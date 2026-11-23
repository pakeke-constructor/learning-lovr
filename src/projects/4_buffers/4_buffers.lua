-- 4_buffers: a tonne of cubes in ONE draw call (instancing).
-- Per-cube transforms live in a GPU Buffer of mat4s; the vertex shader picks one with InstanceIndex.

local H = require('src.helper')
local P = {}
local N = 20000
local shader, transforms, cube

local vertex = --[[glsl]] [[
readonly buffer Transforms { mat4 transforms[]; };

vec4 lovrmain() {
  mat4 m = Transform * transforms[InstanceIndex];
  PositionWorld = vec3(m * VertexPosition);
  Normal = mat3(m) * VertexNormal; // fine for rotation + uniform scale
  Color.rgb *= .5 + .5 * fract(vec3(InstanceIndex) * vec3(.13, .37, .71));
  return ViewProjection * vec4(PositionWorld, 1);
}
]]

function P.load()
  shader = shader or lovr.graphics.newShader(vertex, H.phongFragment)
  cube = cube or lovr.graphics.newModel('src/projects/2_models_and_texs/cube.obj')
  local mats, r = {}, lovr.math.random
  for i = 1, N do
    mats[i] = lovr.math.mat4()
      :translate((r() - .5) * 80, r() * 40, (r() - .5) * 80)
      :rotate(r() * math.pi * 2, r() - .5, r() - .5, r() - .5)
      :scale(.2 + r() * .6)
  end
  transforms = lovr.graphics.newBuffer('mat4', mats) -- uploaded once, lives on the GPU
end

function P.draw(pass)
  H.light(pass, 0, 30, 0)   -- binds phong + sends light uniforms...
  pass:setShader(shader)    -- ...which stay bound since names/types match
  pass:send('Transforms', transforms) -- buffers bind by block name, not member name
  pass:setColor(1, 1, 1)
  pass:draw(cube, 0, 0, 0, 1, 0, 0, 1, 0, N)
end

return P
