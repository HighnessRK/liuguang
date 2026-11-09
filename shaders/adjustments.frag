#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform vec2 uImageSize;
uniform float uValues[14];
uniform float uBalance[9];
uniform float uPreserve;
uniform sampler2D uImage;
out vec4 fragColor;
float lum(vec3 c) { return dot(c, vec3(.2126,.7152,.0722)); }
float vmax(vec3 c) { return max(c.r,max(c.g,c.b)); }
float vmin(vec3 c) { return min(c.r,min(c.g,c.b)); }
void main() {
  vec2 uv=FlutterFragCoord().xy/uSize;
  vec4 original=texture(uImage,uv);
  vec3 c=original.rgb;
  if(uValues[11]!=0.0) {
    vec2 d=1.0/uImageSize;
    vec3 n=(texture(uImage,uv+vec2(d.x,0)).rgb+texture(uImage,uv-vec2(d.x,0)).rgb+
      texture(uImage,uv+vec2(0,d.y)).rgb+texture(uImage,uv-vec2(0,d.y)).rgb)*.25;
    c+=(c-n)*uValues[11]*2.0;
  }
  c*=exp2(uValues[0]*2.0);
  float l=lum(c);
  float tone=uValues[2]*.35*smoothstep(.35,1.0,l)+uValues[3]*.35*(1.0-smoothstep(0.0,.65,l))+
    uValues[1]*.2*(1.0-abs(2.0*l-1.0));
  c=(c+tone-.5)*(1.0+uValues[4]*.8)+.5+uValues[5]*.25-uValues[6]*.2*(1.0-clamp(l,0.0,1.0));
  c*=vec3(1.0+uValues[9]*.16,1.0-uValues[10]*.12,1.0-uValues[9]*.16);
  l=lum(c);
  float chroma=vmax(c)-vmin(c);
  c=vec3(l)+(c-vec3(l))*(1.0+uValues[7]+uValues[8]*(1.0-clamp(chroma,0.0,1.0))*.75);
  float before=(vmax(c)+vmin(c))*.5;
  vec3 weights=vec3(1.0-smoothstep(0.0,.5,l),1.0-abs(2.0*clamp(l,0.0,1.0)-1.0),smoothstep(.5,1.0,l));
  c+=vec3(uBalance[0],uBalance[1],uBalance[2])*weights.x*.25;
  c+=vec3(uBalance[3],uBalance[4],uBalance[5])*weights.y*.25;
  c+=vec3(uBalance[6],uBalance[7],uBalance[8])*weights.z*.25;
  c=clamp(c,0.0,1.0);
  if(uPreserve>.5) {
    float hi=vmax(c),lo=vmin(c),oldL=(hi+lo)*.5,delta=hi-lo;
    float sat=delta<.000001?0.0:delta/max(.000001,1.0-abs(2.0*oldL-1.0));
    float nl=clamp(before,0.0,1.0),nc=(1.0-abs(2.0*nl-1.0))*sat;
    c=delta>.000001?(c-lo)/delta*nc+nl-nc*.5:vec3(nl);
  }
  float vignette=1.0-uValues[12]*.75*smoothstep(.15,.72,length(uv-.5));
  float grain=(fract(sin(uv.x*1234.5+uv.y*7654.3)*43758.5453)-.5)*uValues[13]*.12;
  fragColor=vec4(clamp(c*vignette+grain,0.0,1.0)*original.a,original.a);
}
