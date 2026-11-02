"""Code-drawn application mark matching the four bars in the sidebar."""
from pathlib import Path
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]
im=Image.new('RGBA',(256,256),(0,0,0,0));d=ImageDraw.Draw(im)
d.rounded_rectangle((8,8,248,248),radius=50,fill='#263b2d')
for x,h in [(61,65),(98,139),(135,104),(172,57)]:
    d.rounded_rectangle((x,128-h/2,x+23,128+h/2),radius=9,fill='#c7e5ae')
im.save(root/'src-tauri/icons/icon.png')
im.save(root/'src-tauri/icons/icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
