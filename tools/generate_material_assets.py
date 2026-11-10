"""Original offline material studies. No model API, remote images or fonts.
Regenerate assets and the typed material catalogue using Pillow + numpy.
"""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
# id, category, name, family, base tint, original physical description
ROWS = [
('liquid_glass','光透','液态玻璃','glass','#8ec9ef','流动感透明玻璃，圆润边缘，清晰折射与细腻焦散'),
('frosted_glass','光透','磨砂玻璃','frost','#b6c9df','微蚀刻磨砂玻璃，均匀漫透射，柔和散射高光'),
('clear_glass','光透','超白玻璃','glass','#cbe7eb','低铁超白玻璃，高通透度，中性无色折射'),
('soft_glass','光透','柔光玻璃','frost','#e3b6d4','柔光玻璃，乳白透光层次，柔和边缘高光'),
('iridescent_glass','光透','虹彩玻璃','iridescent','#bea2e9','薄膜虹彩玻璃，随视角变化的紫青粉色干涉光泽'),
('bubble_glass','光透','气泡玻璃','bubble','#9fcad4','透明手工玻璃，内部细小气泡，真实透射与折射'),
('colored_glaze','光透','琉璃','glass','#6cb9b7','通透彩色琉璃，浓淡渐变，圆润光泽与内部层次'),
('jelly','光透','半透果冻','jelly','#eea6c0','半透明果冻，柔软体积感，次表面散射与湿润光泽'),
('sherpa','毛绒','羊羔绒','fur','#ece0ca','蓬松羊羔绒，细密卷曲短绒，温暖柔软触感'),
('long_fur','毛绒','长毛绒','longfur','#d9b8d6','细长蓬松毛绒，根根分明的柔软纤维与自然绒毛轮廓'),
('short_plush','毛绒','短毛绒','fur','#a2c5e2','均匀细密短毛绒，柔软起伏，绒毛顺光方向清晰'),
('velvet','毛绒','天鹅绒','velvet','#845c9c','细腻天鹅绒，深色绒面与掠射柔光，丰富明暗层次'),
('knit','毛绒','针织毛线','knit','#d8a5aa','粗细自然的针织毛线，交织线圈，柔软纤维细节'),
('felt','毛绒','羊毛毡','felt','#adbf9f','致密羊毛毡，细微交错纤维，哑光温润表面'),
('mirror_silver','金属','镜面银','metal','#dce3ea','镜面银金属，清晰环境反射，锐利高光与真实金属质感'),
('brushed_aluminum','金属','拉丝铝','brushed','#b9c8d5','拉丝铝合金，方向性细密纹路，克制反射'),
('champagne_gold','金属','香槟金','metal','#d8b77e','香槟金金属，温暖高光，细腻柔亮反射'),
('liquid_chrome','金属','液态铬','metal','#98a8c1','液态铬金属，流动曲面，强烈而真实的镜面反射'),
('patina','金属','氧化铜','stone','#81a69b','氧化铜，细腻青绿铜锈与露铜区域，真实磨损纹理'),
('porcelain','自然','白瓷','ceramic','#e9e4da','温润白瓷，薄釉光泽，细腻平滑表面'),
('clay','自然','陶土','clay','#c58f78','自然陶土，微小颗粒，温暖哑光与手作痕迹'),
('marble','自然','大理石','marble','#dddcd5','白色大理石，克制灰色天然纹脉与抛光光泽'),
('wood','自然','原木','wood','#bd916d','温润原木，连续天然木纹，细腻开放毛孔'),
('paper','自然','宣纸','paper','#e6dec8','柔软宣纸，细小植物纤维与自然透光层次'),
('silicone','软塑','软硅胶','matte','#b6c4e5','柔软硅胶，均匀细腻哑光，圆润触感'),
('resin','软塑','亚光树脂','matte','#d9b0ad','亚光树脂，轻微漫反射，干净平整的细腻表面'),
('gummy','软塑','亮面软糖','jelly','#db9f72','半透明软糖，轻微含糖微粒，柔软湿润高光'),
('wax','软塑','半透蜡','wax','#e5c3a0','半透明蜡，柔和次表面散射，温暖柔光'),
('silk','织物','丝绸','silk','#b2acd9','轻盈丝绸，顺滑细腻织纹，流动的方向性高光'),
('linen','织物','亚麻','linen','#d3c6ac','天然亚麻，清晰经纬纤维，朴素柔和的哑光'),
('denim','织物','牛仔','denim','#6d91b8','靛蓝牛仔布，真实斜纹织法与细微磨白'),
('satin','织物','褶皱缎','satin','#d7acbc','细腻缎面，柔和褶皱，连续流动的光泽层次'),
]

def render(row, size=320):
    ident, _, _, family, tint, _ = row
    rng = np.random.default_rng(sum(map(ord,ident)))
    yy,xx=np.mgrid[:size,:size]; x=(xx-size*.5)/(size*.34); y=(yy-size*.48)/(size*.34)
    r2=x*x+y*y; inside=r2<=1; z=np.sqrt(np.maximum(0,1-r2))
    base=np.array([int(tint[i:i+2],16) for i in (1,3,5)])/255
    bg=np.empty((size,size,3)); bg[:]=[.92,.925,.94]
    bg += ((xx/size+yy/size)*.025)[...,None]
    shadow=np.exp(-((x/.9)**2+((y-1.02)/.13)**2)*2)*.22
    bg-=shadow[...,None]
    light=np.clip(-x*.35-y*.5+z*.78,0,1); noise=rng.normal(0,1,(size,size))
    diffuse=.32+.64*light
    rgb=base*diffuse[...,None]
    spec=np.exp(-(((x+.37)/.25)**2+((y+.48)/.12)**2))*z
    rim=(1-z)**3
    if family in ['glass','iridescent','bubble','jelly','frost','wax']:
        pattern=(np.sin(x*5+z*3)+np.cos(y*5-z*4))*.05
        rgb=bg*(.72 if family=='glass' else .46)+base*(.22+.16*z[...,None])
        rgb+=pattern[...,None]
        rgb-=rim[...,None]*.19
        rgb+=np.maximum(0,np.sin((x-y)*3+z*5))[...,None]*.06
        if family=='iridescent':
            rgb=.55*rgb+.45*np.stack([.65+.3*np.sin(z*8+x*2+k) for k in [0,2,4]],axis=-1)
        if family=='frost':rgb=rgb*.97+noise[...,None]*.014
        if family=='bubble':
            for _ in range(24):
                a,b=rng.uniform(-.72,.72,2);rad=rng.uniform(.025,.09)
                d=np.sqrt((x-a)**2+(y-b)**2)
                rgb += np.exp(-((d-rad)/.008)**2)[...,None]*.25
        rgb+=spec[...,None]*(.24 if family in ['frost','wax'] else .6)
        rgb+=np.exp(-((np.sqrt(r2)-.965)/.018)**2)[...,None]*.22
    elif family in ['metal','brushed']:
        waves=np.clip(.25+.28*np.sin(y*7+z*2)+.3*light,0,1)
        rgb=base*waves[...,None]+spec[...,None]*.9
        rgb+=np.exp(-((y+.36+x*.22)/.08)**2)[...,None]*.36
        if family=='brushed':rgb+=(np.sin(y*760)*.025+noise*.012)[...,None]
    else:
        if family=='marble':
            veins=np.exp(-np.abs(np.sin(x*4+y*3+np.sin(y*5)*.6)) *35)
            rgb-=veins[...,None]*.27
        if family=='wood':rgb+=(np.sin(x*24+np.sin(y*2)*2+z*4)*.055)[...,None]
        if family in ['knit','linen','denim']:
            t=(np.sin(x*80+(y*55 if family=='denim' else 0))*np.sin(y*95))*.09
            rgb+=t[...,None]+noise[...,None]*.018
        if family in ['silk','satin','velvet']:
            wave=np.sin(x*5+y*3+z*4)**6
            rgb+=wave[...,None]*(.24 if family!='velvet' else .12)
        rgb+=noise[...,None]*(.03 if family in ['clay','felt','paper','stone'] else .006)
        rgb+=spec[...,None]*(.45 if family=='ceramic' else .06)
    rgb=np.clip(rgb,0,1); bg[inside]=rgb[inside]
    im=Image.fromarray((np.clip(bg,0,1)*255).astype('uint8')).convert('RGB')
    if family in ['fur','longfur','felt','velvet']:
        draw=ImageDraw.Draw(im)
        count=11500 if family!='longfur' else 9000
        for _ in range(count):
            a,b=rng.uniform(-1,1,2)
            if a*a+b*b>.99:continue
            zz=math.sqrt(1-a*a-b*b); length=rng.uniform(3,12 if family=='longfur' else 5)
            px=size*(.5+a*.34);py=size*(.48+b*.34)
            bright=.38+.6*max(0,-a*.35-b*.5+zz*.78)+rng.uniform(-.10,.13)
            col=tuple(np.clip(base*bright*255,0,255).astype(int))
            dx=a*length*.6+rng.uniform(-2,2);dy=-length*(.3+zz*.7)
            draw.line([(px,py),(px+dx,py+dy)],fill=col,width=1)
    return im.resize((256,256),Image.Resampling.LANCZOS)

def main():
    dest=ROOT/'assets/materials';dest.mkdir(parents=True,exist_ok=True)
    for row in ROWS:render(row).save(dest/(row[0]+'.webp'),quality=91,method=6)
    definitions='\n'.join('  StudioMaterial('+', '.join(json.dumps(v,ensure_ascii=False) for v in [r[0],r[1],r[2],r[5]])+'),' for r in ROWS)
    (ROOT/'lib/core/materials.dart').write_text('''// Original material descriptions and offline previews, generated by tools/generate_material_assets.py.
class StudioMaterial {
  final String id, category, name, description;
  const StudioMaterial(this.id, this.category, this.name, this.description);
  String get preview => 'assets/materials/$id.webp';
}
const materialCategories = ['光透', '毛绒', '金属', '自然', '软塑', '织物'];
const studioMaterials = [
'''+definitions+'''
];
StudioMaterial? materialById(String? id) {
  for (final material in studioMaterials) {
    if (material.id == id) return material;
  }
  return null;
}
String withMaterial(String original, String? id) {
  final material = materialById(id);
  if (material == null) return original;
  return '$original\\n\\n[材质偏好 · ${material.name}]\\n${material.description}。原提示词为最高优先级；如材质偏好与原提示词冲突，以原提示词为准。仅作用于适合呈现该材质的主体表面；保持主体、身份、数量、构图、文字与创作意图。除非原提示词明确要求，不将背景或所有物体强制替换为该材质。';
}
''',encoding='utf8')
    print(f'Created {len(ROWS)} original material previews')
if __name__=='__main__':main()
