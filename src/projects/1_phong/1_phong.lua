-- 1_phong: primitives + passes + basic Phong lighting.
--
-- How a frame works in LOVR:
--   lovr.draw(pass) receives a Pass for the window/headset. A Pass is a *recorder*:
--   every pass:xyz() call records a draw (with the current state: color, shader,
--   transform stack...). LOVR submits the pass to the GPU after lovr.draw returns.
--   State set on the pass (setColor, setShader, transforms) sticks until changed,
--   and is reset at the start of every frame.

local H = require('src.helper')
local P = {}

function P.load()
  lovr.graphics.setBackgroundColor(0.08, 0.08, 0.1)
end

function P.draw(pass)
  local t = lovr.timer.getTime()
  local lx, ly, lz = math.cos(t) * 2.5, 2.5, -3 + math.sin(t) * 2.5

  -- 1) Lit geometry: bind the shader, then send uniforms (see src/helper.lua).
  H.light(pass, lx, ly, lz)

  -- Ground. Planes face +Z by default, so rotate -90deg around X to face up.
  pass:setColor(0.35, 0.35, 0.4)
  pass:plane(0, 0, -3, 10, 10, -math.pi / 2, 1, 0, 0)

  -- Row of primitives. Signature pattern: (x, y, z, size..., angle, ax, ay, az).
  local y = 1.2
  pass:setColor(0.9, 0.2, 0.2)
  pass:cube(-3, y, -3, 0.6, t, 0, 1, 0)

  pass:setColor(0.9, 0.6, 0.2)
  pass:box(-1.8, y, -3, 0.8, 0.4, 0.4, t, 1, 1, 0)

  pass:setColor(0.9, 0.9, 0.2)
  pass:sphere(-0.6, y, -3, 0.35)

  -- Cylinder/cone/capsule run along their local Z axis.
  pass:setColor(0.2, 0.9, 0.3)
  pass:cylinder(0.6, y, -3, 0.25, 0.7, math.pi / 2, 1, 0, 0)

  -- Cone origin is the center of its base; tip points down local -Z (rotated to +Y here).
  pass:setColor(0.2, 0.8, 0.9)
  pass:cone(1.8, y - 0.35, -3, 0.3, 0.7, math.pi / 2, 1, 0, 0)

  pass:setColor(0.3, 0.4, 1.0)
  pass:capsule(3, y, -3, 0.2, 0.5, t, 0, 0, 1)

  -- 2) Transform stack: push, modify, draw, pop. Draws inherit the current transform.
  pass:push()
    pass:translate(0, 0.6, -5)
    pass:rotate(t * 0.5, 0, 1, 0)
    pass:setColor(0.8, 0.3, 0.9)
    pass:torus(0, 0, 0, 0.6, 0.15, math.pi / 2, 1, 0, 0)

    -- Nested: little spheres orbiting, positioned relative to the torus.
    for i = 1, 6 do
      local a = i / 6 * math.pi * 2
      pass:push()
        pass:rotate(a, 0, 1, 0)
        pass:translate(1.2, 0, 0)
        pass:scale(0.15)
        pass:setColor(1, 1, 1)
        pass:sphere()
      pass:pop()
    end
  pass:pop()

  -- Wireframe is also just pass state.
  pass:setWireframe(true)
  pass:setColor(0.6, 0.9, 0.6)
  pass:sphere(-3, 0.6, -5, 0.4)
  pass:setWireframe(false)

  -- 3) Unlit stuff: setShader() with no args returns to the default shader.
  pass:setShader()

  -- Light marker.
  pass:setColor(1, 0.95, 0.85)
  pass:sphere(lx, ly, lz, 0.08)

  -- Lines and points have no normals, so lighting makes no sense for them.
  pass:setColor(1, 1, 1, 0.4)
  pass:line(lx, ly, lz, lx, 0, lz)
  pass:points(lx, 0.01, lz)

  -- World axes.
  pass:setColor(1, 0, 0) pass:line(0, 0.01, -3, 1, 0.01, -3)
  pass:setColor(0, 1, 0) pass:line(0, 0.01, -3, 0, 1, -3)
  pass:setColor(0, 0, 1) pass:line(0, 0.01, -3, 0, 0.01, -2)

  -- Flat circle outline (style 'line') vs filled ('fill').
  pass:setColor(1, 1, 0.4)
  pass:circle(3, 0.6, -5, 0.4, 0, 0, 1, 0, 'line')

  -- Text uses LOVR's built-in font shader when no custom shader is set.
  pass:setColor(1, 1, 1)
  pass:text('1_phong: primitives + phong', 0, 2.3, -3, 0.2)
end

return P
