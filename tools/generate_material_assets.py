"""Original offline material studies. No model API, remote images or fonts.
Regenerate assets and the typed material catalogue using Pillow + numpy.
"""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw

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

def render(row, size=600):
    ident, _, _, family, tint, _ = row
    rng = np.random.default_rng(sum(map(ord, ident)))
    yy, xx = np.mgrid[:size, :size] / size
    x = (xx - .50) / .36
    y = (yy - .48) / .33
    angle = np.arctan2(y, x)
    optical = family in {"glass", "iridescent", "bubble", "frost", "jelly", "wax"}
    metal = family in {"metal", "brushed"}
    # The finish is photographed on a small test shape, with matching backdrop and softbox.
    # The profile gently varies across glass, fabric, polished blocks and soft materials.
    if ident in {"liquid_glass", "liquid_chrome", "silk", "satin"}:
        radius = 1 + .12 * np.cos(angle * 3 + .35) + .055 * np.sin(angle * 5)
        distance = np.hypot(x, y) / radius
    elif ident in {"clear_glass", "brushed_aluminum", "felt", "marble", "wood", "paper", "denim", "linen", "resin"}:
        u, v = .94 * x + .34 * y, -.34 * x + .94 * y
        distance = (abs(u) ** 4 + abs(v) ** 4) ** .25
    else:
        distance = np.hypot(x, y) * (1 + .023 * np.sin(angle * 4))
    z = np.sqrt(np.maximum(0, 1 - distance ** 2))
    gy, gx = np.gradient(z)
    nx, ny = -gx * size * .30, -gy * size * .30
    norm = np.sqrt(nx * nx + ny * ny + 1)
    nx, ny, nz = nx / norm, ny / norm, 1 / norm
    tint = np.array([int(tint[i:i+2], 16) / 255 for i in (1, 3, 5)])
    tint = tint ** 2
    noise = rng.normal(0, 1, distance.shape)
    backlight = np.exp(-((x + .55) ** 2 + (y + .75) ** 2) * .47)
    background = (.53 + .29 * backlight - .08 * yy)[..., None] * (.79 + .21 * tint)
    shadow = .31 * np.exp(-((x - .15) / .84) ** 2 * 2 - ((y - 1.025) / .21) ** 2 * 2)
    background *= 1 - shadow[..., None]
    light = np.maximum(0, -nx * .47 - ny * .55 + nz * .69)
    reflected = np.maximum(0, -nx * .29 - ny * .37 + nz * .87)
    strip = np.exp(-((nx + .52) / .36) ** 6 - ((ny + .36 + .18 * nx) / .20) ** 4)
    rim = (1 - nz) ** 3
    weave_u, weave_v = x * 72 + 11 * z, y * 67 - 13 * z
    pattern = np.zeros_like(x)
    if family in {"knit", "linen", "denim"}:
        warp = np.sin(weave_u + (weave_v * .55 if family == "denim" else .6 * np.sin(weave_v)))
        weft = np.sin(weave_v + .42 * np.sin(weave_u))
        pattern = (warp * weft) * .072 + noise * .017
        if family == "knit": pattern += np.cos(x * 19 + 1.8 * np.sin(y * 27)) ** 10 * .11
    elif family in {"silk", "satin", "velvet"}:
        pattern = np.sin(9 * x + 6 * y + 7 * z + 2.8 * np.sin(y * 3)) ** 6 * .18
    elif family == "wood":
        flow = (x - .32 * y + .08 * np.sin(y * 4)) * 43 + z * 7
        pattern = .069 * np.sin(flow) + .037 * np.sin(flow * 2.13 + 2 * x) + .019 * noise
    elif family in {"marble", "stone"}:
        warps = 1.3 * np.sin(3 * y) + .17 * np.sin(22 * y + 2 * x)
        veins = np.exp(-np.abs(np.sin(5 * x + 6 * y + warps)) * 24)
        pattern = -.20 * veins + .035 * np.cos(13 * y - 6 * x) + .011 * noise
    elif family in {"clay", "paper", "fur", "longfur", "felt"}:
        pattern = .018 * noise + .025 * np.sin(x * 44 + 8 * np.sin(y * 39))
    if optical:
        transmitted = (.52 + .18 * np.cos(3 * x + 2.2 * y + z * 4.4) * np.sin(z * 6 - 4 * y))[..., None]
        fog = .28 if family in {"frost", "wax"} else .11
        rgb = transmitted * (1 - fog) * (.76 + .24 * tint) + tint * fog
        rgb *= (.44 + .56 * nz)[..., None]
        bend = .11 * np.exp(-((ny - .52 + nx * .21) / .16) ** 2) * (1 - nz * .4)
        rgb += tint * (bend + .12 * z)[..., None]
        rgb += (np.array([.25, .32, .47]) * rim[..., None])
        rgb += (strip * (.33 if fog > .2 else .55) + reflected ** 33 * .30)[..., None]
        if family == "iridescent":
            rgb += np.stack([np.cos(nz * 9 + y * 2 + k) * .13 for k in (0, 2.3, 4.5)], axis=-1)
        if family == "bubble":
            for a, b, r in rng.uniform((-.7, -.7, .017), (.7, .7, .070), (22, 3)):
                bubble = np.hypot(x - a, y - b)
                rgb += (.23 * np.exp(-((bubble - r) / .009) ** 2) - .11 * np.exp(-(bubble / r) ** 2))[..., None]
        if family in {"frost", "wax"}: rgb += noise[..., None] * .009
    elif metal:
        reflection = .14 + .48 * np.exp(-((ny + .58 + .15 * nx) / .31) ** 8)
        reflection += .29 * np.exp(-((ny - .40 - .33 * nx) / .38) ** 6) + .17 * light
        if family == "brushed": reflection = .30 + .50 * light + .045 * np.sin(y * 980) + .025 * noise
        rgb = (.18 + .82 * tint) * reflection[..., None]
        rgb += (strip * .27 + rim * .12)[..., None]
    else:
        rgb = tint * (.25 + .63 * light + pattern)[..., None]
        gloss = .36 if family == "ceramic" else .14 if family in {"silk", "satin", "matte"} else .07
        rgb += (reflected ** 18 * gloss + rim * .045)[..., None]
    mask = np.clip((1.003 - distance) * size / 2.5, 0, 1)[..., None]
    composite = background * (1 - mask) + rgb * mask
    composite += noise[..., None] * .0015
    raster = Image.fromarray((np.clip(composite, 0, 1) ** .47 * 255).astype("uint8")).convert("RGB")
    if family in {"fur", "longfur", "felt", "velvet"}:
        draw = ImageDraw.Draw(raster, 'RGBA')
        for _ in range(28500 if family == 'longfur' else 33500):
            a, b = rng.uniform(-1.015, 1.015, 2)
            if a*a + b*b > 1.015: continue
            depth = math.sqrt(max(0, 1 - a*a - b*b))
            length = rng.uniform(3.0, 23.0 if family == 'longfur' else 10.0 if family == 'fur' else 5.5)
            profile = .28 + .66 * max(0, -.35*a - .46*b + .78*depth)
            blend = math.sqrt(profile) + rng.uniform(-.16, .18)
            color = tuple(np.clip((tint ** .47) * blend * 255, 0, 255).astype(int)) + (int(rng.integers(35, 147)),)
            px, py = size*(.50 + a*.36), size*(.48 + b*.33)
            dx, dy = (.37 + a * .9) * length, (.82 + b * .35) * length
            draw.line([(px, py), (px + dx * .56, py + dy * .57), (px + dx, py + dy)], fill=color, width=1)
    return raster.resize((384, 384), Image.Resampling.LANCZOS)


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
