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

return H
