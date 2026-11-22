-- Dead-simple .obj parser. Run on a worker via lovr.thread.call, which serializes the function
-- to bytecode: it must have NO upvalues (only globals + its own locals), so helpers live inside.
--
-- Handles v / vt / vn / f (fan-triangulated, negative indices ok). Everything else is ignored.
-- Returns a flat triangle list of { x, y, z, nx, ny, nz, u, v } (no index buffer).
-- Missing vt -> uv (0, 0). Missing vn -> smooth normals (sum of adjacent face normals per position).
-- The model is also recentered and scaled to fit a unit cube.
return function(text)
  local pos, uv, nrm, tris = {}, {}, {}, {}

  -- OBJ indices are 1-based; negative ones count back from the end of the list so far.
  local function index(s, list)
    local i = tonumber(s)
    if not i then return nil end
    return i < 0 and #list + 1 + i or i
  end

  for line in text:gmatch('[^\r\n]+') do
    local tag, rest = line:match('^(%S+)%s+(.*)$')
    if tag == 'v' or tag == 'vn' then
      local x, y, z = rest:match('(%S+)%s+(%S+)%s+(%S+)')
      table.insert(tag == 'v' and pos or nrm, { tonumber(x), tonumber(y), tonumber(z) })
    elseif tag == 'vt' then
      local u, v = rest:match('(%S+)%s+(%S+)')
      -- OBJ has v=0 at the bottom; LOVR textures have v=0 at the top.
      table.insert(uv, { tonumber(u), 1 - tonumber(v) })
    elseif tag == 'f' then
      local face = {}
      for corner in rest:gmatch('%S+') do
        -- Corner forms: v, v/vt, v//vn, v/vt/vn
        local vi, ti, ni = corner:match('^(-?%d+)/?(-?%d*)/?(-?%d*)$')
        table.insert(face, { p = index(vi, pos), t = index(ti, uv), n = index(ni, nrm) })
      end
      for i = 2, #face - 1 do
        table.insert(tris, { face[1], face[i], face[i + 1] })
      end
    end
  end

  -- Bounding box -> center + scale factor.
  local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for _, p in ipairs(pos) do
    for k = 1, 3 do lo[k], hi[k] = math.min(lo[k], p[k]), math.max(hi[k], p[k]) end
  end
  local c = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
  local s = 1 / math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])

  -- Smooth normals: cross product of two edges = face normal weighted by area; accumulate per position.
  local smooth = {}
  if #nrm == 0 then
    for i = 1, #pos do smooth[i] = { 0, 0, 0 } end
    for _, tri in ipairs(tris) do
      local a, b, d = pos[tri[1].p], pos[tri[2].p], pos[tri[3].p]
      local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local vx, vy, vz = d[1] - a[1], d[2] - a[2], d[3] - a[3]
      local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
      for k = 1, 3 do
        local acc = smooth[tri[k].p]
        acc[1], acc[2], acc[3] = acc[1] + nx, acc[2] + ny, acc[3] + nz
      end
    end
    -- No need to normalize: the fragment shader normalizes Normal anyway.
  end

  local verts = {}
  for _, tri in ipairs(tris) do
    for k = 1, 3 do
      local corner = tri[k]
      local p = pos[corner.p]
      local x, y, z = (p[1] - c[1]) * s, (p[2] - c[2]) * s, (p[3] - c[3]) * s
      local n = nrm[corner.n] or smooth[corner.p]
      local t = uv[corner.t] or { 0, 0 }
      table.insert(verts, { x, y, z, n[1], n[2], n[3], t[1], t[2] })
    end
  end
  return verts
end
