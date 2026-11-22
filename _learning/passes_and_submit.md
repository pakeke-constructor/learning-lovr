

# Passes, and lovr.graphics.submit:

A pass is *essentially* just a bunch of draw-commands, and a texture:
```lua
Pass {
    drawCommands: DrawCommand[] -- vk_CommandBuffer

    transform: Transform;
    color: Color

    view: View -- this is pretty much just the camera.
    -- (some passes can have multi views, e.g. cubemap renderer)

    shader: Shader?
    texture: Texture? -- like a canvas
}
```

by default, a pass is created automatically.
all draw calls go through here:
```lua
pass:cube(...)
pass:send(...)
pass:fill(...)
```



## submission:
```lua
-- submits passes in order.

-- simple games will have 1-5 passes.
-- more complex 3d games may have 10-20 passes.
-- (super complex AAA titles can have 50 or more passes.)

lovr.graphics.submit(pass1, pass2, pass3)

--[[
## BARRIERS:
LOVR tracks how each texture was last used.

If a pass reads something an earlier pass wrote, it inserts a barrier:
finish the writes, then make them readable.

Each pass draws into a texture. A later pass can then read that texture.

For example:
- `pass1` renders into `texA`.
- `pass2` samples `texA` and renders into `texB`, so there's a barrier before it.
- `pass3` samples `texA` and `texB`, so there's a barrier before that too.

(In raw Vulkan you'd write these barriers yourself, and probably fuck it up.)
]]
```





## compute shaders:
```lua
pass:setShader(computeShader)
pass:send('img', texture) -- bind inputs/outputs like any uniform
pass:compute(gx, gy, gz) -- dispatch gx*gy*gz workgroups (each defaults to 1)
```



