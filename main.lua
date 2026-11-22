local projects, current = {}, {}
local dirs = lovr.filesystem.getDirectoryItems("src/projects")
table.sort(dirs)
for _, name in ipairs(dirs) do
  table.insert(projects, require("src.projects." .. name .. "." .. name))
end

local function switch(p)
  if not p then return end
  if current.cleanup then current.cleanup() end
  current = p
  if p.load then p.load() end
end

for _, name in ipairs({ "update", "draw", "mousepressed", "mousemoved" }) do
  lovr[name] = function(...)
    if current[name] then return current[name](...) end
  end
end

function lovr.load() switch(projects[1]) end
function lovr.keypressed(key) switch(projects[tonumber(key)]) end
