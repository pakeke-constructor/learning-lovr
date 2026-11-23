// Post: one fullscreen pass, HDR in -> display out.
//   1) lens flare is added in HDR (so it gets tonemapped with everything else)
//   2) filmic tonemap (ACES fit) -> gamma space
//   3) grading in gamma space: lift/gamma/gain, split tone, saturation, contrast
//   4) ink edges from the G-buffer (depth + normal discontinuities), drawn on top like a comic
//   5) vignette + film grain, then back to linear for the sRGB target.

uniform texture2D hdr, gAlbedo, gNormal, gPos;
uniform vec3 sunDir;
uniform float edgesOn, flareOn, gradeOn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float lum(vec3 c) { return dot(c, vec3(.2126, .7152, .0722)); }

// Inverse linear depth: affine in screen space for planes, so its 2nd derivative is ~0 on flat
// surfaces (even at grazing angles) and spikes at silhouettes. Sky (w = 0) -> 0 = infinitely far.
float invDepth(vec2 uv) { float d = getPixel(gPos, uv).w; return d > 0. ? 1. / d : 0.; }

// ---- Borderlands ink -----------------------------------------------------------------------
// Stylized, not a full edge detector: silhouettes only (plus hard creases on rocks/monoliths),
// thin, with a hand-drawn wobble in the line width, and the ink is a dark shade of the surface, not black.
float inkEdge(vec2 uv, float d, vec3 n, float mat) {
  if (mat == 2.) return 0.; // grass: no ink, its shell silhouettes are pure noise

  // Line width wobbles along the screen like a brush stroke; thinner with distance.
  float wobble = .6 + .8 * hash(floor(uv * Resolution / 6.));
  float r = mix(2.2, 1., smoothstep(4., 150., d)) * wobble;
  vec2 px = r / Resolution;
  float c = 1. / d;

  // One-sided Laplacian of inverse depth: >0 only when this pixel is NEARER than its neighbours,
  // so silhouette lines land on the object, not on whatever is behind it.
  float lapX = 2. * c - invDepth(uv + vec2(px.x, 0)) - invDepth(uv - vec2(px.x, 0));
  float lapY = 2. * c - invDepth(uv + vec2(0, px.y)) - invDepth(uv - vec2(0, px.y));
  float depthEdge = smoothstep(.3, .7, max(lapX, lapY) * d);

  // Creases only on hard-edged things (rocks 3, monoliths 4).
  float creaseEdge = 0.;
  if (mat == 3. || mat == 4.) {
    float crease = 0.;
    for (int i = 0; i < 4; i++) {
      vec2 o = vec2[](vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1))[i] * px;
      crease = max(crease, 1. - dot(n, getPixel(gNormal, uv + o).xyz));
    }
    creaseEdge = smoothstep(.5, .8, crease) * .7;
  }

  float fade = mat == 5. ? .35 : 1. - smoothstep(60., 300., d); // distant lines melt into the haze
  return max(depthEdge, creaseEdge) * fade * .6;
}

// ---- Lens flare (analytic, in aspect-corrected screen coords centred at 0) -------------------
float hexDist(vec2 q) { q = abs(q); return max(q.x * .866 + q.y * .5, q.y); }

vec3 lensFlare(vec2 uv) {
  // A direction (w = 0) projects to the vanishing point of the sun: ignores camera translation.
  vec4 clip = Projection * View * vec4(sunDir, 0);
  if (clip.w <= 0.) return vec3(0); // sun behind the camera
  vec2 s = clip.xy / clip.w * .5 + .5;

  // Occlusion: how much of a small disc around the sun is sky in the G-buffer (clouds/terrain block it).
  vec2 aspect = vec2(Resolution.x / Resolution.y, 1);
  float vis = 0.;
  for (int i = 0; i < 16; i++) {
    float a = float(i) * 2.39996, rr = .025 * sqrt((float(i) + .5) / 16.); // golden-angle spiral
    vec2 q = s + vec2(cos(a), sin(a)) * rr / aspect;
    bool onScreen = all(greaterThan(q, vec2(0))) && all(lessThan(q, vec2(1)));
    vis += (!onScreen || getPixel(gPos, q).w == 0.) ? 1. : 0.;
  }
  vis /= 16.;
  vec2 edge = min(s, 1. - s);
  vis *= smoothstep(-.15, .05, min(edge.x, edge.y)); // fade out as the sun leaves the screen
  if (vis <= 0.) return vec3(0);

  vec2 p = (uv - .5) * aspect, sp = (s - .5) * aspect;
  vec2 dv = p - sp;
  float d = length(dv);
  vec3 sun = vec3(1., .85, .65);

  // Glare core + wide bloom-ish glow.
  vec3 col = sun * (exp(-d * 30.) * 2. + exp(-d * 8.) * .15);

  // Starburst: spiky rays from the aperture blades, slowly turning with the sun's screen position.
  float ang = atan(dv.y, dv.x) + sp.x * .5;
  float rays = pow(abs(sin(ang * 6.) * sin(ang * 11. + 1.3)), 4.) + .3 * pow(abs(sin(ang * 23.)), 20.);
  col += sun * rays * exp(-d * 9.) * .5;

  // Anamorphic streak: thin, wide, bluish.
  col += vec3(.4, .6, 1.) * exp(-abs(dv.y) * 250.) * exp(-abs(dv.x) * 1.8) * .7;

  // Chromatic halo ring around the sun (each channel at a slightly different radius).
  vec3 radii = vec3(.36, .34, .32);
  col += exp(-pow((d - radii) * 30., vec3(2))) * .07;

  // Ghosts: hexagonal aperture reflections on the line sun -> screen centre -> beyond.
  for (int i = 0; i < 6; i++) {
    float k = vec4(-.35, .25, .55, .8)[i % 4] + float(i / 4) * 1.1;
    float size = vec4(.06, .03, .1, .045)[i % 4] * (1. + float(i / 4));
    vec3 tint = vec3[](vec3(.3, .6, 1.), vec3(1., .5, .2), vec3(.4, 1., .5), vec3(1., .3, .6))[i % 4];
    float h = hexDist(p + sp * k);
    float g = smoothstep(size, size * .75, h) * (.4 + .6 * smoothstep(size * .5, size, h)); // brighter rim
    col += tint * g * .05;
  }

  // Veiling glare: the whole lens washes out a little when looking into the sun.
  col += sun * .015 * (1. - smoothstep(0., .8, length(sp)));
  return col * vis;
}

// ---- Grading ----------------------------------------------------------------------------------
vec3 aces(vec3 x) { return clamp((x * (2.51 * x + .03)) / (x * (2.43 * x + .59) + .14), 0., 1.); }

vec3 grade(vec3 c) {
  vec3 lift = vec3(.005, 0., .02), gain = vec3(1.03, 1., .97), gamma = vec3(.95, 1., 1.05);
  c = pow(max(gain * (c + lift * (1. - c)), 0.), 1. / gamma);
  float l = lum(c);
  c += mix(vec3(-.02, .02, .05), vec3(.03, .015, -.02), smoothstep(.15, .75, l)); // teal shadows, warm highlights
  c = mix(vec3(lum(c)), c, 1.3);                                                  // saturation
  c = mix(c, c * c * (3. - 2. * c), .6);                                           // S-curve contrast
  return clamp(c, 0., 1.);
}

vec4 lovrmain() {
  vec3 color = getPixel(hdr, UV).rgb;
  if (flareOn > .5) color += lensFlare(UV);

  vec3 c = aces(color * .85); // exposure
  if (gradeOn < .5) return vec4(c, 1); // tonemap only, for comparison
  c = grade(linearToGamma(c));

  vec4 pos = getPixel(gPos, UV);
  if (edgesOn > .5 && pos.w > 0.) {
    float mat = floor(getPixel(gAlbedo, UV).a * 255. + .5);
    c = mix(c, c * vec3(.25, .22, .3), inkEdge(UV, pos.w, normalize(getPixel(gNormal, UV).xyz), mat));
  }

  vec2 v = (UV - .5) * vec2(Resolution.x / Resolution.y, 1);
  c *= mix(1., smoothstep(1.1, .3, length(v)), .45);                         // vignette
  c += (hash(UV * Resolution + fract(Time) * 917.) - .5) * .05 * (1. - .6 * lum(c)); // grain, mostly in darks
  return vec4(gammaToLinear(clamp(c, 0., 1.)), 1);
}
