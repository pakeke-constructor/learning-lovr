-- 2_models_and_texs: hand-rolled .obj loader + texture, loaded with lovr.task.
--
-- A task is a coroutine managed by LOVR's scheduler. When a task calls an *async* function,
-- it yields; the work runs on a worker thread and the task resumes with the result.
-- Meanwhile frames keep rendering.
--   - lovr.graphics.newTexture(path): async inside a task (file read + png decode on a worker).
--   - lovr.thread.call(f, ...):       runs a pure Lua function on a worker (here: the .obj parser).
-- Task code itself runs on the main thread, so creating the Mesh there is fine.

local H = require('src.helper')
local parseObj = require('src.projects.2_models_and_texs.obj')
local P = {}

local DIR = 'src/projects/2_models_and_texs/'
local cube, teapot, texture

-- Attribute names match the built-in shader inputs, so the default vertex stage just works.
local function loadMesh(path)
  local vertices = lovr.thread.call(parseObj, lovr.filesystem.read(path))
  return lovr.graphics.newMesh({
    { 'VertexPosition', 'vec3' },
    { 'VertexNormal', 'vec3' },
    { 'VertexUV', 'vec2' },
  }, vertices)
end

function P.load()
  lovr.graphics.setBackgroundColor(0.08, 0.08, 0.1)
  lovr.task.start(function() texture = lovr.graphics.newTexture(DIR .. 'checker.png') end)
  lovr.task.start(function() cube = loadMesh(DIR .. 'cube.obj') end)
  lovr.task.start(function() teapot = loadMesh(DIR .. 'teapot.obj') end)
end

function P.draw(pass)
  local t = lovr.timer.getTime()
  pass:text('2_models_and_texs: .obj + texture via lovr.task', 0, 2.7, -3, 0.15)

  H.light(pass, 2, 3, 0)

  if cube and texture then
    -- A Texture works as a material directly; the shader reads it via ColorTexture.
    pass:setMaterial(texture)
    pass:draw(cube, -1, 1.7, -3, 1, t * 0.5, 0, 1, 0)
    pass:setMaterial()
  end

  if teapot then
    -- teapot.obj is ~6 units wide and sits on y=0, so scale it down.
    pass:setColor(0.85, 0.8, 0.7)
    pass:draw(teapot, 1, 1.3, -3, 0.25, t * 0.5, 0, 1, 0)
  end
end

return P
