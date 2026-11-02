"""Offline reference audio, not a recording of FPGA or FM1 hardware."""
import json
import struct
import wave
from dx7_bank import ROOT, INITIAL, convert
from dx7_validation import rows
from compile_voice_patch import compile_patch, RATE, UNITY
from voice_engine_model import VoiceModel


def main():
    out=ROOT/'reports/fm1-audio';out.mkdir(exist_ok=True)
    source=(ROOT/'assets/fm1/factory.vmem').read_bytes();report=[]
    for n in INITIAL:
        patch=convert(source[n*128:(n+1)*128],n)
        model=VoiceModel(rows(compile_patch(patch)));samples=[]
        # Single note then played chord; velocity and release remain unprocessed.
        schedule={0:[(60,72)],int(RATE*1.2):[(48,110),(55,90),(60,100)]}
        for frame in range(round(RATE*2.8)):
            if frame in schedule:
                for note,velocity in schedule[frame]:
                    identity=frame+note
                    inc=round(440*2**((note-69)/12)*(1<<32)/RATE)
                    model.on(identity,inc,note=note,velocity=velocity)
            if frame in (int(RATE*0.8),int(RATE*2.1)):
                for v in model.voices:
                    if v:model.off(v['id'])
            samples.append(model.frame())
        # Uniform +12 dB audition gain for all files; no per-preset normalization.
        pcm=bytearray();clipped=0
        for pair in samples:
            for value in pair:
                sample=round(value*4*32767/UNITY)
                if abs(sample)>32767:clipped+=1
                pcm.extend(struct.pack('<h',max(-32768,min(32767,sample))))
        name=f'{n:03d}_{patch["name"].replace(" ","_")}.wav'
        with wave.open(str(out/name),'wb') as file:
            file.setparams((2,2,round(RATE),0,'NONE','not compressed'));file.writeframes(pcm)
        report.append(dict(program=n,name=patch['name'],file=name,reference_model=True,
            source_rate=RATE,wav_header_rate=round(RATE),audition_gain=4,clipped_samples=clipped,
            peak=max(abs(v) for pair in samples for v in pair)/UNITY))
        print('Rendered',name,'clipped',clipped,flush=True)
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    assert all(r['clipped_samples']==0 for r in report)


if __name__=='__main__':main()
