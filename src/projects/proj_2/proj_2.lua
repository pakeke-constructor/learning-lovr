-- proj_2: hand-rolled .obj loader + texture, loaded with lovr.task.
--
-- A task is a coroutine managed by LOVR's scheduler (resumed from lovr.run via lovr.task.poll).
-- When a task calls an *async* function, it yields; the work runs on a worker thread, and the
-- task resumes with the result once it's done. Meanwhile frames keep rendering.
--   - lovr.graphics.newTexture(path): async inside a task (file read + png decode on a worker).
--   - lovr.thread.call(f, ...):       runs a pure Lua function on a worker (here: the .obj parser).
-- One task per asset, so the models parse in parallel across workers.
-- Task code itself runs on the main thread, so creating the Mesh there is fine.

local H = require('src.helper')
local parseObj = require('src.projects.proj_2.obj')
local P = {}

local DIR = 'src/projects/proj_2/'
local OBJS = { DIR .. 'cube.obj', DIR .. 'teapot/teapot.obj', DIR .. 'suzanne/suzanne.obj' }

-- Per-load state. Tasks capture their own `s`, so tasks still in flight after a project
-- switch write into a discarded table instead of the next load's state.
local S

function P.load()
  lovr.graphics.setBackgroundColor(0.08, 0.08, 0.1)
  local s = { meshes = {} }
  S = s

  lovr.task.start(function()
    s.texture = lovr.graphics.newTexture(DIR .. 'checker.png')
  end)

  for i, path in ipairs(OBJS) do
    lovr.task.start(function()
      local vertices = lovr.thread.call(parseObj, lovr.filesystem.read(path))
      -- Attribute names match the built-in shader inputs, so the default vertex stage just works.
      s.meshes[i] = lovr.graphics.newMesh({
        { 'VertexPosition', 'vec3' },
        { 'VertexNormal', 'vec3' },
        { 'VertexUV', 'vec2' },
      }, vertices)
    end)
  end
end

function P.draw(pass)
  local t = lovr.timer.getTime()
  for i = 1, #OBJS do
    local x = (i - 2) * 1.6
    local mesh = S.meshes[i]
    -- Only the cube (OBJS[1]) is textured; it waits for its texture too.
    local textured = i == 1
    if mesh and (S.texture or not textured) then
      H.light(pass, 2, 3, 0)
      if textured then
        -- A Texture works as a material directly; the shader reads it via ColorTexture.
        pass:setMaterial(S.texture)
      else
        pass:setColor(0.85, 0.8, 0.7)
      end
      pass:draw(mesh, x, 1.7, -3, 1.2, t * 0.5, 0, 1, 0)
      pass:setMaterial()
      pass:setColor(1, 1, 1)
      pass:setShader()
    else
      pass:text('loading...', x, 1.7, -3, 0.15)
    end
  end

  pass:text('proj_2: .obj + texture via lovr.task', 0, 2.7, -3, 0.15)
end

function P.cleanup()
  S = nil
end

return P
