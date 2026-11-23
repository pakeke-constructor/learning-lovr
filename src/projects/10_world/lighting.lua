-- Lighting for 10_world. Three passes, returned in submit order:
--   1) shadow: depth-only ortho render from the sun. The box (SHADOW_R around a point ahead of the camera)
--      follows the camera, snapped to whole texels so shadow edges don't shimmer while moving.
--   2) ao:     SSAO (alpha) + 1-bounce screen-space GI (rgb), see shaders/light_ao.glsl
--   3) light:  deferred shading into L.hdr (rgba16f, linear), see shaders/light_main.glsl
-- Keys: O AO, I GI, K grain, T animate sun.

local L = {}
local DIR = 'src/projects/10_world/shaders/'
local SHADOW_SIZE, SHADOW_R, SHADOW_DEPTH = 4096, 160, 1200

local azimuth, elevation = 0.5, 0.24 -- radians: a bit right of -Z, ~20 degrees up
L.sunColor = { 3.2, 2.7, 2.1 }
local toggles = { ao = 1, gi = 1, grain = 1 }
local animateSun = false

local depthShader, aoShader, lightShader, shadowSampler
local shadowMap, shadowPass, aoTex, aoPass, lightPass

local function setSun()
  local ce = math.cos(elevation)
  L.sunDir = { math.sin(azimuth) * ce, math.sin(elevation), -math.cos(azimuth) * ce }
end
setSun()

function L.load()
  local common = lovr.filesystem.read(DIR .. 'light_common.glsl')
  aoShader = lovr.graphics.newShader('fill', common .. lovr.filesystem.read(DIR .. 'light_ao.glsl'))
  lightShader = lovr.graphics.newShader('fill', common .. lovr.filesystem.read(DIR .. 'light_main.glsl'))
  depthShader = lovr.graphics.newShader('unlit', 'unlit')
  shadowSampler = lovr.graphics.newSampler({ filter = 'linear', wrap = 'clamp', compare = 'lequal' })
  shadowMap = lovr.graphics.newTexture(SHADOW_SIZE, SHADOW_SIZE, { format = 'd32f', mipmaps = false, usage = { 'render', 'sample' } })
  shadowPass = lovr.graphics.newPass({ depth = shadowMap, samples = 1 })
end

function L.resize(w, h)
  local function rt(format) return lovr.graphics.newTexture(w, h, { format = format, mipmaps = false, usage = { 'render', 'sample' } }) end
  aoTex, L.hdr = rt('rgba16f'), rt('rgba16f')
  aoPass = lovr.graphics.newPass({ aoTex, depth = false, samples = 1 })
  lightPass = lovr.graphics.newPass({ L.hdr, depth = false, samples = 1 })
end

function L.keypressed(key)
  if key == 'o' then toggles.ao = 1 - toggles.ao end
  if key == 'i' then toggles.gi = 1 - toggles.gi end
  if key == 'k' then toggles.grain = 1 - toggles.grain end
  if key == 't' then animateSun = not animateSun end
end

-- Light view looks down -sunDir. Focus = point ahead of the camera, snapped to the shadow texel grid in light space.
local function shadowMatrices(camPose)
  local sun = lovr.math.vec3(L.sunDir[1], L.sunDir[2], L.sunDir[3])
  local view = lovr.math.mat4():lookAt(sun, lovr.math.vec3(0, 0, 0))
  local camPos = lovr.math.vec3(camPose:getPosition())
  local fwd = lovr.math.quat(camPose:getOrientation()) * lovr.math.vec3(0, 0, -1)
  local c = view * (camPos + fwd * (SHADOW_R * 0.6))
  local texel = 2 * SHADOW_R / SHADOW_SIZE
  local x, y = math.floor(c.x / texel) * texel, math.floor(c.y / texel) * texel
  local proj = lovr.math.mat4():orthographic(x - SHADOW_R, x + SHADOW_R, y - SHADOW_R, y + SHADOW_R, -c.z - SHADOW_DEPTH, -c.z + SHADOW_DEPTH)
  return view, proj
end

local function sendCommon(p, g, lightViewProj)
  p:setSampler('nearest')
  p:send('albedoTex', g.albedo)
  p:send('normalTex', g.normal)
  p:send('posTex', g.pos)
  p:send('shadowMap', shadowMap)
  p:send('shadowSampler', shadowSampler)
  p:send('lightViewProj', lightViewProj)
  p:send('sunDir', L.sunDir)
  p:send('sunColor', L.sunColor)
end

function L.render(g, proj, camPose, W)
  if animateSun then
    azimuth = azimuth + lovr.timer.getDelta() * 0.15
    setSun()
  end

  local view, lproj = shadowMatrices(camPose)
  shadowPass:reset()
  shadowPass:setClear({ depth = 1 })
  shadowPass:setViewPose(1, view, true)
  shadowPass:setProjection(1, lproj)
  shadowPass:setDepthTest('lequal')
  shadowPass:setDepthOffset(1, 2)
  shadowPass:setFaceCull('none')
  shadowPass:setShader(depthShader)
  W.drawShadowCasters(shadowPass)
  local lightViewProj = lproj * view

  for _, p in ipairs({ aoPass, lightPass }) do
    p:reset()
    p:setProjection(1, proj)
    p:setViewPose(1, camPose)
    p:setBlendMode()
  end

  aoPass:setShader(aoShader)
  sendCommon(aoPass, g, lightViewProj)
  aoPass:send('giRadius', 6)
  aoPass:fill()

  lightPass:setShader(lightShader)
  sendCommon(lightPass, g, lightViewProj)
  lightPass:send('aoTex', aoTex)
  lightPass:send('aoOn', toggles.ao)
  lightPass:send('giOn', toggles.gi)
  lightPass:send('grainOn', toggles.grain)
  lightPass:fill()

  return { shadowPass, aoPass, lightPass }
end

return L
