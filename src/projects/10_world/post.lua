-- Post: lens flare -> filmic tonemap -> color grading -> ink edges -> vignette + grain.
-- Everything is one fullscreen fill (shaders/post_composite.glsl); reads the HDR image + G-buffer.
-- Keys: E ink edges, F lens flare, C grading (off = plain ACES tonemap).

local Post = {}
local shader
local on = { edges = true, flare = true, grade = true }

function Post.load()
  shader = lovr.graphics.newShader('fill', 'src/projects/10_world/shaders/post_composite.glsl')
end

function Post.resize(w, h) end

function Post.keypressed(key)
  if key == 'e' then on.edges = not on.edges end
  if key == 'f' then on.flare = not on.flare end
  if key == 'c' then on.grade = not on.grade end
end

function Post.draw(pass, hdr, g, sunDir)
  pass:setShader(shader)
  pass:setSampler('nearest') -- exact G-buffer texels; HDR is full-res so nearest is fine too
  pass:send('hdr', hdr)
  pass:send('gAlbedo', g.albedo)
  pass:send('gNormal', g.normal)
  pass:send('gPos', g.pos)
  pass:send('sunDir', sunDir)
  pass:send('edgesOn', on.edges and 1 or 0)
  pass:send('flareOn', on.flare and 1 or 0)
  pass:send('gradeOn', on.grade and 1 or 0)
  pass:fill()
  pass:setShader()
end

return Post
