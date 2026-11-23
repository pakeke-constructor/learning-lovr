// SSAO + 1-bounce screen-space GI, one fullscreen pass. Output: rgb = bounce light, a = ambient visibility.
//
// Both walk world-space points in the hemisphere around the normal and project them to the screen:
//   AO: if the G-buffer surface at that pixel is IN FRONT of the sample point, the sample is buried -> occluded.
//   GI: the G-buffer surface at that pixel is a tiny "area light": its albedo * sun light (shadowed) is
//       bounced towards us, weighted by both cosines and distance. Only what's on screen can bounce (screen-space).
// Per-pixel random rotation (noise) trades banding for grain; light_main.glsl blurs it away.
uniform float giRadius;

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(.06711056, .00583715)))); }

vec2 project(vec3 p, out float depth) {
  vec4 c = ViewProjection * vec4(p, 1.);
  depth = c.w; // perspective: clip w = linear view depth, same unit as posTex.w
  return c.xy / c.w * .5 + .5;
}

bool onScreen(vec2 uv) { return all(greaterThan(uv, vec2(0))) && all(lessThan(uv, vec2(1))); }

vec4 lovrmain() {
  vec4 P = getPixel(posTex, UV);
  if (P.w == 0.) return vec4(0, 0, 0, 1); // sky
  vec3 p = P.xyz;
  vec3 n = normalize(getPixel(normalTex, UV).xyz);
  vec3 t = normalize(cross(n, abs(n.y) < .99 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
  vec3 b = cross(n, t);

  float rnd = ign(FragCoord.xy);
  float R = clamp(P.w * .03, .4, 5.); // AO radius grows with distance so far hills still get some
  float occ = 0.;
  vec3 gi = vec3(0);
  const int N = 12;

  for (int i = 0; i < N; i++) {
    float f = (float(i) + rnd) / float(N);
    float phi = float(i) * 2.39996 + rnd * TAU; // golden-angle spiral, rotated per pixel
    float r = sqrt(f);
    vec3 dir = t * (cos(phi) * r) + b * (sin(phi) * r) + n * sqrt(1. - f + .05); // cosine-ish hemisphere
    dir = normalize(dir);

    // AO: short sample, closer ones denser (f^2)
    float d;
    vec2 uv = project(p + dir * R * mix(.1, 1., f * f), d);
    if (onScreen(uv)) {
      float sd = getPixel(posTex, uv).w;
      float rangeCheck = smoothstep(0., 1., R / max(abs(P.w - sd), 1e-4)); // ignore far-away occluders
      if (sd > 0. && sd < d - .03 * R) occ += rangeCheck;
    }

    // GI: longer reach, every other sample
    if ((i & 1) == 0) {
      uv = project(p + dir * giRadius * (.2 + f), d);
      if (!onScreen(uv)) continue;
      vec4 sp = getPixel(posTex, uv);
      if (sp.w == 0.) continue;
      vec3 sn = normalize(getPixel(normalTex, uv).xyz);
      vec3 toS = sp.xyz - p;
      float dl = length(toS);
      if (dl < .05) continue;
      toS /= dl;
      float geo = max(dot(n, toS), 0.) * max(dot(sn, -toS), 0.) / (1. + dl * dl / (giRadius * giRadius));
      vec3 radiance = getPixel(albedoTex, uv).rgb * sunColor * max(dot(sn, sunDir), 0.) * shadowAt(sp.xyz, sn, 1);
      gi += radiance * geo;
    }
  }

  return vec4(gi * (4. / float(N)), 1. - occ / float(N));
}
