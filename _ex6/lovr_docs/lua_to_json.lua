-- Regenerate: luajit lua_to_json.lua <lovr-docs/api/init.lua> lovr_docs.json
-- Source: https://github.com/bjornbytes/lovr-docs/blob/v0.19.0/api/init.lua
local api = dofile(arg[1])
local function esc(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return m[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end
local function enc(v)
  local t = type(v)
  if t == 'string' then return esc(v) end
  if t ~= 'table' then return tostring(v) end
  local out = {}
  if #v > 0 or next(v) == nil then
    for i = 1, #v do out[i] = enc(v[i]) end
    return '[' .. table.concat(out, ',') .. ']'
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = esc(k) .. ':' .. enc(v[k]) end
  return '{' .. table.concat(out, ',') .. '}'
end
local f = assert(io.open(arg[2], 'wb'))
f:write(enc(api))
f:close()
