

# Shaders:

A LOVR shader is GLSL 4.60 -> SPIR-V -> Vulkan.
You never write `main()`. LOVR wraps your code:
```glsl
#version 460
#include "lovr.glsl"   // declares every builtin, defines main()
// your code: must define lovrmain()
```

```lua
shader = lovr.graphics.newShader(vertexCode, fragmentCode)
shader = lovr.graphics.newShader('unlit', fragmentCode) -- reuse a built-in stage
shader = lovr.graphics.newShader(computeCode)           -- compute
-- built-in stages: unlit, normal, font, cubemap, equirect, fill

pass:setShader(shader) -- pass state, sticks until changed
pass:setShader()       -- back to LOVR's automatic default
```



## what main() does for you (vertex stage):

```glsl
void main() {
  // 1. fill in defaults for every varying
  PositionWorld = vec3(WorldFromLocal * VertexPosition);
  Normal = NormalMatrix * VertexNormal;
  UV = VertexUV;
  Color = PassColor * Material.color * VertexColor;  // (each one toggleable via flags)

  // 2. call YOU. you can overwrite any varying above.
  Position = lovrmain();  // = gl_Position, clip space
}
```

fragment stage is the same idea: `PixelColor = lovrmain();`
(then glow / tonemap / alphaCutoff get applied, if those flags are on.)

=> a vertex shader that just does `return DefaultPosition;` is the default behaviour.



## where the data comes from:
```lua
-- VERTEX ATTRIBUTES (per vertex, from the mesh/buffer)
VertexPosition  -- vec4, local space, w = 1
VertexNormal    -- vec3, local space
VertexUV, VertexColor, VertexTangent
-- custom: `in vec3 myThing;` matches a Buffer format field named 'myThing'

-- PER DRAW (LOVR fills these from pass state on every pass:cube/draw/mesh call)
Transform       -- = WorldFromLocal. transform stack * draw args (x,y,z,scale,angle...)
NormalMatrix    -- inverse-transpose of Transform. correct for non-uniform scale.
PassColor       -- pass:setColor(...)
Material.*      -- pass:setMaterial(...). ColorTexture etc default to 1x1 white.

-- PER CAMERA (pass:setViewPose / setProjection)
View, Projection, ViewProjection, InverseProjection
CameraPositionWorld
ViewIndex       -- which eye (VR). 0 on desktop.

-- GLOBAL
Resolution, Time

-- GPU COUNTERS (vertex stage)
VertexIndex     -- which vertex of the mesh
InstanceIndex   -- which copy, 0..instances-1
```

handy matrices: `ClipFromLocal`, `ClipFromWorld`, `ViewFromWorld`, `WorldFromLocal`, ...
read them right-to-left: `ClipFromWorld * worldPos` = clip pos.
`DefaultPosition` = `ClipFromLocal * VertexPosition`.

aside: under the hood, per-draw data is a uniform array `Draws[256]` of `{ transform, color }`.
each draw call just picks its slot. that's why `pass:cube()` 10k times is mostly CPU cost, not GPU.



## varyings (vertex -> fragment):
```lua
PositionWorld, Normal, UV, UV2, Color, Tangent
-- vertex stage writes them, rasterizer interpolates across the triangle,
-- fragment stage reads them per pixel.
-- interpolation shortens vectors => always normalize(Normal) in the fragment shader.
```



## sending your own data:
```glsl
uniform vec3 lightPos;                          // loose uniform
uniform texture2D tex;                          // texture (usage 'sample')
readonly buffer Transforms { mat4 transforms[]; }; // storage buffer
```
```lua
pass:send('lightPos', { 1, 2, 3 })
pass:send('tex', texture)
pass:send('Transforms', buffer)  -- !! BLOCK name, not member name
-- no binding numbers. LOVR matches by name.
-- sent values survive setShader() if the new shader has the same name + type.
```

GOTCHAS:
- vertex/fragment can't write storage buffers in 0.19 -> must be `readonly buffer`.
  (only compute shaders can write them.)
- buffers bind by block name: `send('transforms', ...)` => "Shader has no variable named 'transforms'".
- sample textures with `getPixel(tex, uv)`, which uses the pass sampler (`pass:setSampler`).



## instancing (see 4_buffers):
```lua
-- once: upload N matrices to the GPU
transforms = lovr.graphics.newBuffer('mat4', listOfMat4s)

-- every frame: ONE draw call, N copies
pass:send('Transforms', transforms)
pass:draw(cube, 0,0,0, 1, 0,0,1,0, N)  -- last arg = instance count
```

```glsl
vec4 lovrmain() {
  mat4 m = Transform * transforms[InstanceIndex]; // this copy's local -> world
  PositionWorld = vec3(m * VertexPosition);       // for lighting
  Normal = mat3(m) * VertexNormal;                // ok for uniform scale only
  return ViewProjection * vec4(PositionWorld, 1); // NOT DefaultPosition (ignores the buffer)
}
```
by itself, instancing draws N copies on top of each other.
the shader has to use InstanceIndex to look something up and make each copy different.



## flags (spec constants):
```glsl
layout(constant_id = 0) const bool flag_fancy = false;
```
```lua
lovr.graphics.newShader(v, f, { flags = { fancy = true } })
shader:clone({ fancy = false }) -- new variant, no recompile
```
builtin flags (1000+): passColor, vertexColors, normalMap, glow, tonemap, alphaCutoff, ...



## fullscreen + compute:
```lua
-- fullscreen effect: built-in 'fill' vertex stage makes a screen-covering triangle, UV 0..1
post = lovr.graphics.newShader('fill', fragCode)
pass:setShader(post); pass:fill(inputTexture)

-- compute: declare layout(local_size_x = 8, local_size_y = 8) in; yourself
pass:setShader(computeShader)
pass:compute(gx, gy, gz) -- all computes in a pass run BEFORE its draws
```
