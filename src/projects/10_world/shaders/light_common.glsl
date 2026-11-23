// Shared by light_ao.glsl and light_main.glsl (concatenated in front of them by lighting.lua).
uniform texture2D albedoTex, normalTex, posTex;  // G-buffer, read with the pass sampler ('nearest')
uniform texture2D shadowMap;
uniform sampler shadowSampler;                   // compare sampler: texture() returns lit fraction 0..1
uniform mat4 lightViewProj;
uniform vec3 sunDir;                             // towards the sun
uniform vec3 sunColor;

// Sun visibility at world point p. Normal offset pushes the lookup off the surface (kills acne on slopes).
// Outside the shadow box = lit.
float shadowAt(vec3 p, vec3 n, int taps) {
  vec4 c = lightViewProj * vec4(p + n * .12, 1.);
  vec2 uv = c.xy * .5 + .5;
  if (any(lessThan(uv, vec2(0))) || any(greaterThan(uv, vec2(1))) || c.z > 1.) return 1.;
  if (taps == 1) return texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv, c.z));
  // 4 taps at +-1 texel, each one bilinear-filtered by the hardware compare -> soft-ish edge
  vec2 t = 1. / vec2(textureSize(sampler2DShadow(shadowMap, shadowSampler), 0));
  float s = 0.;
  s += texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv + t * vec2(-1, -1), c.z));
  s += texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv + t * vec2( 1, -1), c.z));
  s += texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv + t * vec2(-1,  1), c.z));
  s += texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv + t * vec2( 1,  1), c.z));
  return s * .25;
}
