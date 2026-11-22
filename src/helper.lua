-- Shared helpers for all projects. require('src.helper')
local H = {}

-- Phong shader -----------------------------------------------------------------

-- Vertex stage: DefaultPosition = Projection * View * Transform * VertexPosition.
-- LOVR also fills varyings for us: PositionWorld, Normal (world space), Color, UV.
local phongVertex = [[
vec4 lovrmain() {
  return DefaultPosition;
}
]]

-- Fragment stage: classic Phong = ambient + diffuse + specular.
-- Loose uniforms get set from Lua with pass:send(name, value).
-- `Color` already contains pass:setColor() * vertex color.
local phongFragment = [[
uniform vec3 lightPos;
uniform vec3 lightColor;
uniform float shininess;

vec4 lovrmain() {
  vec3 N = normalize(Normal);
  vec3 L = normalize(lightPos - PositionWorld);
  vec3 V = normalize(CameraPositionWorld - PositionWorld);
  vec3 R = reflect(-L, N);

  float ambient = 0.15;
  float diffuse = max(dot(N, L), 0.0);
  float specular = diffuse > 0.0 ? pow(max(dot(R, V), 0.0), shininess) : 0.0;

  vec3 rgb = Color.rgb * (ambient + diffuse * lightColor) + specular * lightColor;
  return vec4(rgb, Color.a);
}
]]

local phong

-- Bind the phong shader on `pass` and send light uniforms.
-- Shader is created lazily (graphics module ready) and shared across projects.
function H.light(pass, lx, ly, lz, color, shininess)
  phong = phong or lovr.graphics.newShader(phongVertex, phongFragment)
  pass:setShader(phong)
  pass:send('lightPos', { lx, ly, lz })
  pass:send('lightColor', color or { 1, 0.95, 0.85 })
  pass:send('shininess', shininess or 32)
end

-- Default fly camera -----------------------------------------------------------
-- Left-drag to look, WASD move, Shift fast. Wired up in main.lua.

local cam = {}
H.camera = cam

-- Set camera position/orientation; omitted args fall back to defaults.
function cam.set(x, y, z, yaw, pitch)
  cam.x, cam.y, cam.z = x or 0, y or 1.7, z or 0
  cam.yaw, cam.pitch = yaw or 0, pitch or 0
end
cam.set()

function cam.update(dt)
  local down = lovr.system.isKeyDown
  local speed = (down('lshift', 'rshift') and 8 or 3) * dt
  local f = (down('w') and 1 or 0) - (down('s') and 1 or 0)
  local r = (down('d') and 1 or 0) - (down('a') and 1 or 0)
  local s, c = math.sin(cam.yaw), math.cos(cam.yaw)
  local ps, pc = math.sin(cam.pitch), math.cos(cam.pitch)
  -- forward = -Z rotated by pitch (X) then yaw (Y) = (-s*pc, ps, -c*pc); right = (c, 0, -s)
  cam.x = cam.x + (-s * pc * f + c * r) * speed
  cam.y = cam.y + ps * f * speed
  cam.z = cam.z + (-c * pc * f - s * r) * speed
end

function cam.mousemoved(x, y, dx, dy)
  if not lovr.system.isMouseDown(1) then return end
  cam.yaw = cam.yaw - dx * 0.004
  cam.pitch = math.max(-1.5, math.min(1.5, cam.pitch - dy * 0.004))
end

-- setViewPose takes the camera's pose (camera -> world); LOVR inverts it into the view matrix.
function cam.apply(pass)
  local pose = lovr.math.mat4():translate(cam.x, cam.y, cam.z):rotate(cam.yaw, 0, 1, 0):rotate(cam.pitch, 1, 0, 0)
  pass:setViewPose(1, pose)
end

return H
