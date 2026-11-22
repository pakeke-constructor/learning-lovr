

# Passes, and lovr.graphics.submit:

A pass is *essentially* just a bunch of draw-commands, and a texture:
```lua
Pass {
    drawCommands: DrawCommand[] -- turned into a vk_CommandBuffer

    transform: Mat4;

    state: { -- kinda like a vk_Pipeline
        shader: Shader, material: Material, font: Font
        color: Color
        blendMode, depthTest, depthWrite, cullMode, winding, wireframe, stencil, ...
    }

    camera: Camera -- :setView stuff
    -- (can have multiple, e.g. cubemap renderer)

    shader: Shader?
    texture: Texture? -- like a canvas

    _access: Access[] -- PRIVATE FIELD: tracks every texture/buffer that was touched.
    -- (submit uses it for barriers)
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
LOVR tracks how each texture was last used within a pass.

If pass_B reads a texture an earlier pass (eg pass_A) wrote, it inserts a barrier:
finish the writes on pass_A first, then make them readable for pass_B.

(Basically: Each pass draws into a texture. A later pass can then read that texture.)
if passes don't share any textures, they will be submitted in parallel.

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



