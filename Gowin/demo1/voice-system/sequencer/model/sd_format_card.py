"""Apply the reviewed exFAT image only to the approved SD card, with rollback firmware.

No disk letters or generic Windows raw devices are opened. Every SD write is
range checked, backed up and read back through the FPGA bridge with CRC16.
"""
from pathlib import Path
import datetime,hashlib,json,os,subprocess,sys,time,zipfile
import sd_recheck as recovery
from sd_d2xx import D2xxBridge
from sd_format_plan import OUT,BASE,SECTORS,CAPACITY,reader,MemoryVolume
from sd_transport import Card,partition_info
from exfat_reference import ExfatVolume

EXPECTED_CID='fe3432534400000020000005e3019a45'
ROOT=recovery.ROOT
SESSION=OUT/'session'


def load_plan(name):
    with zipfile.ZipFile(OUT/(name+'.zip')) as archive:
        result={int(Path(n).stem):archive.read(n) for n in archive.namelist()}
    assert result and all(BASE<=lba<BASE+SECTORS and len(data)==512 for lba,data in result.items())
    return result


def initialize_card(card):
    # The card stays powered during FPGA SRAM replacement. Re-issue its reset
    # sequence if the first CMD0 still returns residual SPI data; all other
    # initialization/CRC failures remain fatal. No writes occur in this loop.
    for attempt in range(3):
        try:return card.initialize()
        except AssertionError as error:
            if error.args!=(('CMD0',63),) or attempt==2:raise
            print('Retry SD reset after residual CMD0 response 0x3f',flush=True)
            card.bridge.release();time.sleep(.02)


def run():
    assert sys.argv[1:] in (['--apply-reviewed-plan'],['--apply-reviewed-plan','--resume-read-only-backup']), 'Explicit reviewed-plan switch required'
    approval=json.loads((OUT/'approval.json').read_text(encoding='utf-8'))
    assert approval['authorized'] and approval['expected_cid']==EXPECTED_CID
    assert not (OUT/'card-result.json').exists(), 'Do not overwrite a prior run; review its journal first'
    format_blocks=load_plan('format');file_blocks=load_plan('file-test')
    plan=json.loads((OUT/'plan.json').read_text())
    assert len(format_blocks)==plan['format_sectors'] and plan['independent_reader_verified']
    all_lbas=sorted(format_blocks.keys()|file_blocks.keys())
    recovery.OUT=SESSION
    if '--resume-read-only-backup' in sys.argv:
        old=json.loads((OUT/'progress.json.initial').read_text(encoding='utf-8'))
        assert old['stage']=='backup' and old['write_count']==0 and not (OUT/'write-journal.jsonl').exists()
        assert hashlib.sha256((SESSION/'rollback.fs').read_bytes()).hexdigest()==recovery.ROLLBACK_HASH
    else:recovery.backup()
    report={'time':datetime.datetime.now().astimezone().isoformat(),'ok':False,'writes_authorized':True,
        'partition_start':BASE,'partition_sectors':SECTORS,'cluster_bytes':131072}
    bridge=None;card=None;started=time.monotonic()
    def publish():
        report['elapsed_seconds']=round(time.monotonic()-started,2)
        if card:report.update(read_count=card.read_count,write_count=card.write_count)
        (OUT/'progress.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    try:
        recovery.program(recovery.DIAG/'impl/pnr/sd_card.fs','program-diagnostic')
        bridge=D2xxBridge();card=Card(bridge)
        identity=initialize_card(card);report['identity']=identity
        assert identity['cid']==EXPECTED_CID and identity['sectors']==CAPACITY,identity
        bridge.fast=True
        base,gpt=partition_info(card,card.read_block(0));report['partition']=gpt
        assert base==BASE and gpt['scheme']=='GPT' and len(gpt['partitions'])==1
        assert gpt['partitions'][0]['sectors']==SECTORS
        print('PASS identity, GPT and approved partition bounds',flush=True)
        # GPT is read and archived, but never appears in a write plan.
        with zipfile.ZipFile(OUT/'gpt-backup.zip','x',zipfile.ZIP_DEFLATED) as archive:
            for lba in list(range(34))+list(range(CAPACITY-33,CAPACITY)):
                archive.writestr(f'{lba}.bin',card.read_block(lba))
        previous={};report['stage']='backup';publish()
        with zipfile.ZipFile(OUT/'metadata-backup.zip','x',zipfile.ZIP_DEFLATED) as archive:
            for i,lba in enumerate(all_lbas):
                data=card.read_block(lba);previous[lba]=data;archive.writestr(f'{lba}.bin',data)
                if i%32==0 or i+1==len(all_lbas):
                    report['backup_done']=i+1;report['backup_total']=len(all_lbas);publish()
                    print(f'Backup {i+1}/{len(all_lbas)} ({time.monotonic()-started:.1f}s)',flush=True)
        report['backup_sha256']=hashlib.sha256((OUT/'metadata-backup.zip').read_bytes()).hexdigest()
        card.allow_write=True
        report['stage']='format';report['format_changed']=sum(previous[k]!=v for k,v in format_blocks.items());publish()
        print('Changed format sectors',report['format_changed'],flush=True)
        # Allocation metadata first; backup boot region, then main boot region.
        order=sorted(format_blocks,key=lambda lba:(2 if BASE<=lba<BASE+12 else 1 if BASE+12<=lba<BASE+24 else 0,lba))
        journal=(OUT/'write-journal.jsonl').open('x',encoding='utf-8')
        def write(lba,data,stage):
            assert BASE<=lba<BASE+SECTORS and lba in previous
            journal.write(json.dumps({'stage':stage,'lba':lba,'state':'intent','sha256':hashlib.sha256(data).hexdigest()})+'\n');journal.flush();os.fsync(journal.fileno())
            card.write_block(lba,data)
            journal.write(json.dumps({'stage':stage,'lba':lba,'state':'verified'})+'\n');journal.flush()
        try:
            for i,lba in enumerate(order):
                if previous[lba]!=format_blocks[lba]:write(lba,format_blocks[lba],'format')
                if i%32==0:report['format_done']=i+1;publish()
            print('PASS format metadata written and read back',flush=True)
            # File data before its allocation bitmap and root directory publication.
            root_lba=BASE+plan['heap_offset']+(plan['root_cluster']-2)*256
            bitmap_lba=BASE+plan['heap_offset']
            report['stage']='file-test';publish()
            for lba in sorted(file_blocks,key=lambda p:(2 if root_lba<=p<root_lba+256 else 1 if bitmap_lba<=p<bitmap_lba+256 else 0,p)):
                current=format_blocks.get(lba,previous[lba])
                if current!=file_blocks[lba]:write(lba,file_blocks[lba],'file-test')
        finally:journal.close()
        # Reset SD protocol and discard all write-side caches before file reads.
        assert initialize_card(card)['cid']==EXPECTED_CID;bridge.fast=True
        cache={}
        def read(lba):
            assert 0<=lba<CAPACITY
            if lba not in cache:cache[lba]=card.read_block(lba)
            return cache[lba]
        report['stage']='fresh-mount';publish()
        volume=ExfatVolume(read,CAPACITY,BASE)
        volume._boot(0,9);volume._boot(12,9)
        verified={}
        for name,expected in plan['files'].items():
            data=volume.read_file(name,8192)
            assert len(data)==expected['length'] and hashlib.sha256(data).hexdigest()==expected['sha256']
            (OUT/('readback-'+name)).write_bytes(data);verified[name]=expected
            print('PASS fresh file read',name,len(data),flush=True)
        # Check actual free-space bitmap, not only its size/first allocation byte.
        bitmap=volume._read(volume.bitmap,1<<20,check_allocated=False)
        bitmap_first=BASE+volume.heap_offset
        expected_bitmap=b''.join(file_blocks.get(bitmap_first+i,format_blocks[bitmap_first+i]) for i in range((len(bitmap)+511)//512))[:len(bitmap)]
        assert bitmap==expected_bitmap
        # Both GPT copies remain byte-identical.
        with zipfile.ZipFile(OUT/'gpt-backup.zip') as archive:
            for name in archive.namelist():assert card.read_block(int(Path(name).stem))==archive.read(name)
        report.update(ok=True,stage='verified',files=verified,main_boot_verified=True,backup_boot_verified=True,
            fresh_sd_initialize=True,gpt_unchanged=True,allocation_bitmap_verified=True)
        print('PASS exFAT 128 KiB clusters, both boots, bitmap, files and unchanged GPT',flush=True)
    except BaseException as error:
        report['error']=repr(error);print('FORMAT ERROR',repr(error),flush=True)
        raise
    finally:
        publish()
        if bridge:
            try:bridge.close()
            except Exception as error:report['bridge_close_error']=repr(error)
        (OUT/'card-result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        recovery.program(SESSION/'rollback.fs','restore-original-firmware')
        with (OUT/'restore-session.log').open('w',encoding='utf-8') as log:
            result=subprocess.run([sys.executable,str(ROOT/'sequencer/model/restore_session.py'),str(SESSION)],stdout=log,stderr=subprocess.STDOUT,timeout=300)
        assert result.returncode==0,'Original firmware restored; session restoration failed, see restore-session.log'
        print('PASS original synth firmware and latest user session restored',flush=True)


if __name__=='__main__':run()
