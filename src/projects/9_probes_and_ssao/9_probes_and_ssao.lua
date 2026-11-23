-- 9_probes_and_ssao: 8's light probes + 3's SSAO, combined the way games usually do it.
--
-- Probes = low frequency, colored bounce light (red near red walls, blue sky from above), but blurry: no contact shadows.
-- SSAO   = high frequency, colorless "how buried is this pixel": dark creases, wall/floor corners, under the sphere.
-- Both are about *indirect* light, so AO multiplies only the ambient term:
--     lit = albedo * (direct + probeAmbient * ao)
-- (direct light gets its own occlusion from shadow maps, see 7; here it has none.)
--
-- Per frame (submitted together):
--   1) gpass  -> gbuf (rgba32f): view-space normal + linear depth (same as 3).
--   2) aopass -> aoTex (r16f): raw, noisy AO from the gbuffer (same as 3).
--   3) window pass: draw the scene normally. Each fragment finds its own screen pixel (gl_FragCoord / Resolution),
--      blurs the AO around it, and multiplies its probe ambient by that.
-- Bake (at load): as in 8, but the sky is a color, so up-facing probe faces see sky light.
-- Static geometry uses probes too here, so the divider wall leaks: its two sides blend red and blue (see 8).
--
-- Keys: O toggles SSAO, V shows the ambient term only (probes * AO, no direct light, no albedo).

local H = require('src.helper')
local P = {}

local NX, NY, NZ, SPACING = 8, 2, 4, 2
local ORIGIN = { -7, 0.75, -3 }
local SKY = { 0.35, 0.45, 0.6 }

local litFragment = string.format(--[[glsl]] [[
uniform vec3 lightPos;
uniform float aoOn;
uniform float ambientOnly;
uniform texture2D gbuf;
uniform texture2D aoTex;
uniform Probes { vec4 probes[%d]; }; // 6 per probe: +X -X +Y -Y +Z -Z

const ivec3 COUNT = ivec3(%d, %d, %d);
const vec3 ORIGIN = vec3(%f, %f, %f);
const float SPACING = %f;

vec3 cube(ivec3 c, vec3 n) {
  c = clamp(c, ivec3(0), COUNT - 1);
  int base = (c.x + c.y * COUNT.x + c.z * COUNT.x * COUNT.y) * 6;
  vec3 n2 = n * n;
  return n2.x * probes[base + (n.x > 0. ? 0 : 1)].rgb
       + n2.y * probes[base + (n.y > 0. ? 2 : 3)].rgb
       + n2.z * probes[base + (n.z > 0. ? 4 : 5)].rgb;
}

float cornerWeight(vec3 f, ivec3 o) {
  vec3 w = mix(1. - f, f, vec3(o));
  return w.x * w.y * w.z;
}

vec3 ambient(vec3 p, vec3 n) {
  vec3 g = clamp((p - ORIGIN) / SPACING, vec3(0), vec3(COUNT - 1));
  ivec3 c = ivec3(floor(g));
  vec3 f = g - floor(g);
  vec3 sum = vec3(0);
  for (int x = 0; x <= 1; x++)
  for (int y = 0; y <= 1; y++)
  for (int z = 0; z <= 1; z++) {
    ivec3 o = ivec3(x, y, z);
    sum += cornerWeight(f, o) * cube(c + o, n);
  }
  return sum;
}

// 4x4 depth/normal-aware blur of the raw AO around screen position uv (3's composite, as a function).
float blurredAO(vec2 uv) {
  vec4 g = getPixel(gbuf, uv);
  vec2 texel = 1. / Resolution;
  float sum = 0., wsum = 0.;
  for (int y = -2; y < 2; y++) {
    for (int x = -2; x < 2; x++) {
      vec2 suv = uv + vec2(x, y) * texel;
      vec4 s = getPixel(gbuf, suv);
      float wd = max(0., 1. - abs(s.a - g.a) / g.a * 30.);
      float wn = pow(max(dot(s.xyz, g.xyz), 0.), 8.);
      float w = wd * wn + 1e-4;
      sum += getPixel(aoTex, suv).r * w;
      wsum += w;
    }
  }
  return sum / wsum;
}

vec4 lovrmain() {
  vec3 N = normalize(Normal);
  vec3 toL = lightPos - PositionWorld;
  float d = length(toL);
  float direct = max(dot(N, toL / d), 0.) * 6. / (1. + d * d);
  float ao = aoOn > 0. ? blurredAO(gl_FragCoord.xy / Resolution) : 1.;
  vec3 amb = ambient(PositionWorld, N) * ao;
  if (ambientOnly > 0.) return vec4(amb, 1.);
  return vec4(Color.rgb * (direct + amb), 1.);
}
]], NX * NY * NZ * 6, NX, NY, NZ, ORIGIN[1], ORIGIN[2], ORIGIN[3], SPACING)

-- From 3: view-space normal (xyz) + linear view depth (a).
local gbufferFragment = --[[glsl]] [[
vec4 lovrmain() {
  vec3 n = normalize(mat3(View) * normalize(Normal));
  float depth = -(View * vec4(PositionWorld, 1.)).z;
  return vec4(n, depth);
}
]]

-- From 3, unchanged except the two radii (room scale).
local aoFragment = --[[glsl]] [[
uniform texture2D gbuf;

const int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

vec3 viewPos(vec2 uv, float depth) {
  vec4 p = InverseProjection * vec4(uv * 2. - 1., .5, 1.);
  p.xyz /= p.w;
  return p.xyz * (depth / -p.z);
}

float occlusion(vec3 P, mat3 TBN, float radius, float noise) {
  const int COUNT = 24;
  vec3 N = TBN[2];
  float occ = 0.;
  for (int i = 0; i < COUNT; i++) {
    float fi = float(i) + .5;
    float r = sqrt(fi / float(COUNT));
    float phi = fi * 2.39996323;
    vec3 h = vec3(r * cos(phi), r * sin(phi), sqrt(1. - r * r));
    float t = fract(fi * .7548776662 + noise);
    vec3 S = P + TBN * h * radius * mix(.1, 1., t * t);

    vec4 clip = Projection * vec4(S, 1.);
    vec2 uv = clip.xy / clip.w * .5 + .5;
    if (any(lessThan(uv, vec2(0.))) || any(greaterThan(uv, vec2(1.)))) continue;
    uv = (floor(uv * Resolution) + .5) / Resolution;

    float depth = getPixel(gbuf, uv).a;
    if (depth <= 0.) continue;
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

  float ao = occlusion(P, TBN, .4, noise) * occlusion(P, TBN, 1.5, fract(noise + .37));
  return vec4(ao, ao, ao, 1.);
}
]]

local FACES = {
  { -math.pi / 2, 0, 1, 0 }, { math.pi / 2, 0, 1, 0 },
  { math.pi / 2, 1, 0, 0 }, { -math.pi / 2, 1, 0, 0 },
  { math.pi, 0, 1, 0 }, { 0, 0, 1, 0 },
}

local litShader, gbufferShader, aoShader, teapot
local probeBuf, gbuf, aoTex, gpass, aopass
local width, height
local light = { -2, 2, 0 }
local aoOn, ambientOnly = true, false

-- Geometry only: callers pick the shader. sphereX = nil leaves out the dynamic objects (bake = static only).
local function drawScene(p, sphereX, teapotAngle)
  local h = 2.5
  p:setColor(0.6, 0.6, 0.6)
  p:box(0, -0.1, 0, 16, 0.2, 8)
  p:setColor(0.9, 0.15, 0.1)
  p:box(-4, h / 2, -4, 8, h, 0.2)
  p:box(-4, h / 2, 4, 8, h, 0.2)
  p:box(-8, h / 2, 0, 0.2, h, 8)
  p:setColor(0.1, 0.25, 0.9)
  p:box(4, h / 2, -4, 8, h, 0.2)
  p:box(4, h / 2, 4, 8, h, 0.2)
  p:box(8, h / 2, 0, 0.2, h, 8)
  p:setColor(0.8, 0.8, 0.8)
  p:box(0, h / 2, -2.5, 0.2, h, 3)
  p:box(0, h / 2, 2.5, 0.2, h, 3)
  if sphereX then
    p:setColor(1, 1, 1)
    p:sphere(sphereX, 0.6, 0, 0.6) -- resting on the floor: contact shadow for SSAO
    p:draw(teapot, -5, 0, -2.2, 0.45, teapotAngle, 0, 1, 0) -- red corner: watch red/sky bounce sweep over it
  end
end

local function useLit(p, baking)
  p:setShader(litShader)
  p:setSampler('nearest')
  p:send('Probes', probeBuf)
  p:send('lightPos', light)
  p:send('gbuf', gbuf)
  p:send('aoTex', aoTex)
  p:send('aoOn', (aoOn and not baking) and 1 or 0)
  p:send('ambientOnly', (ambientOnly and not baking) and 1 or 0)
end

local function resize(w, h)
  width, height = w, h
  local opts = { mipmaps = false, usage = { 'render', 'sample' } }
  opts.format = 'rgba32f'
  gbuf = lovr.graphics.newTexture(w, h, opts)
  opts.format = 'r16f'
  aoTex = lovr.graphics.newTexture(w, h, opts)
  gpass = lovr.graphics.newPass({ gbuf, depth = 'd32f', samples = 1 })
  aopass = lovr.graphics.newPass({ aoTex, depth = false, samples = 1 })
end

local function bake()
  local tex = lovr.graphics.newTexture(16, 16, 6, {
    type = 'array', format = 'rgba16f', mipmaps = true, usage = { 'render', 'transfer' } })
  local bakePass = lovr.graphics.newPass({ tex, samples = 1 })
  local proj = lovr.math.mat4():perspective(math.pi / 2, 1, 0.05)
  probeBuf:clear() -- the lit shader reads probes while baking: start from zero ambient (one bounce)
  local data = {}
  for k = 0, NZ - 1 do
    for j = 0, NY - 1 do
      for i = 0, NX - 1 do
        local x, y, z = ORIGIN[1] + i * SPACING, ORIGIN[2] + j * SPACING, ORIGIN[3] + k * SPACING
        bakePass:reset()
        bakePass:setClear(SKY[1], SKY[2], SKY[3], 1)
        for f, r in ipairs(FACES) do
          bakePass:setViewPose(f, x, y, z, unpack(r))
          bakePass:setProjection(f, proj)
        end
        useLit(bakePass, true)
        drawScene(bakePass)
        lovr.graphics.submit(bakePass)
        for f = 1, 6 do
          local r, g, b = tex:getPixels(0, 0, f, 5):getPixel(0, 0)
          data[#data + 1] = { r, g, b, 1 }
        end
      end
    end
  end
  probeBuf:setData(data)
end

function P.load()
  lovr.graphics.setBackgroundColor(SKY)
  H.camera.set(-2, 7, 6, -0.2, -0.9)
  litShader = lovr.graphics.newShader('unlit', litFragment)
  gbufferShader = lovr.graphics.newShader('unlit', gbufferFragment)
  aoShader = lovr.graphics.newShader('fill', aoFragment)
  probeBuf = lovr.graphics.newBuffer('vec4', NX * NY * NZ * 6)
  local parseObj = require('src.projects.2_models_and_texs.obj')
  teapot = lovr.graphics.newMesh({
    { 'VertexPosition', 'vec3' },
    { 'VertexNormal', 'vec3' },
    { 'VertexUV', 'vec2' },
  }, parseObj(lovr.filesystem.read('src/projects/2_models_and_texs/teapot.obj')))
  resize(lovr.system.getWindowDimensions()) -- the lit shader needs gbuf/aoTex bound, even while baking
  bake()
end

function P.draw(pass)
  local w, h = pass:getDimensions()
  if w ~= width or h ~= height then resize(w, h) end
  local proj = pass:getProjection(1, lovr.math.mat4())
  local t = lovr.timer.getTime()
  local sphereX = math.sin(t * 0.4) * 6.5
  local teapotAngle = t * 0.5

  -- 1) G-buffer, same camera as the window.
  gpass:reset()
  gpass:setClear(0, 0, 0, 0)
  gpass:setProjection(1, proj)
  H.camera.apply(gpass)
  gpass:setBlendMode()
  gpass:setShader(gbufferShader)
  drawScene(gpass, sphereX, teapotAngle)

  -- 2) Raw SSAO.
  aopass:reset()
  aopass:setProjection(1, proj)
  aopass:setSampler('nearest')
  aopass:setShader(aoShader)
  aopass:send('gbuf', gbuf)
  aopass:fill()

  -- 3) Lit scene: probes * AO.
  useLit(pass, false)
  drawScene(pass, sphereX, teapotAngle)

  pass:setShader()
  pass:setColor(1, 1, 0.7)
  pass:sphere(light[1], light[2], light[3], 0.1)

  lovr.graphics.submit(gpass, aopass, pass)
  return true
end

function P.keypressed(key)
  if key == 'o' then aoOn = not aoOn end
  if key == 'v' then ambientOnly = not ambientOnly end
end

return P
