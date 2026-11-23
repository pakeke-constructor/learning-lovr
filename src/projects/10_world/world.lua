-- World: everything that writes the G-buffer.
--   terrain   CPU heightfield (5 noise layers), split into 40m chunk meshes (view culling + grass LOD)
--   grass     shell texturing: nearby terrain chunks redrawn as N instanced, raised "shells"
--   rocks     a few jittered low-poly spheres, reused with random transforms; stretched/tilted = cliffs
--   monoliths huge white boxes, slightly tilted, buried in the ground
--   clouds    clusters of squashed spheres with the bottom clipped flat, drifting
-- Keys: G toggles grass.

local W = {}
W.MAT = { terrain = 1, grass = 2, rock = 3, monolith = 4, cloud = 5 }

local SIZE, CELL, CHUNK = 800, 2, 40 -- world size, vertex spacing, chunk size (meters)
local SHELLS, SHELL_H, GRASS_DIST, DENSITY = 32, 0.6, 45, 10
local DIR = 'src/projects/10_world/shaders/'

local noise = lovr.math.noise
local chunks, rocks, monoliths, clouds = {}, {}, {}, {}
local gbufShader, flatShader, cloudShader, grassShader
local grassOn, time = true, 0

local function ridge(x, z) return 1 - math.abs(noise(x, z) * 2 - 1) end

-- Layered noise: broad hills + mid hills + sharp ridges + bumps + fine roughness.
function W.height(x, z)
  return (noise(x / 260, z / 260) - .5) * 60
      + (noise(x / 90 + 17, z / 90 - 3) - .5) * 20
      + ridge(x / 150 + 40, z / 150) ^ 2 * 18
      + (noise(x / 22 + 5, z / 22) - .5) * 3
      + (noise(x / 7 - 9, z / 7) - .5) * .6
end

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(e0, e1, x)
  local t = math.max(0, math.min(1, (x - e0) / (e1 - e0)))
  return t * t * (3 - 2 * t)
end

-- Linear-space vertex colors: lush/dry grass patches, dirt on steep slopes.
local function groundColor(x, z, ny)
  local dry = smooth(.35, .7, noise(x / 70 + 100, z / 70))
  local r, g, b = lerp(.09, .30, dry), lerp(.25, .30, dry), lerp(.03, .06, dry)
  local steep = smooth(.88, .72, ny)
  return lerp(r, .25, steep), lerp(g, .18, steep), lerp(b, .11, steep)
end

local function buildTerrain()
  -- Height grid with a 1-cell border so every vertex gets a central-difference normal.
  local n, h = SIZE / CELL, {}
  for j = -1, n + 1 do
    h[j] = {}
    for i = -1, n + 1 do h[j][i] = W.height(-SIZE / 2 + i * CELL, -SIZE / 2 + j * CELL) end
  end

  local q = CHUNK / CELL -- quads per chunk side
  local indices = {}
  for j = 0, q - 1 do
    for i = 0, q - 1 do
      local a = j * (q + 1) + i + 1
      local b, c, d = a + 1, a + q + 1, a + q + 2
      for _, v in ipairs({ a, c, b, b, c, d }) do indices[#indices + 1] = v end
    end
  end

  local format = { { 'VertexPosition', 'vec3' }, { 'VertexNormal', 'vec3' }, { 'VertexColor', 'vec4' } }
  for cj = 0, n / q - 1 do
    for ci = 0, n / q - 1 do
      local verts = {}
      for j = cj * q, cj * q + q do
        for i = ci * q, ci * q + q do
          local x, z, y = -SIZE / 2 + i * CELL, -SIZE / 2 + j * CELL, h[j][i]
          local nx, ny, nz = h[j][i - 1] - h[j][i + 1], 2 * CELL, h[j - 1][i] - h[j + 1][i]
          local len = math.sqrt(nx * nx + ny * ny + nz * nz)
          nx, ny, nz = nx / len, ny / len, nz / len
          local r, g, b = groundColor(x, z, ny)
          verts[#verts + 1] = { x, y, z, nx, ny, nz, r, g, b, 1 }
        end
      end
      local mesh = lovr.graphics.newMesh(format, verts, { storage = 'gpu' })
      mesh:setIndices(indices)
      mesh:computeBoundingBox()
      chunks[#chunks + 1] = { mesh = mesh, x = -SIZE / 2 + (ci + .5) * CHUNK, z = -SIZE / 2 + (cj + .5) * CHUNK }
    end
  end
end

-- Low-poly rock: lat/long sphere, radius bumped by smooth 3D noise, top sliced flat (mesa/cliff look).
-- Flat shading comes from the shader.
local function rockMesh(seed)
  local lon, lat, verts, idx = 8, 6, {}, {}
  for j = 0, lat do
    for i = 0, lon - 1 do
      local th, ph = j / lat * math.pi, i / lon * 2 * math.pi
      local x, y, z = math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)
      local r = .75 + .5 * noise(x * 1.3 + seed, y * 1.3, z * 1.3)
      verts[#verts + 1] = { r * x, math.min(r * y, .6), r * z }
    end
  end
  for j = 0, lat - 1 do
    for i = 0, lon - 1 do
      local a, b = j * lon + i + 1, j * lon + (i + 1) % lon + 1
      local c, d = a + lon, b + lon
      for _, v in ipairs({ a, c, b, b, c, d }) do idx[#idx + 1] = v end
    end
  end
  local mesh = lovr.graphics.newMesh({ { 'VertexPosition', 'vec3' } }, verts, { storage = 'gpu' })
  mesh:setIndices(idx)
  return mesh
end

local function place(list, mesh, x, z, sx, sy, sz, sink, tilt, rng, color)
  local y = W.height(x, z) - sink * sy
  local m = lovr.math.newMat4():translate(x, y, z)
    :rotate(rng:random() * math.pi * 2, 0, 1, 0)
    :rotate(tilt, 1, 0, 0)
    :scale(sx, sy, sz)
  list[#list + 1] = { mesh = mesh, m = m, color = color }
end

local function buildProps()
  local rng = lovr.math.newRandomGenerator(7)
  local function rand(lo, hi) return lo + (hi - lo) * rng:random() end -- rng:random(lo, hi) gives integers
  local meshes = { rockMesh(10), rockMesh(20), rockMesh(30) }
  local function rock() return meshes[rng:random(1, 3)] end
  local function rockColor()
    local v = rand(.75, 1)
    return { .5 * v, .41 * v, .32 * v }
  end

  -- Cliffs: tall, stretched, leaning slabs. First few placed in view of the start camera.
  local cliffSpots = { { -45, -70 }, { 60, -110 }, { -110, -200 }, { 150, -40 } }
  for i = 1, 12 do
    local s = cliffSpots[i] or { rand(-350, 350), rand(-350, 350) }
    local sy = rand(25, 55)
    place(rocks, rock(), s[1], s[2], rand(8, 15), sy, rand(6, 12), .05, rand(.15, .45), rng, rockColor())
    for _ = 1, 4 do -- boulders at its feet
      local x, z = s[1] + rand(-25, 25), s[2] + rand(-25, 25)
      local r = rand(1.5, 5)
      place(rocks, rock(), x, z, r * rand(.8, 1.6), r, r, .3, rand(0, .6), rng, rockColor())
    end
  end
  for _ = 1, 50 do -- scattered boulders, keep the spawn clear
    local x, z = rand(-380, 380), rand(-380, 380)
    if x * x + (z - 30) ^ 2 > 400 then
      local r = rand(.8, 4)
      place(rocks, rock(), x, z, r * rand(.8, 1.8), r, r, .3, rand(0, .8), rng, rockColor())
    end
  end

  -- Monoliths: { x, z, width, height, depth }
  local spots = {
    { -70, -170, 55, 300, 40 }, { 90, -320, 80, 460, 60 }, { -230, -360, 70, 380, 65 }, { 260, -190, 45, 260, 85 },
    { -320, -60, 75, 340, 50 }, { 330, 150, 60, 420, 60 }, { -200, 250, 90, 280, 45 }, { 40, -80, 22, 120, 22 },
  }
  for _, s in ipairs(spots) do
    local x, z, w, hgt, d = s[1], s[2], s[3], s[4], s[5]
    local y = W.height(x, z) + hgt / 2 - 25
    local m = lovr.math.newMat4():translate(x, y, z)
      :rotate(rng:random() * math.pi, 0, 1, 0)
      :rotate(rand(-.08, .08), 1, 0, 0)
      :scale(w, hgt, d)
    monoliths[#monoliths + 1] = m
  end

  -- Clouds: a few squashed blobs each, bottom clipped at `base`.
  for _ = 1, 16 do
    local c = { x = rand(-600, 600), z = rand(-500, 300), y = rand(150, 210), blobs = {} }
    local size = rand(.7, 1.4)
    for _ = 1, rng:random(5, 9) do
      local r = rand(25, 50) * size
      c.blobs[#c.blobs + 1] = { rand(-70, 70) * size, rand(-4, 18) * size, rand(-35, 35) * size, r }
    end
    clouds[#clouds + 1] = c
  end
end

function W.load()
  local function shader(flags)
    return lovr.graphics.newShader('unlit', DIR .. 'world_gbuffer.glsl', { flags = flags })
  end
  gbufShader = shader()
  flatShader = shader({ flatNormals = true })
  cloudShader = shader({ cloud = true })
  grassShader = lovr.graphics.newShader(DIR .. 'world_grass_vert.glsl', DIR .. 'world_grass_frag.glsl')
  chunks, rocks, monoliths, clouds = {}, {}, {}, {}
  buildTerrain()
  buildProps()
end

function W.update(dt) time = time + dt end

function W.keypressed(key)
  if key == 'g' then grassOn = not grassOn end
end

local function cloudX(c) return (c.x + time * 4 + 700) % 1400 - 700 end

-- perCloud(c) runs before each cloud's blobs (G-buffer pass uses it to send the clip height).
local function drawClouds(pass, perCloud)
  for _, c in ipairs(clouds) do
    if perCloud then perCloud(c) end
    local x = cloudX(c)
    for _, b in ipairs(c.blobs) do
      pass:sphere(lovr.math.mat4():translate(x + b[1], c.y + b[2], c.z + b[3]):scale(b[4], b[4] * .55, b[4]), 12, 8)
    end
  end
end

function W.drawShadowCasters(pass)
  pass:setColor(1, 1, 1)
  for _, c in ipairs(chunks) do pass:draw(c.mesh) end
  for _, r in ipairs(rocks) do pass:draw(r.mesh, r.m) end
  for _, m in ipairs(monoliths) do pass:box(m) end
  drawClouds(pass)
end

function W.drawGBuffer(pass)
  pass:setViewCull(true)

  pass:setShader(gbufShader)
  pass:send('material', W.MAT.terrain)
  pass:setColor(1, 1, 1)
  for _, c in ipairs(chunks) do pass:draw(c.mesh) end

  pass:setShader(flatShader)
  pass:send('material', W.MAT.rock)
  for _, r in ipairs(rocks) do
    pass:setColor(r.color[1], r.color[2], r.color[3])
    pass:draw(r.mesh, r.m)
  end
  pass:send('material', W.MAT.monolith)
  pass:setColor(1, 1, .98)
  for _, m in ipairs(monoliths) do pass:box(m) end

  pass:setShader(cloudShader)
  pass:send('material', W.MAT.cloud)
  pass:setColor(1, 1, 1)
  drawClouds(pass, function(c) pass:send('cloudBase', c.y - 3) end)

  if grassOn then
    local cx, cy, cz = pass:getViewPose(1)
    pass:setShader(grassShader)
    pass:send('shellCount', SHELLS)
    pass:send('shellHeight', SHELL_H)
    pass:send('density', DENSITY)
    pass:send('fadeDist', GRASS_DIST)
    pass:setColor(1, 1, 1)
    local reach = GRASS_DIST + CHUNK * .75
    for _, c in ipairs(chunks) do
      if (c.x - cx) ^ 2 + (c.z - cz) ^ 2 < reach * reach then pass:draw(c.mesh, 0, 0, 0, 1, 0, 0, 1, 0, SHELLS) end
    end
  end

  pass:setShader()
  pass:setViewCull(false)
end

return W
