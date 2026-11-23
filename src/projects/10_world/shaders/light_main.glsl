// Deferred lighting: G-buffer + AO/GI + shadow map -> linear HDR (tonemapping happens in post).
//   surfaces: albedo * (sun * shadow, stippled by grain) + albedo * (sky/ground hemisphere * AO + GI bounce)
//   clouds:   3-band toon ramp, no AO/shadow
//   sky:      gradient + sun halo + bright sun disk (> 1 so post's flare/bloom can key off it)
//   all:      height fog, tinted towards the sun
uniform texture2D aoTex;
uniform float aoOn, giOn, grainOn;

const vec3 SKY_ZENITH = vec3(.10, .26, .70);
const vec3 SKY_HORIZON = vec3(.62, .72, .84);
const vec3 AMB_SKY = vec3(.34, .42, .56);
const vec3 AMB_GROUND = vec3(.20, .18, .12);

float hash3(vec3 p) {
  p = fract(p * .1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  f = f * f * (3. - 2. * f);
  return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + 1.), f.x), f.y), f.z);
}

vec3 skyColor(vec3 d) {
  vec3 c = mix(SKY_HORIZON, SKY_ZENITH, pow(clamp(d.y, 0., 1.), .45));
  c = mix(c, SKY_HORIZON * .8, smoothstep(0., -.15, d.y)); // below horizon: hazy, never black
  float s = max(dot(d, sunDir), 0.);
  return c + sunColor * (pow(s, 8.) * .06 + pow(s, 120.) * .4); // wide warm glow + tight halo
}

// Analytic height fog: density falls off exponentially with altitude, integrated along the view ray.
float fogAmount(vec3 cam, vec3 p) {
  const float density = .0007, falloff = .01;
  vec3 r = p - cam;
  float dist = length(r);
  float k = falloff * r.y;
  float integral = abs(k) > 1e-4 ? (1. - exp(-k)) / k : 1.;
  return 1. - exp(-density * exp(-falloff * cam.y) * dist * integral);
}

// Depth-aware 4x4 box blur of the noisy AO/GI pass.
vec4 blurredAO(float depth) {
  vec2 texel = 1. / Resolution;
  vec4 sum = vec4(0);
  float wsum = 0.;
  for (int x = -2; x < 2; x++) for (int y = -2; y < 2; y++) {
    vec2 uv = UV + (vec2(x, y) + .5) * texel;
    float w = exp(-abs(getPixel(posTex, uv).w - depth) / (depth * .02 + .01));
    sum += getPixel(aoTex, uv) * w;
    wsum += w;
  }
  return sum / max(wsum, 1e-4);
}

vec4 lovrmain() {
  vec4 P = getPixel(posTex, UV);
  vec3 cam = CameraPositionWorld;

  if (P.w == 0.) { // sky: rebuild the view ray from the pixel
    vec4 vp = InverseProjection * vec4(UV * 2. - 1., .5, 1.);
    vec3 d = normalize(transpose(mat3(View)) * (vp.xyz / vp.w));
    float disk = smoothstep(.99955, .99975, dot(d, sunDir));
    return vec4(skyColor(d) + sunColor * disk * 25., 1.);
  }

  vec4 A = getPixel(albedoTex, UV);
  vec4 N4 = getPixel(normalTex, UV);
  int mat = int(A.a * 255. + .5);
  vec3 n = normalize(N4.xyz);
  vec3 p = P.xyz;
  vec3 v = normalize(p - cam);
  vec3 albedo = A.rgb;
  float ndl = dot(n, sunDir);
  vec3 color;

  if (mat == 5) { // clouds: hard toon bands, cool shadow side, warm rim when backlit
    float band = ndl > .35 ? 1. : ndl > -.15 ? .72 : .5;
    vec3 shade = mix(vec3(.42, .5, .72), vec3(1.05, .97, .9), band);
    float rim = pow(1. - max(dot(n, -v), 0.), 3.) * pow(max(dot(v, sunDir), 0.), 4.);
    color = albedo * shade * 1.6 + sunColor * rim * .8;
  } else {
    float sh = shadowAt(p, n, 4);
    float lit = max(ndl, 0.) * sh;

    // Grain: world-space value noise (2 octaves) so it sticks to surfaces. The sun term is thresholded
    // against it -> stippled terminator and shadow edges, like ink dots. Fades out with distance (aliasing).
    float grain = .6 * vnoise(p * 7.) + .4 * vnoise(p * 23.);
    float fade = (1. - smoothstep(25., 140., P.w)) * grainOn;
    float stipple = smoothstep(grain - .1, grain + .1, lit * 1.15);
    lit = mix(lit, stipple, .55 * fade);
    albedo *= mix(1., .82 + .36 * grain, fade); // speckled surface texture

    vec4 ao = blurredAO(P.w);
    float vis = mix(1., ao.a, aoOn);
    vis *= vis; // stronger contrast
    float hemi = n.y * .5 + .5;
    vec3 ambient = mix(AMB_GROUND, AMB_SKY, hemi) * vis + ao.rgb * giOn;

    if (mat == 2) { // grass shells: roots darker (self-shadowing of the blades)
      float h = N4.w;
      ambient *= mix(.35, 1., h);
      lit *= mix(.5, 1., h);
    }
    color = albedo * (sunColor * lit + ambient);
    if (mat == 4) color += albedo * .12; // monoliths: slight self-glow, shadow side stays a cool light grey
  }

  vec3 fogColor = mix(SKY_HORIZON, sunColor * .5, pow(max(dot(v, sunDir), 0.), 8.) * .6);
  color = mix(color, fogColor, fogAmount(cam, p) * (mat == 4 ? .35 : 1.)); // monoliths cut through the haze
  return vec4(color, 1.);
}
