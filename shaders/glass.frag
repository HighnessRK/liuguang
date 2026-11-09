#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform float uRadius;
uniform float uStrength;
uniform float uDark;
uniform sampler2D uBackdrop;
out vec4 fragColor;
float sdf(vec2 p,vec2 halfSize,float r) {
  vec2 q=abs(p)-halfSize+vec2(r);
  return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r;
}
void main() {
  vec2 coord=FlutterFragCoord().xy;
  vec2 uv=coord/uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y=1.0-uv.y;
#endif
  vec2 halfSize=uSize*.5;
  float radius=min(uRadius,min(halfSize.x,halfSize.y));
  vec2 p=coord-halfSize;
  float distanceInside=-sdf(p,halfSize,radius);
  float rim=1.0-smoothstep(0.0,max(2.0,min(radius*.5,24.0)),distanceInside);
  vec2 normal=normalize(vec2(sdf(p+vec2(1,0),halfSize,radius)-sdf(p-vec2(1,0),halfSize,radius),
    sdf(p+vec2(0,1),halfSize,radius)-sdf(p-vec2(0,1),halfSize,radius))+vec2(.00001));
  vec2 shift=normal*rim*rim*uStrength/uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  shift.y=-shift.y;
#endif
  vec2 sampleUv=clamp(uv+shift,vec2(.001),vec2(.999));
  vec4 base=texture(uBackdrop,sampleUv);
  float red=texture(uBackdrop,clamp(sampleUv+shift*.035,vec2(.001),vec2(.999))).r;
  float blue=texture(uBackdrop,clamp(sampleUv-shift*.035,vec2(.001),vec2(.999))).b;
  float sheen=pow(rim,3.0)*max(0.0,dot(normal,normalize(vec2(-.6,-.8))))*.055;
  fragColor=vec4(clamp(vec3(red,base.g,blue)+sheen,0.0,1.0),base.a);
}
