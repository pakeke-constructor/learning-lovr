-- 8_light_probes: simplest possible light probes: a small grid of "ambient cubes", baked once.
--
-- Probe = a point in space that remembers "how much light arrives from each direction" here.
-- Simplest storage: an ambient cube (Half-Life 2 style) = 6 colors, one per axis direction (+X -X +Y -Y +Z -Z).
--
-- Bake (at load, and again on R):
--   for each probe: render the static scene into a tiny 16x16 'array' texture with 6 layers.
--     Multiview: a canvas with 6 layers = 6 views, each draw is broadcast to all of them.
--     View i = camera at the probe looking along axis i, perspective(90deg, aspect 1) -> 6 faces cover the sphere.
--     (Not a 'cube' texture: we only need each face's average, so face orientation conventions don't matter.)
--     Mipmaps are generated at the end of the pass -> the 1x1 mip of each layer = that face's average color.
--     Read those 6 pixels back (Texture:getPixels, a CPU stall, fine for a bake) -> one Buffer for all probes.
-- Shade: ambient = weighted sum of the 3 faces the normal points toward:
--     n2 = N * N;  ambient = n2.x * cube[N.x > 0 ? +X : -X] + n2.y * (+Y/-Y) + n2.z * (+Z/-Z)
--   The sphere sits between 8 probes (a grid cell) -> trilinear blend of their 8 ambients, so no pop between cells.
--   then lit = albedo * (direct + ambient).
--
-- Scene: two open-top rooms joined by a doorway, one point light (no shadows) in room A near the door.
-- Room A: red walls. Room B: blue walls, further from the light -> dimmer. A white sphere moves between them.
-- Static geometry gets a flat constant ambient (a real game would use lightmaps); the sphere is what probes are for.
--
-- Good at: the moving sphere picks up red in A, blue in B, with zero per-frame GI cost (paid at bake).
--
-- Keys:
--   Arrows  move the light. Direct light updates, the probes don't: stale until R (rebake). Probes = static lighting.
--   P  show probes: each sphere shows its raw ambient cube (incoming light, not times albedo).
--      Leaking: the probes at x = +-1 sit on both sides of the divider wall; anything between them blends
--      red and blue light right through the wall. Fixes: denser spacing, per-probe visibility/occlusion.
--   Low frequency only: no sharp shadows or detail, resolution = probe spacing (2m here).

local H = require('src.helper')
local P = {}

local NX, NY, NZ, SPACING = 8, 2, 4, 2
local ORIGIN = { -7, 0.75, -3 } -- probe (0,0,0); grid spans x -7..7, y 0.75..2.75, z -3..3

local fragment = string.format(--[[glsl]] [[
uniform vec3 lightPos;
uniform int mode; // 0 flat ambient (static geometry), 1 probes, 2 probe display
uniform Probes { vec4 probes[%d]; }; // 6 per probe: +X -X +Y -Y +Z -Z

const ivec3 COUNT = ivec3(%d, %d, %d);
const vec3 ORIGIN = vec3(%f, %f, %f);
const float SPACING = %f;

vec3 cube(ivec3 c, vec3 n) {
  c = clamp(c, ivec3(0), COUNT - 1);
  int base = (c.x + c.y * COUNT.x + c.z * COUNT.x * COUNT.y) * 6;
  vec3 n2 = n * n; // weights sum to 1
  return n2.x * probes[base + (n.x > 0. ? 0 : 1)].rgb
       + n2.y * probes[base + (n.y > 0. ? 2 : 3)].rgb
       + n2.z * probes[base + (n.z > 0. ? 4 : 5)].rgb;
}

// Trilinear weight of cell corner o (each axis 0 or 1) when we're f (0..1 per axis) through the cell.
// Per axis: o = 0 -> 1 - f, o = 1 -> f (closer corner = more weight). All 8 weights sum to 1.
float cornerWeight(vec3 f, ivec3 o) {
  vec3 w = mix(1. - f, f, vec3(o));
  return w.x * w.y * w.z;
}

vec3 ambient(vec3 p, vec3 n) {
  vec3 g = clamp((p - ORIGIN) / SPACING, vec3(0), vec3(COUNT - 1)); // position in grid units
  ivec3 c = ivec3(floor(g)); // cell's lower corner
  vec3 f = g - floor(g);     // how far through the cell
  vec3 sum = vec3(0);
  for (int x = 0; x <= 1; x++)
  for (int y = 0; y <= 1; y++)
  for (int z = 0; z <= 1; z++) {
    ivec3 o = ivec3(x, y, z);
    sum += cornerWeight(f, o) * cube(c + o, n);
  }
  return sum;
}

vec4 lovrmain() {
  vec3 N = normalize(Normal);
  if (mode == 2) return vec4(ambient(PositionWorld, N), 1.);
  vec3 toL = lightPos - PositionWorld;
  float d = length(toL);
  float direct = max(dot(N, toL / d), 0.) * 12. / (1. + d * d);
  vec3 amb = mode == 0 ? vec3(.03) : ambient(PositionWorld, N);
  return vec4(Color.rgb * (direct + amb), 1.);
}
]], NX * NY * NZ * 6, NX, NY, NZ, ORIGIN[1], ORIGIN[2], ORIGIN[3], SPACING)


-- One rotation per face: the camera looks down -Z, rotate it to look along +X -X +Y -Y +Z -Z.
local FACES = {
  { -math.pi / 2, 0, 1, 0 }, { math.pi / 2, 0, 1, 0 },
  { math.pi / 2, 1, 0, 0 }, { -math.pi / 2, 1, 0, 0 },
  { math.pi, 0, 1, 0 }, { 0, 0, 1, 0 },
}

local shader, probeBuf, bakeTex, bakePass
local light = { -2, 2, 0 }
local showProbes = false

local function drawScene(p)
  p:setShader(shader)
  p:send('Probes', probeBuf)
  p:send('lightPos', light)
  p:send('mode', 0)
  local h = 2.5
  p:setColor(0.6, 0.6, 0.6)
  p:box(0, -0.1, 0, 16, 0.2, 8) -- floor
  p:setColor(0.9, 0.15, 0.1) -- room A (x < 0)
  p:box(-4, h / 2, -4, 8, h, 0.2)
  p:box(-4, h / 2, 4, 8, h, 0.2)
  p:box(-8, h / 2, 0, 0.2, h, 8)
  p:setColor(0.1, 0.25, 0.9) -- room B (x > 0)
  p:box(4, h / 2, -4, 8, h, 0.2)
  p:box(4, h / 2, 4, 8, h, 0.2)
  p:box(8, h / 2, 0, 0.2, h, 8)
  p:setColor(0.8, 0.8, 0.8) -- divider with a 2m doorway at z = 0
  p:box(0, h / 2, -2.5, 0.2, h, 3)
  p:box(0, h / 2, 2.5, 0.2, h, 3)
end

local function bake()
  local data = {}
  local proj = lovr.math.mat4():perspective(math.pi / 2, 1, 0.05) -- far omitted = infinite reverse-Z
  for k = 0, NZ - 1 do
    for j = 0, NY - 1 do
      for i = 0, NX - 1 do
        local x, y, z = ORIGIN[1] + i * SPACING, ORIGIN[2] + j * SPACING, ORIGIN[3] + k * SPACING
        bakePass:reset()
        bakePass:setClear(0, 0, 0, 1) -- sky is black
        for f, r in ipairs(FACES) do
          bakePass:setViewPose(f, x, y, z, unpack(r))
          bakePass:setProjection(f, proj)
        end
        drawScene(bakePass) -- static geometry only: moving objects don't belong in the bake
        lovr.graphics.submit(bakePass)
        for f = 1, 6 do
          local r, g, b = bakeTex:getPixels(0, 0, f, 5):getPixel(0, 0) -- mip 5 = 1x1 = face average
          data[#data + 1] = { r, g, b, 1 }
        end
      end
    end
  end
  probeBuf:setData(data)
end

function P.load()
  lovr.graphics.setBackgroundColor(0, 0, 0)
  H.camera.set(0, 11, 9, 0, -0.9)
  shader = lovr.graphics.newShader('unlit', fragment)
  probeBuf = lovr.graphics.newBuffer('vec4', NX * NY * NZ * 6)
  bakeTex = lovr.graphics.newTexture(16, 16, 6, {
    type = 'array', format = 'rgba16f', mipmaps = true, usage = { 'render', 'transfer' } })
  bakePass = lovr.graphics.newPass({ bakeTex, samples = 1 })
  bake()
end

function P.update(dt)
  local down = lovr.system.isKeyDown
  light[1] = light[1] + ((down('right') and 4 or 0) - (down('left') and 4 or 0)) * dt
  light[3] = light[3] + ((down('down') and 4 or 0) - (down('up') and 4 or 0)) * dt
end

function P.draw(pass)
  local t = lovr.timer.getTime()
  drawScene(pass)

  pass:send('mode', 1)
  pass:setColor(1, 1, 1)
  pass:sphere(math.sin(t * 0.4) * 6.5, 1.2, 0, 0.6)

  if showProbes then
    pass:send('mode', 2) -- probe's own position -> weight 1 on itself
    for k = 0, NZ - 1 do
      for j = 0, NY - 1 do
        for i = 0, NX - 1 do
          pass:sphere(ORIGIN[1] + i * SPACING, ORIGIN[2] + j * SPACING, ORIGIN[3] + k * SPACING, 0.2)
        end
      end
    end
  end

  pass:setShader()
  pass:setColor(1, 1, 0.7)
  pass:sphere(light[1], light[2], light[3], 0.1)
  pass:text('P: probes   arrows: light   R: rebake', 0, 4, -4, 0.4)
end

function P.keypressed(key)
  if key == 'p' then showProbes = not showProbes end
  if key == 'r' then bake() end
end

return P
