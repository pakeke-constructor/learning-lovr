-- proj_3: field of white cubes + SSAO (screen-space ambient occlusion).
--
-- Pipeline (3 passes per frame, submitted together):
--   1) gpass  -> gbuf (rgba32f): view-space normal (xyz) + linear view depth (a). Sky = depth 0.
--   2) aopass -> aoTex (r16f): fullscreen; for each pixel, sample points in a hemisphere around
--      the normal, project them back to screen and check if the gbuffer surface is in front of them.
--      Two radii (small = contact shadows, large = broad occlusion), multiplied.
--   3) window pass: fullscreen composite; 4x4 depth/normal-aware blur of AO (cancels the 4x4
--      rotation noise used in step 2), a little flat lighting, fog to white.
--
-- Offscreen passes are retained objects: reset() each frame, then record, then submit.
-- Returning true from lovr.draw tells LOVR we submitted the window pass ourselves.

local H = require('src.helper')
local P = {}

local gbufferFragment = [[
vec4 lovrmain() {
  vec3 n = normalize(mat3(View) * normalize(Normal));
  float depth = -(View * vec4(PositionWorld, 1.)).z;
  return vec4(n, depth);
}
]]

local aoFragment = [[
uniform texture2D gbuf;

// 4x4 Bayer index -> per-pixel rotation; the composite's 4x4 blur averages it back out.
const int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

// Rebuild view-space position from screen UV + linear depth.
// Any point on the pixel's ray works; rescale it so -z == depth.
vec3 viewPos(vec2 uv, float depth) {
  vec4 p = InverseProjection * vec4(uv * 2. - 1., .5, 1.);
  p.xyz /= p.w;
  return p.xyz * (depth / -p.z);
}

// Alchemy/SAO-style estimator: pick sample pixels via a hemisphere around the normal, then use the
// *actual surface point* at each pixel. Occlusion = how much that point sits above our tangent plane
// (cosine), faded by distance. Continuous in depth, so no banding from hard depth compares.
float occlusion(vec3 P, mat3 TBN, float radius, float noise) {
  const int COUNT = 24;
  vec3 N = TBN[2];
  float occ = 0.;
  for (int i = 0; i < COUNT; i++) {
    float fi = float(i) + .5;
    // Fibonacci spiral on the disk, lifted to a hemisphere (z = normal).
    float r = sqrt(fi / float(COUNT));
    float phi = fi * 2.39996323;
    vec3 h = vec3(r * cos(phi), r * sin(phi), sqrt(1. - r * r));
    // Sample distance: decorrelated from direction, biased toward the center.
    float t = fract(fi * .7548776662 + noise);
    vec3 S = P + TBN * h * radius * mix(.1, 1., t * t);

    vec4 clip = Projection * vec4(S, 1.);
    vec2 uv = clip.xy / clip.w * .5 + .5;
    if (any(lessThan(uv, vec2(0.))) || any(greaterThan(uv, vec2(1.)))) continue;
    uv = (floor(uv * Resolution) + .5) / Resolution; // snap to texel center so Q is exact

    float depth = getPixel(gbuf, uv).a;
    if (depth <= 0.) continue; // sky never occludes
    vec3 v = viewPos(uv, depth) - P;
    float len = length(v);
    float falloff = max(1. - len * len / (radius * radius), 0.);
    occ += falloff * max(dot(v, N) - .002 * -P.z, 0.) / (len + 1e-3);
  }
  return max(1. - 2. * occ / float(COUNT), 0.);
}

vec4 lovrmain() {
  vec4 g = getPixel(gbuf, UV);
  if (g.a <= 0.) return vec4(1.);

  vec3 N = normalize(g.xyz);
  vec3 P = viewPos(UV, g.a);

  ivec2 px = ivec2(gl_FragCoord.xy) & 3;
  float noise = (float(bayer[px.y * 4 + px.x]) + .5) / 16.;
  float angle = noise * 6.2831853;
  vec3 rv = vec3(cos(angle), sin(angle), 0.);
  vec3 T = normalize(rv - N * dot(rv, N));
  mat3 TBN = mat3(T, cross(N, T), N);

  float ao = occlusion(P, TBN, .6, noise) * occlusion(P, TBN, 3., fract(noise + .37));
  return vec4(ao, ao, ao, 1.);
}
]]

local compositeFragment = [[
uniform texture2D gbuf;
uniform texture2D aoTex;
uniform float aoOn;

// AO strength: exponent on the blurred AO. 1 = raw, higher = darker.
const float AO_STRENGTH = 1.8;

vec4 lovrmain() {
  vec4 g = getPixel(gbuf, UV);
  if (g.a <= 0.) return vec4(1.);

  float ao = 1.;
  if (aoOn > 0.) {
    // 4x4 bilateral blur: skip neighbors on a different surface (depth or normal mismatch).
    vec2 texel = 1. / Resolution;
    float sum = 0., wsum = 0.;
    for (int y = -2; y < 2; y++) {
      for (int x = -2; x < 2; x++) {
        vec2 uv = UV + vec2(x, y) * texel;
        vec4 s = getPixel(gbuf, uv);
        float wd = max(0., 1. - abs(s.a - g.a) / g.a * 30.);
        float wn = pow(max(dot(s.xyz, g.xyz), 0.), 8.);
        float w = wd * wn + 1e-4;
        sum += getPixel(aoTex, uv).r * w;
        wsum += w;
      }
    }
    ao = pow(sum / wsum, AO_STRENGTH);
  }

  // Barely-there lighting: mostly ambient, slight sky + sun so faces read differently.
  vec3 n = transpose(mat3(View)) * g.xyz;
  float sun = max(dot(n, normalize(vec3(.4, .8, .3))), 0.);
  float light = .66 + .16 * (.5 + .5 * n.y) + .18 * sun;

  vec3 color = vec3(light * ao);
  float fog = 1. - exp(-g.a * .008);
  return vec4(mix(color, vec3(1.), fog), 1.);
}
]]

local gbufferShader, aoShader, compositeShader
local gbuf, aoTex, gpass, aopass
local width, height
local aoOn = true

local function resize(w, h)
  width, height = w, h
  local opts = { mipmaps = false, usage = { 'render', 'sample' } }
  opts.format = 'rgba32f'
  gbuf = lovr.graphics.newTexture(w, h, opts)
  opts.format = 'r16f'
  aoTex = lovr.graphics.newTexture(w, h, opts)
  -- samples = 1: we sample these textures, and MSAA-resolving depth/normals would blend surfaces.
  gpass = lovr.graphics.newPass({ gbuf, depth = 'd32f', samples = 1 })
  aopass = lovr.graphics.newPass({ aoTex, depth = false, samples = 1 })
end

function P.load()
  H.camera.set(0, 3, 12, 0, -0.2)
  gbufferShader = lovr.graphics.newShader('unlit', gbufferFragment)
  aoShader = lovr.graphics.newShader('fill', aoFragment)
  compositeShader = lovr.graphics.newShader('fill', compositeFragment)
end

function P.draw(pass)
  local w, h = pass:getDimensions()
  if w ~= width or h ~= height then resize(w, h) end

  -- Offscreen passes use the window's camera + projection so all three agree on screen mapping.
  local proj = pass:getProjection(1, lovr.math.mat4())

  -- 1) G-buffer
  gpass:reset()
  gpass:setClear(0, 0, 0, 0)
  gpass:setProjection(1, proj)
  H.camera.apply(gpass)
  gpass:setBlendMode() -- alpha holds depth, not opacity: no blending
  gpass:setShader(gbufferShader)
  gpass:plane(0, 0, 0, 1000, 1000, -math.pi / 2, 1, 0, 0)
  for x = -30, 30 do
    for z = -30, 30 do
      gpass:cube(x * 2.5, 0.5, z * 2.5, 1)
    end
  end

  -- 2) SSAO (skipped entirely when off, so you can compare the GPU cost too)
  if aoOn then
    aopass:reset()
    aopass:setProjection(1, proj)
    aopass:setSampler('nearest')
    aopass:setShader(aoShader)
    aopass:send('gbuf', gbuf)
    aopass:fill()
  end

  -- 3) Composite to window
  pass:setSampler('nearest')
  pass:setShader(compositeShader)
  pass:send('gbuf', gbuf)
  pass:send('aoTex', aoTex)
  pass:send('aoOn', aoOn and 1 or 0)
  pass:fill()

  if aoOn then
    lovr.graphics.submit(gpass, aopass, pass)
  else
    lovr.graphics.submit(gpass, pass)
  end
  return true
end

-- O toggles SSAO.
function P.keypressed(key)
  if key == 'o' then aoOn = not aoOn end
end

return P
