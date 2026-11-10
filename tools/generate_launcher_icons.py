"""Build original adaptive launcher icons with geometric glyphs and offline textures."""
from pathlib import Path
import math,re
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[1]
COLORS={'blue':('#446bdb','#8dbefa'),'violet':('#7754d5','#d7abec'),'rose':('#bc5488','#f6b7be'),'teal':('#218c91','#9cdac7'),'amber':('#b76a34','#f2d29a'),'graphite':('#394557','#9aaabf')}
GLYPHS=['spark','aperture','orb','orbit']
MATERIALS=['glass','frost','ceramic','plush']
def star(draw,x,y,r,fill):
    pts=[]
    for i in range(8):
        a=-math.pi/2+i*math.pi/4;rr=r if i%2==0 else r*.33
        pts.append((x+math.cos(a)*rr,y+math.sin(a)*rr))
    draw.polygon(pts,fill=fill)
def render(glyph,color,material):
    n=512;yy,xx=np.mgrid[:n,:n];u=xx/n;v=yy/n
    def rgb(h):return np.array([int(h[i:i+2],16) for i in (1,3,5)])/255
    a,b=map(rgb,COLORS[color]);t=np.clip((u+v)*.5,0,1)
    arr=a*(1-t[...,None])+b*t[...,None]
    glow=np.exp(-((u-.22)**2+(v-.12)**2)*4)
    arr+=glow[...,None]*(.14 if material!='ceramic' else .06)
    rng=np.random.default_rng(102)
    if material in ['frost','plush']:arr+=rng.normal(0,.018 if material=='frost' else .035,(n,n,1))
    im=Image.fromarray((np.clip(arr,0,1)*255).astype('uint8')).convert('RGBA')
    if material=='glass':
        layer=Image.new('RGBA',(n,n));d=ImageDraw.Draw(layer)
        d.ellipse((-n*.2,-n*.5,n*.95,n*.5),fill=(255,255,255,24))
        d.arc((n*.06,n*.06,n*.94,n*.94),200,285,fill=(255,255,255,95),width=3)
        im=Image.alpha_composite(im,layer)
    if material=='plush':
        d=ImageDraw.Draw(im)
        for _ in range(18000):
            x,y=rng.uniform(0,n,2);shade=(.1+.12*rng.random()); c=tuple((np.clip((a+b)/2+shade,0,1)*255).astype(int))+(70,)
            d.line([(x,y),(x+rng.uniform(-3,3),y-rng.uniform(2,7))],fill=c,width=1)
    mask=Image.new('L',(n,n));d=ImageDraw.Draw(mask)
    if glyph=='spark':
        star(d,n*.43,n*.51,n*.21,255);star(d,n*.68,n*.34,n*.095,255);star(d,n*.65,n*.69,n*.075,255)
    elif glyph=='aperture':
        for i in range(6):
            ang=i*math.pi/3
            points=[]
            for radius,offset in [(.11,0),(.22,.18),(.22,.94),(.11,1.03)]:
                points.append((n*(.5+math.cos(ang+offset)*radius),n*(.5+math.sin(ang+offset)*radius)))
            d.polygon(points,fill=255)
    elif glyph=='orb':
        d.ellipse((n*.3,n*.3,n*.7,n*.7),outline=255,width=12)
        d.ellipse((n*.39,n*.39,n*.61,n*.61),fill=255)
        star(d,n*.73,n*.3,n*.055,255)
    else:
        d.ellipse((n*.29,n*.4,n*.71,n*.6),outline=255,width=14)
        part=Image.new('L',(n,n));ImageDraw.Draw(part).ellipse((n*.29,n*.4,n*.71,n*.6),outline=255,width=14)
        mask=Image.fromarray(np.maximum(np.array(mask),np.array(part.rotate(60,resample=Image.Resampling.BICUBIC))))
        mask=Image.fromarray(np.maximum(np.array(mask),np.array(part.rotate(-60,resample=Image.Resampling.BICUBIC))))
    shadow=Image.new('RGBA',(n,n),(15,25,70,95));shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(9)).point(lambda x:int(x*.25)))
    im=Image.alpha_composite(im,shadow)
    fg=Image.new('RGBA',(n,n),(255,255,255,255));fg.putalpha(mask)
    im=Image.alpha_composite(im,fg)
    return im.resize((256,256),Image.Resampling.LANCZOS)
def main():
    res=ROOT/'android/app/src/main/res';drawable=res/'drawable';drawable.mkdir(exist_ok=True)
    mipmap=res/'mipmap-anydpi-v26';mipmap.mkdir(exist_ok=True)
    ids=[]
    for glyph in GLYPHS:
      for color in COLORS:
       for material in MATERIALS:
        key=f'{glyph}_{color}_{material}';ids.append(key)
        render(glyph,color,material).convert('RGB').save(drawable/f'icon_{key}.webp',quality=94,method=6)
        obsolete=drawable/f'icon_{key}.png'
        if obsolete.exists():obsolete.unlink()
        (mipmap/f'launcher_{key}.xml').write_text(f'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@android:color/white"/><foreground android:drawable="@drawable/icon_{key}"/></adaptive-icon>')
    manifest=ROOT/'android/app/src/main/AndroidManifest.xml';text=manifest.read_text(encoding='utf8')
    text=re.sub(r'\s*<intent-filter>\s*<action android:name="android.intent.action.MAIN"\s*/>\s*<category android:name="android.intent.category.LAUNCHER"\s*/>\s*</intent-filter>','',text)
    text=re.sub(r'\s*<!-- BEGIN LAUNCHER ALIASES -->.*?<!-- END LAUNCHER ALIASES -->','',text,flags=re.S)
    aliases=[]
    for key in ['default']+ids:
        name='LauncherDefault' if key=='default' else 'Launcher_'+key
        icon='@mipmap/ic_launcher' if key=='default' else '@mipmap/launcher_'+key
        aliases.append(f'        <activity-alias android:name=".{name}" android:enabled="{"true" if key=="default" else "false"}" android:exported="true" android:targetActivity=".MainActivity" android:icon="{icon}" android:label="琉光"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity-alias>')
    text=text.replace('    </application>','    <!-- BEGIN LAUNCHER ALIASES -->\n'+'\n'.join(aliases)+'\n    <!-- END LAUNCHER ALIASES -->\n    </application>')
    manifest.write_text(text,encoding='utf8')
    path=ROOT/'android/app/src/main/kotlin/com/liuguang/liuguang/LauncherIcons.kt'
    path.write_text('''package com.liuguang.liuguang

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import java.io.ByteArrayOutputStream

object LauncherIcons {
    private val ids = listOf("default", '''+', '.join('"'+i+'"' for i in ids)+''')
    private fun name(id: String) = if(id == "default") "LauncherDefault" else "Launcher_" + id
    fun current(context: Context): String = context.getSharedPreferences("liuguang_icon",0).getString("selected","default") ?: "default"
    fun apply(context: Context, id: String) {
        require(ids.contains(id)) { "Unknown launcher icon" }
        val manager = context.packageManager
        fun component(key: String) = ComponentName(context,context.packageName + "." + name(key))
        if(Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(ids.map { key -> PackageManager.ComponentEnabledSetting(
                component(key), if(key == id) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP) })
        } else {
            manager.setComponentEnabledSetting(component(id), PackageManager.COMPONENT_ENABLED_STATE_ENABLED,PackageManager.DONT_KILL_APP)
            ids.filter { it != id }.forEach { manager.setComponentEnabledSetting(component(it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED,PackageManager.DONT_KILL_APP) }
        }
        context.getSharedPreferences("liuguang_icon",0).edit().putString("selected",id).apply()
    }
    fun preview(context: Context,id: String): ByteArray {
        require(ids.contains(id))
        val resource = if(id=="default") context.applicationInfo.icon else context.resources.getIdentifier("launcher_"+id,"mipmap",context.packageName)
        val drawable=context.getDrawable(resource) ?: error("Icon unavailable")
        val bitmap=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888)
        drawable.setBounds(0,0,256,256); drawable.draw(Canvas(bitmap))
        val stream=ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.PNG,100,stream);bitmap.recycle()
        return stream.toByteArray()
    }
}
''',encoding='utf8')
    print('Generated',len(ids),'adaptive launcher icons')
if __name__=='__main__':main()
