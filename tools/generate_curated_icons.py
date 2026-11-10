from pathlib import Path
import numpy as np,math
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
PRESETS=[('orb_blue_glass','极光之环',['#162c6b','#6999ee','#e4a9d5']),('orbit_teal_glass','青屿流光',['#103f3d','#45a89c','#ced59a']),('orb_amber_glass','日落鎏金',['#673850','#edb17b','#d887ab']),('orbit_violet_glass','鸢尾星云',['#302766','#a38be0','#e9b2d9']),('orb_rose_glass','蔷薇月色',['#6c2449','#db8daf','#efcfae']),('orbit_graphite_glass','冰川月白',['#293b57','#92bed7','#c2cbe7']),('spark_teal_glass','森境微光',['#173e35','#8bbd9e','#d1dba3']),('spark_amber_glass','赤陶余晖',['#623c39','#d5a18d','#e6c59e'])]
def render(colors,index):
 n=640;y,x=np.mgrid[:n,:n];u=x/n;v=y/n
 rgb=[np.array([int(h[i:i+2],16) for i in (1,3,5)])/255 for h in colors]
 t=np.clip(u*.6+v*.4,0,1);a=rgb[0]*(1-t[...,None])+rgb[1]*t[...,None]
 glow=np.exp(-((u-.83)**2+(v-.2)**2)*5)[...,None];a=a*(1-glow*.65)+rgb[2]*glow*.65
 im=Image.fromarray((np.clip(a,0,1)*255).astype('uint8')).convert('RGBA')
 layer=Image.new('RGBA',(n,n));d=ImageDraw.Draw(layer)
 d.ellipse((n*.27,n*.27,n*.73,n*.73),fill=(235,255,255,26))
 im=Image.alpha_composite(im,layer.filter(ImageFilter.GaussianBlur(18)))
 for angle in [-32+index*3,32-index*2]:
  ring=Image.new('RGBA',(n,n));q=ImageDraw.Draw(ring)
  q.ellipse((n*.29,n*.19,n*.71,n*.81),outline=(219,251,244,220),width=6)
  q.arc((n*.30,n*.20,n*.70,n*.80),195,300,fill=(255,255,255,245),width=3)
  ring=ring.rotate(angle,resample=Image.Resampling.BICUBIC)
  im=Image.alpha_composite(im,ring)
 d=ImageDraw.Draw(im);cx=n*.5;cy=n*.5;r=n*.064
 points=[]
 for k in range(8):
  angle=k*math.pi/4;rad=r if k%2==0 else r*.24;points.append((cx+math.cos(angle)*rad,cy+math.sin(angle)*rad))
 d.polygon(points,fill=(247,255,245,255));d.ellipse((n*.66,n*.26,n*.68,n*.28),fill=(255,255,255,230))
 return im.resize((256,256),Image.Resampling.LANCZOS).convert('RGB')
if __name__=='__main__':
 (ROOT/'assets/icons').mkdir(exist_ok=True)
 for i,(id,name,colors) in enumerate(PRESETS):
  image=render(colors,i)
  for path in [ROOT/f'assets/icons/{id}.webp',ROOT/f'android/app/src/main/res/drawable/icon_{id}.webp']:image.save(path,quality=96,method=6)
 print('Created eight finished gradient orbital icons')
