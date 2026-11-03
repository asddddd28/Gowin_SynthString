"""Check actual RTL frames against independent tab geometry and unchanged content."""
import json
from pathlib import Path
from PIL import Image
from display_model import PAGES, navigation_pixel

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'reports/hdmi-tabs'
FRAMES = ROOT / 'reports/sequencer/tabs-video-unit'
BASE = ROOT / 'reports/sequencer/library-video-unit'
FONT = [int(x, 16) for x in (ROOT/'hdmi/assets/font.hex').read_text().split()]
FILES = ('overview', 'patches', 'operators', 'modulation', 'effects', 'system',
         'sequences', 'presets', 'calibration')


def expected_pixel(page, x, y):
    """Original 5x7 font, doubled inside 12x16 cells; coordinates are absolute."""
    background = navigation_pixel(page, x, y)
    if background is None:
        return 0x101820
    tab = (x-24)//156
    left = 24+tab*156+((12-len(PAGES[tab]))//2)*12
    relative = x-left
    glyph = False
    if 80 <= y < 94 and 0 <= relative < len(PAGES[tab])*12 and relative%12 < 10:
        code = ord(PAGES[tab][relative//12])
        glyph = bool(FONT[code*8+(y-80)//2] & (1 << (4-(relative%12)//2)))
    return navigation_pixel(page, x, y, glyph)


def main():
    results = {}
    for index, name in enumerate(FILES):
        page = index if index < 8 else 0
        actual = Image.open(FRAMES/f'{name}.ppm').convert('RGB')
        baseline = Image.open(BASE/f'{name}.ppm').convert('RGB')
        assert actual.size == (1280, 720)
        pixels = actual.load()
        for y in range(64, 112):
            for x in range(1280):
                value = expected_pixel(page, x, y)
                expected = (value>>16, (value>>8)&255, value&255)
                assert pixels[x,y] == expected, (name,x,y,pixels[x,y],expected)
        # Content panels, plots, key highlights and calibration overlay are exact.
        for box in ((0,0,1280,64), (0,144,1280,720)):
            assert actual.crop(box).tobytes() == baseline.crop(box).tobytes(), (name,box)
        assert actual.crop((0,128,1280,144)).tobytes() == baseline.crop((0,112,1280,128)).tobytes()
        assert actual.crop((0,112,1280,128)).tobytes() == bytes((16,24,32))*(1280*16)
        actual.save(OUT/f'{name}.png')
        results[name] = dict(selected=page, tabs=8, gutter_px=12, tab_px=[144,48],
                             matched_navigation_pixels=1280*48, other_content_exact=True)
    (OUT/'pixel-validation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print('PASS nine RTL frames: separated cards, one selected tab, exact glyph colors, unchanged content')


if __name__ == '__main__':
    main()
