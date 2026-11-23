-- 5_models_and_rigging: glTF via lovr.graphics.newModel: node hierarchy, materials, animation, clones.
-- Fox.glb: Khronos glTF-Sample-Assets (CC-BY 4.0, PixelMannen / tomkranis / @AsoboStudio). Skinned, 3 animations.
-- Keys: Space = crossfade main fox to next animation, K = toggle skeleton, H = toggle head override.
local H = require("src.helper")
local P = {}
local DIR = 'src/projects/5_models_and_rigging/'
local S = 0.01 -- Fox is authored in cm (~79 units tall)

local fox, plain, clones
local anim, prev, fadeStart = 1, nil, 0
local FADE = 0.4
local showSkeleton, headOverride = true, false

function P.load()
  lovr.graphics.setBackgroundColor(0.08, 0.08, 0.1)
  if fox then return end

  -- One file -> vertex/index buffers, textures, materials, node tree, skin, animations, all on the GPU.
  fox = lovr.graphics.newModel(DIR .. 'Fox.glb')

  -- materials=false: textures/materials are skipped; the mesh uses whatever pass:setMaterial/setColor says.
  plain = lovr.graphics.newModel(DIR .. 'Fox.glb', { materials = false })

  -- clone(): shares buffers/textures with `fox`, but has its own node transforms (animation state).
  clones = {}
  for i = 1, fox:getAnimationCount() do clones[i] = fox:clone() end

  print(('nodes %d  meshes %d  materials %d  textures %d  joints %s'):format(
    fox:getNodeCount(), fox:getMeshCount(), fox:getMaterialCount(), fox:getTextureCount(), fox:hasJoints()))
  print('dimensions', fox:getDimensions())
  for i = 1, fox:getAnimationCount() do
    print('animation', i, fox:getAnimationName(i), fox:getAnimationDuration(i))
  end
  -- A glTF PBR material becomes a Material: a table of factors + textures the shader reads.
  for k, v in pairs(fox:getMaterial(1):getProperties()) do
    print('material.' .. k, type(v) == 'table' and table.concat(v, ', ') or v)
  end
end

local function printTree(model, node, depth)
  print(('  '):rep(depth) .. (model:getNodeName(node) or '<scene root>') .. (model:getNodeMesh(node) and ' [mesh]' or ''))
  -- Not getNodeChildren: in 0.19.1 it returns { [childIndex] = childIndex } (sparse), so ipairs stops early.
  local child = model:getNodeChild(node)
  while child do
    printTree(model, child, depth + 1)
    child = model:getNodeSibling(child)
  end
end

function P.keypressed(key)
  if key == 'space' then
    prev, fadeStart = anim, lovr.timer.getTime()
    anim = anim % fox:getAnimationCount() + 1
  elseif key == 'k' then
    showSkeleton = not showSkeleton
  elseif key == 'h' then
    headOverride = not headOverride
  elseif key == 't' then
    printTree(fox, fox:getRootNode(), 0)
  end
end

function P.update(dt)
  local t = lovr.timer.getTime()

  -- Each clone plays a different animation; time wraps automatically past the duration.
  for i, c in ipairs(clones) do c:animate(i, t) end
  plain:animate('Run', t * 0.5) -- speed = scale the timestamp

  -- Crossfade: apply the old animation fully, then blend the new one over it by k.
  local k = prev and math.min((t - fadeStart) / FADE, 1) or 1
  if prev and k < 1 then fox:animate(prev, t, 1) end
  fox:animate(anim, t, k)
  if k >= 1 then prev = nil end

  -- Manual override after animate: nodes are just local TRS transforms you can poke.
  -- 'parent' = local space. Compose a sway on top of whatever the animation set.
  if headOverride then
    local q = lovr.math.quat(fox:getNodeOrientation('b_Head_05', 'parent'))
    fox:setNodeOrientation('b_Head_05', q * lovr.math.quat(math.sin(t * 3) * 0.8, 1, 0, 0))
  end
end

-- getNodePosition(..., 'root') = position in model space; parent->child lines = the joint hierarchy.
local function drawSkeleton(pass, model)
  for i = 1, model:getNodeCount() do
    local p = model:getNodeParent(i)
    local name = model:getNodeName(i)
    if p and name and name:find('^b_') then
      local x1, y1, z1 = model:getNodePosition(p, 'root')
      local x2, y2, z2 = model:getNodePosition(i, 'root')
      pass:line(x1, y1, z1, x2, y2, z2)
      pass:sphere(x2, y2, z2, 1.5)
    end
  end
end

function P.draw(pass)
  local t = lovr.timer.getTime()
  local z = -4

  H.light(pass, 2, 4, 0)
  pass:setColor(1, 1, 1)

  -- Main fox: model uses its own materials (base color texture -> ColorTexture in the phong shader).
  pass:draw(fox, 0, 0, z, S, 0.5, 0, 1, 0)

  for i, c in ipairs(clones) do
    pass:draw(c, -4 + (i - 1) * 1.4, 0, z - 2, S * 0.7, 0.5, 0, 1, 0)
  end

  -- materials=false model: tint it with pass state instead.
  pass:setColor(0.3, 0.6, 1)
  pass:draw(plain, 3, 0, z, S, -0.5, 0, 1, 0)

  pass:setShader()
  pass:setColor(1, 1, 1)
  pass:plane(0, 0, z - 1, 12, 8, -math.pi / 2, 1, 0, 0, 'line', 12, 8)

  if showSkeleton then
    pass:push('state')
    pass:setDepthTest() -- see bones through the mesh
    pass:setColor(1, 0.4, 0.2)
    pass:push()
    pass:transform(0, 0, z, S, S, S, 0.5, 0, 1, 0) -- same as the fox draw (transform takes sx,sy,sz, not uniform scale)
    drawSkeleton(pass, fox)
    pass:pop()
    pass:pop('state')
  end

  local fade = prev and ('  <- ' .. fox:getAnimationName(prev)) or ''
  pass:text('5_models_and_rigging: lovr.graphics.newModel(Fox.glb)', 0, 2.6, z, 0.15)
  pass:text(('main: %s%s   [Space] next  [K] skeleton  [H] head override  [T] print node tree'):format(
    fox:getAnimationName(anim), fade), 0, 2.3, z, 0.08)
  for i in ipairs(clones) do
    pass:text('clone: ' .. fox:getAnimationName(i), -4 + (i - 1) * 1.4, 1.1, z - 2, 0.08)
  end
  pass:text('materials=false', 3, 1.1, z, 0.08)
end

return P
