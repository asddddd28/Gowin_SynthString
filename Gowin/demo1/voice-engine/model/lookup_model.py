"""Snapshot lookup ordering; reference to verify a multicycle CAM without RTL parsing."""
import random


def lookup(active, identities, ages, identity):
    matches=[i for i in range(8) if active[i] and identities[i]==identity]
    if matches:return matches[-1],True
    free=[i for i in range(8) if not active[i]]
    if free:return free[0],False
    return min(range(8),key=lambda i:ages[i]),False


def incremental(active,identities,ages,identity):
    found=free=False;match=first=oldest_slot=0;oldest=(1<<64)-1
    for i in range(8):
        if active[i] and ages[i]<oldest:oldest,oldest_slot=ages[i],i
        if not active[i] and not free:free,first=True,i
        if active[i] and identities[i]==identity:found,match=True,i
    return (match if found else first if free else oldest_slot),found


if __name__=='__main__':
    rng=random.Random(0x43414d)
    for n in range(20000):
        active=[bool(rng.getrandbits(1)) for _ in range(8)]
        ids=[rng.randrange(10) for _ in range(8)]
        ages=[rng.getrandbits(64) for _ in range(8)]
        if n%7==0:ages=[0]*8
        note=rng.randrange(10)
        assert lookup(active,ids,ages,note)==incremental(active,ids,ages,note)
    print('PASS lookup model: 20000 snapshots, first-free / exact-last / oldest-first tie order')
