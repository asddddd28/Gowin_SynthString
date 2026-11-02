"""Fetch the pinned Apache-2.0 FM1 factory parameters, without device access."""
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
COMMIT='4c7496daac04a95ff10d1afdcc8f9ead2dbabc41'
BASE=f'https://raw.githubusercontent.com/m-vave/fm1_open/{COMMIT}/'
EXPECTED='ecad0b8620f9d784d46c8da1e3c5de02c40214649ed8dec218026431046aad25'


def fetch():
    folder=ROOT/'assets/fm1';folder.mkdir(parents=True,exist_ok=True)
    source=urllib.request.urlopen(BASE+'app/fm_factory.inc',timeout=30).read()
    text=source.decode('utf-8')
    packed=[int(x) for x in re.findall(r'\d+',text.split('factory_packed[] = {',1)[1].split('}',1)[0])]
    raw=bytearray();index=0
    while index<len(packed):
        token=packed[index];index+=1
        if token<128:raw.append(token)
        else:
            low=packed[index];index+=1;distance=low&127
            if low&128:distance|=packed[index]<<7;index+=1
            if not 0<distance<=len(raw):raise ValueError('invalid compressed distance')
            for _ in range(token-125):raw.append(raw[-distance])
        if len(raw)>16384:raise ValueError('factory image exceeds expected length')
    if len(raw)!=16384 or hashlib.sha256(raw).hexdigest()!=EXPECTED:raise ValueError('factory SHA mismatch')
    (folder/'factory.vmem').write_bytes(raw)
    (folder/'factory_packed.inc').write_bytes(source)
    # Preserve the source's complete license notices, rather than assuming the
    # application's GPL license applies to this separately licensed resource.
    notices=urllib.request.urlopen(BASE+'THIRD_PARTY.md',timeout=30).read()
    (folder/'UPSTREAM_NOTICES.md').write_bytes(notices)
    (folder/'SOURCE.json').write_text(json.dumps(dict(repository='https://github.com/m-vave/fm1_open',commit=COMMIT,
        source='app/fm_factory.inc',source_sha256=hashlib.sha256(source).hexdigest(),vmem_sha256=EXPECTED,
        voices=128,bytes=len(raw),license='Apache-2.0',modification='Lossless unpacking only; original parameters and order retained'),indent=2)+'\n',encoding='utf-8')
    print('Verified FM1 factory:',len(raw),'bytes /128 voices')


if __name__=='__main__':fetch()
