from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[1]
n = 768
icon = Image.new('RGB', (n, n))
pixels = icon.load()
for y in range(n):
    for x in range(n):
        d = math.hypot((x-n*.3)/n, (y-n*.22)/n)
        glow = max(0, 1-d)
        pixels[x,y] = (int(18+glow*24),int(35+glow*40),int(29+glow*27))
overlay = Image.new('RGBA', (n,n))
for tilt in (-32, 32):
    lens = Image.new('RGBA',(n,n))
    draw = ImageDraw.Draw(lens)
    draw.ellipse((n*.24,n*.13,n*.76,n*.87),fill=(170,238,198,25),outline=(186,245,208,215),width=12)
    draw.arc((n*.25,n*.14,n*.75,n*.86),185,310,fill=(255,255,245,245),width=6)
    lens = lens.rotate(tilt,resample=Image.Resampling.BICUBIC)
    overlay.alpha_composite(lens)
shadow = overlay.filter(ImageFilter.GaussianBlur(21))
base = icon.convert('RGBA'); base.alpha_composite(shadow); base.alpha_composite(overlay)
draw=ImageDraw.Draw(base)
cx,cy=n*.5,n*.5
draw.polygon([(cx,cy-39),(cx+10,cy-10),(cx+39,cy),(cx+10,cy+10),(cx,cy+39),(cx-10,cy+10),(cx-39,cy),(cx-10,cy-10)],fill=(239,255,231,255))
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    directory=root/'android/app/src/main/res'/f'mipmap-{density}'
    directory.mkdir(parents=True,exist_ok=True)
    base.resize((size,size),Image.Resampling.LANCZOS).save(directory/'ic_launcher.png')
base.resize((512,512),Image.Resampling.LANCZOS).save(root/'assets/app_icon.png')
