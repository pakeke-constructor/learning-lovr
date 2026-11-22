-- Dead-simple .obj parser: v / vt / vn / f. Returns a flat triangle list of
-- { x, y, z, nx, ny, nz, u, v }. Faces with no vn get a flat (per-triangle) normal.
-- Runs on a worker via lovr.thread.call, which sends it as bytecode, so it can't use upvalues.
return function(text)
  local pos, uv, nrm, verts = {}, {}, {}, {}
  for line in text:gmatch('[^\r\n]+') do
    local tag, a, b, c = line:match('^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)')
    if tag == 'v' then
      table.insert(pos, { tonumber(a), tonumber(b), tonumber(c) })
    elseif tag == 'vn' then
      table.insert(nrm, { tonumber(a), tonumber(b), tonumber(c) })
    elseif tag == 'vt' then
      -- OBJ has v=0 at the bottom; LOVR textures have v=0 at the top.
      table.insert(uv, { tonumber(a), 1 - tonumber(b) })
    elseif tag == 'f' then
      local face = {}
      for corner in line:gmatch('%s(%S+)') do
        -- Corner forms: v, v/vt, v//vn, v/vt/vn
        local vi, ti, ni = corner:match('^(%d+)/?(%d*)/?(%d*)$')
        table.insert(face, { pos[tonumber(vi)], uv[tonumber(ti)] or { 0, 0 }, nrm[tonumber(ni)] })
      end
      -- Fan triangulation: (1, 2, 3), (1, 3, 4), ...
      for i = 2, #face - 1 do
        local tri = { face[1], face[i], face[i + 1] }
        -- Flat normal = cross product of two triangle edges (the shader normalizes it).
        local p1, p2, p3 = tri[1][1], tri[2][1], tri[3][1]
        local ux, uy, uz = p2[1] - p1[1], p2[2] - p1[2], p2[3] - p1[3]
        local vx, vy, vz = p3[1] - p1[1], p3[2] - p1[2], p3[3] - p1[3]
        local flat = { uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx }
        for _, corner in ipairs(tri) do
          local p, t, n = corner[1], corner[2], corner[3] or flat
          table.insert(verts, { p[1], p[2], p[3], n[1], n[2], n[3], t[1], t[2] })
        end
      end
    end
  end
  return verts
end
