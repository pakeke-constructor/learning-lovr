local H = require("src.helper")
local cam = H.camera

local projects, current = {}, {}
local dirs = lovr.filesystem.getDirectoryItems("src/projects")
table.sort(dirs, function(a, b) return tonumber(a:match("^%d+")) < tonumber(b:match("^%d+")) end)
for _, name in ipairs(dirs) do
  table.insert(projects, require("src.projects." .. name .. "." .. name))
end

local function switch(p)
  if not p then return end
  if current.cleanup then current.cleanup() end
  current = p
  cam.set()
  if p.load then p.load() end
end

function lovr.mousepressed(...)
  if not (current.mousepressed and current.mousepressed(...)) then cam.mousepressed(...) end
end

function lovr.update(dt)
  cam.update(dt)
  if current.update then current.update(dt) end
end

-- Camera applied first; a project can override with its own pass:setViewPose in draw.
function lovr.draw(pass)
  cam.apply(pass)
  if current.draw then return current.draw(pass) end
end

function lovr.mousemoved(...)
  cam.mousemoved(...)
  if current.mousemoved then current.mousemoved(...) end
end

-- PROJECT=10 lovr . -> start in project 10
function lovr.load() switch(projects[tonumber(os.getenv("PROJECT") or "") or 1]) end
function lovr.keypressed(key, ...)
  switch(projects[key == "0" and 10 or tonumber(key)])
  if current.keypressed then current.keypressed(key, ...) end
end
