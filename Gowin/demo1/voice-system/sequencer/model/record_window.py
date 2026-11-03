"""首次录音的小节窗口语义；音乐休止按原时间保留，仅去首尾空小节。"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Note:
    on: int
    off: int | None


def window(notes, stop, bpm=120, ppq=960, early=True):
    """返回(origin, length, notes)，起点可为负以表达录制按下前20ms窗口。"""
    bar = ppq*4
    lead = bpm*8//25 if early else 0
    assert lead < bar
    if not notes:
        return 0,0,()
    origin = (min(note.on for note in notes)+lead)//bar*bar-lead
    cutoff = (stop+lead)//bar*bar-lead
    # Only complete windows are retained. A note exactly on cutoff is next bar.
    saved = [note for note in notes if origin <= note.on < cutoff]
    if not saved:
        return origin,0,()
    # Held notes occupy the entire elapsed interval; do not call that silence.
    last = max(cutoff if note.off is None else min(cutoff,note.off) for note in saved)
    occupied_end = ((last+lead+bar-1)//bar)*bar-lead
    end = min(cutoff,occupied_end)
    return origin,end-origin,tuple(Note(note.on-origin,None if note.off is None or note.off>=end else note.off-origin) for note in saved)


def verify():
    bar=3840; lead=38
    for first,expected in [(bar-lead-1,3839),(bar-lead,0),(bar-lead+1,1),(bar-1,37),(bar,38),(bar+1,39)]:
        origin,length,notes=window([Note(first,bar+120)],3*bar+40)
        assert notes[0].on==expected
        assert length==(2*bar if first==bar-lead-1 else bar)
    origin,length,notes=window([Note(3*bar+40,3*bar+960)],6*bar)
    assert length==bar and notes[0].on==78  # Lead-in and trailing blank bars removed.
    assert window([Note(10,None)],3*bar)[1]==3*bar  # Held pad is not empty.
    assert window([Note(10,30),Note(2*bar+20,2*bar+40)],4*bar)[1]==3*bar
    assert window([],4*bar)[1]==0
    assert window([Note(10,30)],100)[1]==0
    for bpm in range(20,301):
        assert 0 <= 20-bpm*8//25/(bpm*16)*1000 < 1000/(bpm*16)
    print('PASS early window: six boundary positions, leading/trailing empty bars, middle rests, held notes, no full bar, BPM20..300')


if __name__=='__main__':verify()
