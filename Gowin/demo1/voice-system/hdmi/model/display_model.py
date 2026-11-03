"""HDMI contract model: bounded audio observer, page navigation and DFT reference."""
import math

RATE = 50_000_000 / 1024
PAGES = ("OVERVIEW", "PATCHES", "OPERATORS", "MODULATION", "EFFECTS", "SYSTEM", "SEQUENCES", "SD PRESETS")

def navigation_pixel(page, x, y, glyph=False):
    """Eight 144x48 tabs, 12px gutters; return None outside navigation cards."""
    if not 64 <= y < 112 or x < 24:
        return None
    tab, offset = divmod(x - 24, 156)
    if tab >= 8 or offset >= 144:
        return None
    if glyph:
        return 0x101820 if tab == page else 0xdce8ed
    return 0xefad73 if tab == page else 0x21323f

def spectrum(samples):
    """Exact signed fixed-point reference for the hardware 256-sample DFT."""
    assert len(samples) == 256
    bins = []
    for band in range(1, 65):
        real = imag = 0
        for index, sample in enumerate(samples):
            phase = (index * band) & 255
            real += (sample * round(32767 * math.cos(phase * math.tau / 256))) >> 15
            imag += (sample * round(32767 * math.sin(phase * math.tau / 256))) >> 15
        magnitude=abs(real)+abs(imag)
        bit=magnitude.bit_length()-1
        bins.append(127 if bit>=22 else 0 if bit<10 else 8+10*(bit-10)+((magnitude>>(bit-3))&7))
    return bins

def navigate(page, direction):
    return (page + direction) % len(PAGES)

def joystick_axis(pair):
    """Electrical order bit0=H, bit1=L: low/centre/high, invalid ignored."""
    return {0: -1, 1: 0, 3: 1}.get(pair)

def joystick_event(previous_armed, pair):
    region=joystick_axis(pair)
    return (region==0, region if previous_armed and region in (-1,1) else 0)

def wave_shift(samples):
    peak=max(map(abs,samples))
    if peak<64:return 0
    for shift in range(7,0,-1):
        if peak<(32768>>shift):return shift
    return 0

def triggered_capture(samples, previous_peak=0, timeout=2048):
    """Acquire256 consecutive PCM samples at a hysteretic rising crossing.

    Waiting is display-only and bounded; silence/DC still publishes fresh data.
    No circular rotation, padding or interpolation is allowed in the capture.
    """
    threshold=max(4,previous_peak>>4)
    armed=False
    for index,value in enumerate(samples):
        triggered=armed and value>=0
        if triggered or index==timeout-1:
            result=samples[index:index+256]
            assert len(result)==256
            return index,result,triggered
        if value<=-threshold:armed=True
    raise ValueError('Insufficient input stream for trigger or timeout')

if __name__ == "__main__":
    samples = [round(28000 * math.sin(math.tau * 8 * i / 256)) for i in range(256)]
    values = spectrum(samples)
    assert values.index(max(values)) == 7
    assert navigate(7, 1) == 0 and navigate(0, -1) == 7
    armed=False
    events=[]
    for pair in (3,3,1,0,0,1,3,3,1,2,0,1):
        armed,event=joystick_event(armed,pair);events.append(event)
    assert events==[0,0,0,-1,0,0,1,0,0,0,0,0]
    for offset in (3,13,25):
        stream=[round(1000*math.sin(math.tau*(i+offset)/32)) for i in range(2304)]
        start,block,locked=triggered_capture(stream)
        assert locked and block[0]==0 and block[1]>0
    for value in (0,400):
        start,block,locked=triggered_capture([value]*2304)
        assert start==2047 and not locked and block==[value]*256
    print("PASS: 256-sample fixed-point DFT, eight-page wrap")
