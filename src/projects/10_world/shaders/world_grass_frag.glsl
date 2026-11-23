// Shell grass, fragment stage. The ground is split into tiny cells (one blade each).
// A cell's pixel survives on shell h if the blade is taller than h and the pixel is inside the blade's
// square cross-section (rect grid). Everything else is discarded.

uniform float density;  // blades per meter
uniform float fadeDist; // meters: blades shrink to nothing at this distance

layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outPos;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3. - 2. * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + 1.), f.x), f.y);
}

vec4 lovrmain() {
  float h = UV.x;
  vec3 n = normalize(Normal);
  vec3 p = PositionWorld;

  // How tall can grass get here: none on steep slopes, patchy clumps, shrinks with distance.
  float dist = length(CameraPositionWorld - p);
  float patches = smoothstep(.25, .6, vnoise(p.xz * .12)) * .6 + .4;
  float slope = smoothstep(.8, .9, n.y);
  float fade = 1. - smoothstep(fadeDist * .3, fadeDist, dist);

  vec2 cp = p.xz * density;
  vec2 cell = floor(cp);
  float r = hash(cell);
  float bladeH = mix(.85, 1., r) * patches * slope * fade;
  if (h > bladeH) discard;

  vec2 local = abs(fract(cp) - .5); // square blade centred in its grid cell
  if (max(local.x, local.y) > .3) discard;

  // Dark roots -> bright tips, per-blade tint, gusts lighten the tips a bit (like real grass showing its sheen).
  vec3 albedo = Color.rgb * mix(.6, 1.15, h) * mix(.85, 1.1, hash(cell + 11.));
  albedo = mix(albedo, albedo * vec3(1.25, 1.2, .8), h * h * UV.y * .6);

  outNormal = vec4(n, h);
  outPos = vec4(p, -(View * vec4(p, 1)).z);
  return vec4(albedo, 2. / 255.);
}
