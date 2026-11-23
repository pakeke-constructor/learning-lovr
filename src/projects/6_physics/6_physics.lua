-- 6_physics: lovr.physics (Jolt): world, colliders, joints, motors, raycasts, collision callbacks, fixed step + interpolation.
-- LMB = lock mouse, then push what you aim at (raycast + impulse). RMB = shoot box. G = toggle gravity. Esc = unlock mouse.
local H = require("src.helper")
local cam = H.camera
local P = {}
local world, acc
local STEP = 1 / 60

local function lookDir()
  local s, c, ps, pc = math.sin(cam.yaw), math.cos(cam.yaw), math.sin(cam.pitch), math.cos(cam.pitch)
  return -s * pc, ps, -c * pc
end

function P.load()
  lovr.graphics.setBackgroundColor(0.1, 0.1, 0.12)
  cam.set(0, 2, 6)
  if world then world:destroy() end
  acc = 0
  -- 'static' tags: colliders never move, Jolt skips them in the solver.
  world = lovr.physics.newWorld({ tags = { 'ground', 'wall' }, staticTags = { 'ground', 'wall' } })
  world:newBoxCollider(0, -0.5, 0, 20, 1, 20):setTag('ground')
  -- Invisible walls: 40m cubes whose inner faces line the ground's edges. Not drawn (tag 'wall').
  for _, p in ipairs({ { 30, 0 }, { -30, 0 }, { 0, 30 }, { 0, -30 } }) do
    world:newBoxCollider(p[1], 0, p[2], 40):setTag('wall')
  end

  -- Tower of boxes. Dynamic by default: mass computed from shape volume.
  for y = 0, 5 do
    for x = -1, 1 do world:newBoxCollider(x * 0.42, 0.2 + y * 0.4, -2, 0.4) end
  end

  -- Chain: first link hangs from the world (nil collider), each link ball-jointed to the previous one.
  local prev
  for i = 0, 5 do
    local link = world:newSphereCollider(3, 4 - i * 0.4, -2, 0.15)
    lovr.physics.newBallJoint(prev, link, 3, 4.2 - i * 0.4, -2)
    prev = link
  end

  -- Windmill: plank hinged to the world, velocity motor spins it (rad/s).
  local plank = world:newBoxCollider(-3, 1.5, -2, 2.4, 0.2, 0.2)
  local hinge = lovr.physics.newHingeJoint(nil, plank, -3, 1.5, -2, 0, 0, 1)
  hinge:setMotorMode('velocity')
  hinge:setMotorTarget(2)

  -- Bouncy, slippery stuff via per-collider material properties.
  for i = 1, 4 do
    local b = world:newSphereCollider(-1 + i * 0.5, 3 + i, 0, 0.2)
    b:setRestitution(0.9)
  end

  -- Callbacks run inside world:update. Stamp a hit time to flash colliders on impact.
  world:setCallbacks({
    enter = function(a, b)
      a:setUserData(lovr.timer.getTime());
      b:setUserData(lovr.timer.getTime())
    end
  })
end

-- Returning true consumes the click (main.lua skips the camera). Unlocked: let the camera grab the mouse.
function P.mousepressed(_, _, button)
  if lovr.system.getMouseMode() ~= 'relative' then return end
  local dx, dy, dz = lookDir()
  if button == 1 then
    -- Raycast returns the first hit: collider, shape, hit point, normal.
    local c, _, x, y, z = world:raycast(cam.x, cam.y, cam.z, cam.x + dx * 50, cam.y + dy * 50, cam.z + dz * 50)
    if c then c:applyLinearImpulse(dx * 5, dy * 5, dz * 5, x, y, z) end -- at a point -> also spins
  elseif button == 2 then
    local box = world:newBoxCollider(cam.x + dx, cam.y + dy, cam.z + dz, 0.4)
    box:setContinuous(true) -- CCD: fast bodies don't tunnel through thin stuff
    box:setLinearVelocity(dx * 20, dy * 20, dz * 20)
  end
  return true
end

function P.keypressed(key)
  if key == 'escape' then lovr.system.setMouseMode('normal') end
  if key == 'g' then
    local _, gy = world:getGravity()
    world:setGravity(0, gy == 0 and -9.81 or 0, 0)
    for _, c in ipairs(world:getColliders()) do c:setAwake(true) end -- sleeping bodies won't notice otherwise
  end
end

-- Fixed timestep for stable sim; interpolate() blends poses between the last two steps for smooth rendering.
function P.update(dt)
  acc = acc + dt
  while acc >= STEP do
    world:update(STEP)
    acc = acc - STEP
  end
  world:interpolate(acc / STEP)
end

function P.draw(pass)
  H.light(pass, 3, 6, 4)
  local now = lovr.timer.getTime()
  for _, c in ipairs(world:getColliders()) do
    if c:getTag() == 'wall' then goto continue end
    local shape = c:getShape()
    local flash = math.max(0, 1 - (now - (c:getUserData() or 0)) * 4)
    if c:getTag() == 'ground' then pass:setColor(0.3, 0.32, 0.35)
    elseif c:isAwake() then pass:setColor(0.9, 0.5 + flash * 0.5, 0.2 + flash * 0.8)
    else pass:setColor(0.3, 0.4, 0.8) end -- asleep = blue
    local x, y, z, angle, ax, ay, az = shape:getPose() -- world pose of the shape (collider pose * shape offset)
    if shape:getType() == 'box' then
      local w, h, d = shape:getDimensions()
      pass:box(x, y, z, w, h, d, angle, ax, ay, az)
    else
      pass:sphere(x, y, z, shape:getRadius(), angle, ax, ay, az)
    end
    ::continue::
  end

  pass:setShader()
  pass:setColor(1, 1, 1)
  for _, j in ipairs(world:getJoints()) do
    local x, y, z = j:getAnchors()
    local _, b = j:getColliders()
    pass:line(x, y, z, b:getPosition())
  end
  local dx, dy, dz = lookDir()
  local c, _, x, y, z, nx, ny, nz = world:raycast(cam.x, cam.y, cam.z, cam.x + dx * 50, cam.y + dy * 50, cam.z + dz * 50)
  if c then pass:line(x, y, z, x + nx * 0.5, y + ny * 0.5, z + nz * 0.5) end -- aim marker: hit point + normal
end

return P
