-- 10_world: stylized open world, deferred pipeline.
--
-- Modules (each owns its shaders in shaders/):
--   world.lua    terrain (layered noise), rocks/cliffs, white monoliths, clouds, grass shells -> G-buffer
--   lighting.lua sun shadow map, SSAO + 1-bounce screen-space GI, grain-in-the-light, sky, fog -> HDR texture
--   post.lua     ink edges (Borderlands), sun lens flare, color grading, film grain -> window
--
-- Per frame, submitted in order:  G-buffer -> lighting passes (shadow, ao/gi, light) -> window (post)
--
-- G-buffer (all w x h, samples = 1):
--   albedo  rgba8 (sRGB)  rgb = albedo, a = material id / 255  (0 = sky, see W.MAT)
--   normal  rgba16f       xyz = world normal, w = extra per-material value (grass: shell height 0..1)
--   pos     rgba32f       xyz = world position, w = linear view depth (0 = sky)
--
-- Env vars (for tooling): PROJECT=10 starts here. SHOT=out.png renders a few frames, saves, quits.
-- CAM="x,y,z,yaw,pitch" overrides the start camera (y = height above ground).

local H = require('src.helper')
local W = require('src.projects.10_world.world')
local L = require('src.projects.10_world.lighting')
local Post = require('src.projects.10_world.post')

local P = {}
local width, height
local g = {}
local shot = os.getenv('SHOT')
local shotFrames, shotTex, shotPass = 0

local function resize(w, h)
  width, height = w, h
  local function rt(format) return lovr.graphics.newTexture(w, h, { format = format, mipmaps = false, usage = { 'render', 'sample' } }) end
  g.albedo, g.normal, g.pos = rt('rgba8'), rt('rgba16f'), rt('rgba32f')
  g.pass = lovr.graphics.newPass({ g.albedo, g.normal, g.pos, depth = 'd32f', samples = 1 })
  L.resize(w, h)
  Post.resize(w, h)
  if shot then
    shotTex = lovr.graphics.newTexture(w, h, { format = 'rgba8', mipmaps = false, usage = { 'render', 'sample', 'transfer' } })
    shotPass = lovr.graphics.newPass({ shotTex, samples = 1 })
  end
end

function P.load()
  W.load()
  L.load()
  Post.load()
  local c = {}
  for n in (os.getenv('CAM') or ''):gmatch('[^,]+') do c[#c + 1] = tonumber(n) end
  local x, z = c[1] or 0, c[3] or 30
  H.camera.set(x, W.height(x, z) + (c[2] or 4), z, c[4] or 0, c[5] or 0.05)
  H.camera.speed = 6
  width = nil
end

function P.update(dt)
  W.update(dt)
end

function P.draw(pass)
  local w, h = pass:getDimensions()
  if w ~= width or h ~= height then resize(w, h) end
  local proj = pass:getProjection(1, lovr.math.mat4())
  local camPose = pass:getViewPose(1, lovr.math.mat4())

  g.pass:reset()
  g.pass:setClear(0, 0, 0, 0) -- all targets; depth clears to 0 (reverse-Z)
  g.pass:setProjection(1, proj)
  g.pass:setViewPose(1, camPose)
  g.pass:setBlendMode()
  W.drawGBuffer(g.pass)

  local lightPasses = L.render(g, proj, camPose, W)

  local out = shot and shotPass or pass
  if shot then out:reset() end
  out:setProjection(1, proj)
  out:setViewPose(1, camPose)
  Post.draw(out, L.hdr, g, L.sunDir)

  local passes = { g.pass }
  for _, p in ipairs(lightPasses) do passes[#passes + 1] = p end
  passes[#passes + 1] = out
  lovr.graphics.submit(passes)

  if shot then
    shotFrames = shotFrames + 1
    if shotFrames == 5 then
      local f = io.open(shot, 'wb')
      f:write(shotTex:getPixels():encode():getString())
      f:close()
      lovr.event.quit()
    end
  end
  return true
end

function P.keypressed(key)
  W.keypressed(key)
  L.keypressed(key)
  Post.keypressed(key)
end

return P
