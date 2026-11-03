"""Read-only card recheck with immutable session backup and guaranteed SRAM rollback."""
from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
DIAG=ROOT.parents[1]/'demo_test/diagnostics/sd_card'
OUT=ROOT/'reports/sequencer/sd-recheck-20261103'
sys.path.insert(0,str(DIAG))
from sd_transport import Bridge,Card,partition_info
import serial

PROGRAMMER='C:/Gowin/Gowin_V1.9.11.03_Education_x64/Programmer/bin/programmer_cli.exe'
ROLLBACK=ROOT/'reports/synthui-hdmi/build-touch-final/impl/pnr/synth_hdmi.fs'
ROLLBACK_HASH='20c30c9c923c9cba505801edbe5fcd41ece2ea165a5625aa06338bb5b08136f5'


def program(path,name):
    guard=serial.Serial(port=None,baudrate=115200,timeout=.02);guard.dtr=False;guard.rts=False;guard.port='COM4';guard.open()
    try:
        result=subprocess.run([PROGRAMMER,'--device','GW5AT-60B','--cable-index','4','--run','2','--frequency','15MHz','--fsFile',str(path)],capture_output=True,text=True,errors='replace',timeout=90)
    finally:guard.close()
    log=result.stdout+result.stderr;(OUT/f'{name}.log').write_text(log,encoding='utf-8')
    assert result.returncode==0 and 'Finished.' in log,log[-1800:]
    print('PASS SRAM',name,hashlib.sha256(path.read_bytes()).hexdigest(),flush=True)


def backup():
    OUT.mkdir(exist_ok=False)
    assert hashlib.sha256(ROLLBACK.read_bytes()).hexdigest()==ROLLBACK_HASH
    session=Path('\\\\?\\'+str(Path(os.environ['LOCALAPPDATA'])/'SynthString/voice-engine/COM4.json'))
    data=session.read_bytes();saved=json.loads(data)
    assert saved.get('pending') is None and saved.get('wave') is None,'Resolve unfinished command/wave before SRAM reset'
    (OUT/'session-COM4.json').write_bytes(data)
    shutil.copyfile(ROOT/'app/TangSynthStudio.exe',OUT/'TangSynthStudio.exe')
    shutil.copyfile(ROLLBACK,OUT/'rollback.fs')
    record={'time':datetime.datetime.now().astimezone().isoformat(),'rollback_source':str(ROLLBACK),
            'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()}}
    (OUT/'backup.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print('PASS latest user session backup; wave',saved.get('wave_name'),'volume',saved['volume'],flush=True)


def diagnose():
    report={'time':datetime.datetime.now().astimezone().isoformat(),'mode':'read-only','ok':False}
    bridge=None;card=None
    try:
        bridge=Bridge();card=Card(bridge)
        report['identity']=card.initialize();print('Card initialized',report['identity']['product'],flush=True)
        mbr=card.read_block(0);(OUT/'lba0.bin').write_bytes(mbr)
        bridge.fast=True
        assert card.read_block(0)==mbr,'slow/fast LBA0 mismatch'
        base,partition=partition_info(card,mbr);report['partition']=partition;report['partition_lba']=base
        print('Partition verified',base,flush=True)
        sectors=[];previous={}
        for fast in (False,True):
            bridge.fast=fast
            for offset in (0,1,11,12,13,23):
                lba=base+offset;data=card.read_block(lba)
                if fast:assert previous[lba]==data,'slow/fast boot mismatch'
                previous[lba]=data;(OUT/f'lba-{lba}-{"fast" if fast else "slow"}.bin').write_bytes(data)
                sectors.append(dict(lba=lba,fast=fast,nonzero=sum(b!=0 for b in data),sha256=hashlib.sha256(data).hexdigest(),prefix=data[:32].hex()))
                print('Read',lba,'fast' if fast else 'slow','nonzero',sectors[-1]['nonzero'],flush=True)
        report['sectors']=sectors
        boot=previous[base];backup_boot=previous[base+12]
        report['exfat_boot_signature']=boot[3:11]==b'EXFAT   ' and boot[510:512]==b'\x55\xaa'
        report['exfat_backup_signature']=backup_boot[3:11]==b'EXFAT   ' and backup_boot[510:512]==b'\x55\xaa'
        report['ok']=report['exfat_boot_signature'] and report['exfat_backup_signature']
        if not report['ok']:report['error']='exFAT boot signature missing; no writes attempted'
        print('Current exFAT boot validation',report['ok'],flush=True)
    except Exception as error:
        report['error']=repr(error);print('SD CHECK ERROR',repr(error),flush=True)
    finally:
        if card:report.update(read_count=card.read_count,write_count=card.write_count,commands=card.commands)
        if bridge:bridge.close()
        (OUT/'card-result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':
    backup()
    try:
        program(DIAG/'impl/pnr/sd_card.fs','program-diagnostic')
        diagnose()
    finally:
        program(OUT/'rollback.fs','restore-original-firmware')
        print('Original synth SRAM restored; user patches still need restore_session.py',flush=True)
