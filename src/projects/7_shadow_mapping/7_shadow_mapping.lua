-- 7_shadow_mapping: one directional "sun" light casting shadows.
--
-- Two passes per frame, submitted together:
--   1) shadowPass -> shadowMap (depth texture, no color targets).
--      Camera = the light: orthographic projection (sun rays are parallel) looking along the light dir.
--      Only depth gets written: the "distance photo" from the light.
--   2) window pass: each fragment re-projects its world position with the SAME light matrix and
--      compares its depth against the stored depth. Further than stored = something is in front = shadow.
--
-- Depth convention: LOVR's default camera is reverse-Z (near = 1, far = 0, test 'gequal').
-- mat4:orthographic is regular Z (near = 0, far = 1), so the shadow pass uses test 'lequal' and clears to 1.
--
-- Keys: B toggles bias (off = "shadow acne" stripes), V shows the shadow map.

local H = require('src.helper')
local P = {}

local litFragment = --[[glsl]] [[
uniform texture2D shadowMap;
uniform sampler shadowSampler; // compare sampler: returns 1 (lit) / 0 (shadow) instead of depth
uniform mat4 lightViewProj;
uniform vec3 lightDir;         // direction TOWARDS the light

vec4 lovrmain() {
  vec4 clip = lightViewProj * vec4(PositionWorld, 1.);
  vec2 uv = clip.xy * .5 + .5; // ortho: w = 1, no divide needed
  // Hardware compare: clip.z <= stored depth ? 1 : 0. Linear filtering blends 4 compares -> soft-ish edges.
  float lit = texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv, clip.z));

  float diffuse = max(dot(normalize(Normal), normalize(lightDir)), 0.);
  return vec4(Color.rgb * (0.2 + diffuse * lit), Color.a); // shadow removes direct light, ambient stays
}
]]

local litShader, shadowMap, shadowPass, shadowSampler
local biasOn, showMap = true, false

function P.load()
  lovr.graphics.setBackgroundColor(0.55, 0.7, 0.9)
  H.camera.set(0, 5, 14, 0, -0.3)
  litShader = lovr.graphics.newShader('unlit', litFragment)

  -- Depth-only render target that we can also sample later.
  shadowMap = lovr.graphics.newTexture(2048, 2048, { format = 'd32f', mipmaps = false, usage = { 'render', 'sample' } })
  shadowPass = lovr.graphics.newPass({ depth = shadowMap, samples = 1 })
  shadowSampler = lovr.graphics.newSampler({ filter = 'linear', wrap = 'clamp', compare = 'lequal' })
end

-- Same geometry for both passes. Colors are ignored by the shadow pass.
local function drawScene(p, t)
  p:setColor(0.75, 0.75, 0.7)
  p:plane(0, 0, 0, 30, 30, -math.pi / 2, 1, 0, 0)
  p:setColor(0.85, 0.3, 0.25)
  p:box(-4, 1, -2, 1.5, 2, 1.5)
  p:setColor(0.3, 0.6, 0.9)
  p:box(4, 2, -3, 1, 4, 1)
  p:setColor(0.9, 0.8, 0.3)
  p:sphere(0, 1.2 + math.sin(t * 1.5) * 0.6, 0, 0.8)
  p:setColor(0.4, 0.85, 0.45)
  p:torus(3, 1.5, 3, 1, 0.25, t * 0.7, 1, 1, 0)
  p:setColor(0.8, 0.8, 0.85)
  for i = -3, 3 do
    p:cylinder(i * 1.5, 1.5, 6, 0.12, 3, math.pi / 2, 1, 0, 0)
  end
end

function P.draw(pass)
  local t = lovr.timer.getTime()

  -- Sun direction (towards the light): fixed elevation, slowly orbiting.
  local dir = lovr.math.vec3(math.cos(t * 0.2), 1, math.sin(t * 0.2)):normalize()

  -- 1) Shadow pass from the light. lightViewProj maps world -> light clip space.
  local view = lovr.math.mat4():lookAt(dir * 25, lovr.math.vec3(0, 0, 0))
  local proj = lovr.math.mat4():orthographic(-12, 12, -12, 12, 1, 50)

  shadowPass:reset()
  shadowPass:setClear({ depth = 1 })
  shadowPass:setViewPose(1, view, true) -- true = already a view matrix
  shadowPass:setProjection(1, proj)
  shadowPass:setDepthTest('lequal')
  -- Bias: push stored depth away from the light, more on surfaces seen edge-on (sloped).
  if biasOn then shadowPass:setDepthOffset(1, 2) end
  drawScene(shadowPass, t)

  -- 2) Main pass.
  if showMap then
    pass:fill(shadowMap) -- depth samples as (d, 0, 0, 1), so it shows up red
  else
    pass:setShader(litShader)
    pass:send('shadowMap', shadowMap)
    pass:send('shadowSampler', shadowSampler)
    pass:send('lightViewProj', proj * view)
    pass:send('lightDir', dir)
    drawScene(pass, t)
  end

  lovr.graphics.submit(shadowPass, pass)
  return true
end

function P.keypressed(key)
  if key == 'b' then biasOn = not biasOn end
  if key == 'v' then showMap = not showMap end
end

return P
