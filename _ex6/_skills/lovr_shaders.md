---
name: "lovr_shaders"
description: "Use for anything to do with LOVR shaders: GLSL builtins, uniforms/buffers/textures, render targets, fullscreen/post passes, compute, flags"
---

# LOVR 0.19 shaders

Sources:
- `etc/shaders/lovr.glsl` @v0.19.1 is the ground truth for builtins.
- `guides/Shaders.md` in lovr-docs. Its attribute location table is out of date.
- `_ex6/lovr_docs/lovr_docs.json` is a local API dump. Grep it for anything missing here.


## Setup

GLSL 4.60, compiled to SPIR-V, run on Vulkan.
Vulkan conventions: NDC y points down, texture v=0 is the top row, depth is 0..1.

LOVR wraps your code like this:
```glsl
#version 460
// multiview extension
#include "lovr.glsl"   // declares all builtins, defines main()
// your code
```

`main()` calls your `lovrmain()`:
- vertex: `vec4 lovrmain()` returns the clip position. `PositionWorld, Normal, UV, UV2, Color, Tangent` are already set and can be overwritten.
- fragment: `vec4 lovrmain()` returns the color for `PixelColor`. Afterwards `main()` applies glow, tonemap and alphaCutoff if those flags are on.
- compute: `void lovrmain()`.
- With `{ raw = true }` there is no prelude and no `lovrmain`. Write your own `main`.

Minimal example:
```lua
local shader = lovr.graphics.newShader('unlit', [[
  uniform vec4 tint;
  vec4 lovrmain() { return DefaultColor * tint; }
]])

function lovr.draw(pass)
  pass:setShader(shader)
  pass:send('tint', { 1, .5, .5, 1 })
  pass:cube(0, 1.7, -2)
  pass:setShader()
end
```

Rules:
- A graphics shader has a vertex and a fragment stage. Either one can be a DefaultShader name to reuse the built-in stage: `newShader('unlit', frag)`, `newShader(vert, 'unlit')`, `newShader('fill', frag)`.
- Stage code can be a GLSL string, a filename, or a Blob of SPIR-V from `compileShader`.
- All state lives on the Pass. `setShader(nil)` goes back to the automatic built-in shader for each draw type.
- No binding numbers needed. Declare `uniform float x;`, `uniform texture2D t;`, `buffer B {...};` and `pass:send` matches by name.
- Compile errors are thrown as Lua errors from `newShader`.
- `newShader` and `compileShader` are async in 0.19 and work on any thread or in `lovr.task`.


## Lua API

### lovr.graphics
- `newShader(vertex, fragment, options?)`
- `newShader(compute, options?)`
- `newShader(defaultShader, options?)`
- options: `flags = { name|id = number|bool }`, `label = string`, `raw = bool`
- `compileShader(vertex, fragment)` or `compileShader(compute)` returns SPIR-V Blobs
- `newSampler{ filter, wrap, compare, anisotropy, mipmaprange }`
  - filter: `'linear'` or `{ min, mag, mip }`
  - wrap: `'repeat'` or `{ u, v, w }`
  - compare: CompareMode
  - anisotropy: default 1
  - mipmaprange: `{ lo, hi }`
- `newTexture(w, h, { format, mipmaps, usage, linear, label })`
  - usage: any of `'sample', 'render', 'storage', 'transfer'`
- `newPass(...textures)`, `newPass(canvas)`, `newPass()`
  - canvas: `{ tex1, tex2, ..., depth = ..., samples = 1|4 }`
  - depth: Texture, format, false, or `{ format, texture }`. Default `'d32f'`.
  - samples: default 4
- `newBuffer(format, data|count)`
- `newRaytracer(capacity, { dynamic, fasttrace, fastbuild, compress })`
- `submit(...passes)` submits in order. Return `true` from `lovr.draw` to skip the automatic window pass submit.

### Shader
- `clone(flags)` - new variant with different flags, no recompile
- `getBufferFormat(name)` - returns format, length. Use it to build a matching Buffer. Blocks containing a single array or struct are unwrapped.
- `getWorkgroupSize()` - x, y, z
- `getType()` - `'graphics'` or `'compute'`
- `hasStage(stage)`
- `hasAttribute(name|location)`
- `hasVariable(name)`
- `getLabel()`

### Pass
Shader and resources:
- `setShader(shader | DefaultShader | nil)`
- `send(name, value)` - value is number, bool, table, vector, matrix, Texture or Sampler. Values stay bound across `setShader` if name and type match.
- `send(name, buffer, offset?, extent?)`
- `setSampler(Sampler | 'nearest' | 'linear' | 'cubic')` - the sampler behind `Sampler` and `getPixel`
- `setMaterial(Material | Texture | nil)`

Draw and compute:
- `fill(texture?)` - fullscreen triangle. Runs the current custom shader if set; build it with `newShader('fill', frag)`.
- `compute(x, y, z)`
- `compute(buffer, offset)` - indirect
- All computes in a Pass run before its draws, in parallel unless separated by `pass:barrier()`.

Targets and camera:
- `setCanvas(...)`, `getCanvas()`
- `setClear(r, g, b, a | hex | bool | { colors..., depth, stencil })`
- `reset()` - clears recorded commands. Call it each frame on a pass you keep around.
- `setViewPose(view, mat4 | pose, inverted?)`
- `setProjection(view, mat4)` (the number form `left, right, up, down, near, far` is deprecated; build a mat4 with `:fov(...)` instead)
- `getProjection(view, mat4)` - fills the mat4

Render state:
- `setBlendMode(index?, mode?, alphaMode?)` - no args turns blending off
- `setDepthTest(CompareMode?)`, `setDepthWrite(bool)`, `setDepthOffset`, `setDepthClamp`
- `setFaceCull('back' | 'front' | 'none' | bool)` (true = 'back'; `setCullMode` is the deprecated name), `setWinding`
- `setColorWrite(index?, bool | r, g, b, a)`
- `setStencilTest`, `setStencilWrite`
- `setMeshMode('triangles' | 'lines' | 'points')`
- `setViewCull(bool)`, `setWireframe(bool)`, `setColor(...)`

### Enums
- DefaultShader: `unlit, normal, font, cubemap, equirect, fill`
- ShaderType: `graphics, compute`
- ShaderStage: `vertex, fragment, compute`
- Builtin flags (constant_id 1000+, default in brackets):
  `pointSize [1], passColor [T], materialColor [T], vertexColors [T], uvTransform [T], alphaCutoff [F], glow [F], normalMap [F], vertexTangents [T], colorTexture [T], glowTexture [T], metalnessTexture [T], roughnessTexture [T], ambientOcclusion [T], clearcoatTexture [F], tonemap [F]`


## GLSL builtins

### All graphics stages
- `vec2 Resolution` - canvas size in pixels
- `float Time`
- `sampler Sampler` - set by `Pass:setSampler`
- `int ViewIndex` - multiview eye, 0 on desktop
- `mat4 View, Projection, ViewProjection, InverseProjection`
- `vec3 CameraPositionWorld`
- `PI, TAU, PI_2`
- `ClipDistance, CullDistance, PrimitiveID`

### Vertex
Attributes (location):
- `vec4 VertexPosition` (10)
- `vec3 VertexNormal` (11)
- `vec2 VertexUV` (12)
- `vec2 VertexUV2` (13)
- `vec4 VertexColor` (14)
- `vec4 VertexTangent` (15) - w is handedness
- Custom: `in vec3 myAttr;` matches a Buffer/Mesh format field by name.

Other:
- `mat4 Transform` - same as `WorldFromLocal`
- `mat3 NormalMatrix`
- `vec4 PassColor`
- Matrices: `ClipFromLocal, ClipFromWorld, ClipFromView, ViewFromLocal, ViewFromWorld, ViewFromClip, WorldFromLocal, WorldFromView, WorldFromClip`
- `DefaultPosition` - `ClipFromLocal * VertexPosition`
- `VertexIndex, InstanceIndex, BaseVertex, BaseInstance, DrawIndex, PointSize, Position`

### Fragment
Inputs:
- `vec3 PositionWorld`
- `vec3 Normal` - world space, not normalized
- `vec2 UV, UV2`
- `vec4 Color` - pass color x material color x vertex color, depending on flags
- `vec4 Tangent`

Other:
- `DefaultColor` - `Color * getPixel(ColorTexture, UV)`
- `mat3 TangentMatrix`
- `FragCoord, FragDepth, FrontFacing, PointCoord, SampleID, SampleMask, SampleMaskIn, SamplePosition`

Outputs:
- `PixelColor` - location 0, the `lovrmain` return value
- Extra targets: declare `layout(location = 1) out vec4 second;` and write it in `lovrmain`. Locations map to canvas textures in order.

### Compute
- Declare `layout(local_size_x = 8, local_size_y = 8) in;` yourself.
- `GlobalThreadID, LocalThreadID, LocalThreadIndex, WorkgroupID, WorkgroupSize, WorkgroupCount, SubgroupCount`

### Material
Set by `Pass:setMaterial`. A plain Texture becomes `ColorTexture`.
- `Material.color, glow, uvShift, uvScale, sdfRange, metalness, roughness, clearcoat, clearcoatRoughness, occlusionStrength, normalScale, alphaCutoff`
- `Material.glow.a` is the glow strength.
- Textures: `ColorTexture, GlowTexture, MetalnessTexture (b), RoughnessTexture (g), ClearcoatTexture (r), OcclusionTexture (r), NormalTexture`
- Unset textures are 1x1 white. The normal map default is flat.

### Functions
Sampling with the pass sampler:
- `getPixel(texture2D, vec2)`
- `getPixel(texture3D, vec3)`
- `getPixel(textureCube, vec3)`
- `getPixel(texture2DArray, vec2, float layer)`
- `getPixel(textureCubeArray, vec4)`
- Same overloads take a combined `sampler2D(tex, mySampler)` etc.

Raw sampling:
- `texture(sampler2D(tex, Sampler), uv)`
- `texelFetch(tex, ivec2, lod)` needs `#extension GL_EXT_samplerless_texture_functions : require`

PBR:
- `struct Surface`, `getDefaultSurface()`, `newSurface()`
- `applyMaterial(inout s)`, `finalizeSurface(inout s)`
- `getLighting(s, vec3 lightDir, vec4 color, float visibility)`
- `getIndirectLighting(s, textureCube env, vec3 sh[9])`
- `D_GGX, G_SmithGGXCorrelated, F_Schlick, prefilteredBRDF, evaluateSphericalHarmonics`

Color:
- `tonemap` (ACES), `gammaToLinear, linearToGamma, pqToLinear, linearToPQ, sRGBToRec2020, rec2020ToSRGB`

Misc:
- `packSnorm10x3(vec4)`, `unpackSnorm10x3(uint)`
- `cofactor3(mat4x3)` - vertex only

### Resource declarations
All bound with `pass:send(name, ...)`.
- `uniform float x;` (or vec, mat, array) - send a number, table, or vector/matrix. Arrays and structs as tables is untested.
- `uniform Block { ... };` - uniform buffer
- `buffer Block { ... };` - storage buffer, writable in compute
- `layout(scalar)` on a block drops std140/std430 padding.
- `uniform texture2D name;` - also `texture3D, textureCube, texture2DArray, textureCubeArray, texture2DMS`. Texture needs usage `'sample'`.
- `layout(rgba8) uniform image2D name;` - storage image. Texture needs usage `'storage'`.
- `uniform sampler name;`
- `uniform raytracer name;` - an `accelerationStructureEXT`. Query with `rayQueryEXT`, `rayQueryInitializeEXT(q, name, flags, 0xff, origin, tmin, dir, tmax)`, `rayQueryProceedEXT`, `rayQueryGetIntersectionTypeEXT`.

Flags:
- `layout(constant_id = N) const bool|int|float flag_name = default;` with N < 1000
- Set with `newShader(..., { flags = { name = v } })` or `shader:clone{ name = v }`. The `flag_` prefix is dropped.

### Built-in stage sources
- `fill.vert` - fullscreen triangle from `VertexIndex`, `UV = ndc * .5 + .5`, z = 1
- `unlit` - `DefaultPosition` and `DefaultColor`
- `normal.frag` - `normalize(Normal) * .5 + .5`
- `cubemap`, `equirect` - skybox, use with `pass:skybox`
- `font.frag` - MSDF using `Material.sdfRange`


## Recipes and gotchas
Tested in `src/projects/3_ssao` (SSAO).

Offscreen pipeline:
- Once (and on resize): create textures, then `newPass({ tex, depth = 'd32f', samples = 1 })`.
- Each frame: `p:reset()`, `p:setClear(...)`, copy the camera, record draws.
- Copy the camera: `setViewPose` the same as the window. `windowPass:getProjection(1, m)` fills mat4 `m`, then `p:setProjection(1, m)`.
- Submit: `lovr.graphics.submit(p1, p2, windowPass)` then `return true` from `lovr.draw`.

Gotchas:
- New passes clear to transparent black. Set `setClear` after `reset()`.
- Data in alpha gets mangled by default alpha blending. Call `pass:setBlendMode()` first.
- Store depth in `rgba32f`. 16f loses precision at distance.
- Read exact texels with `pass:setSampler('nearest')`.
- To sample a render target, render it with `samples = 1` and give it `usage = { 'render', 'sample' }`.
- `Projection`-based UV `clip.xy / clip.w * .5 + .5` matches the fill UV.

Snippets:
```glsl
vec3 nView = mat3(View) * normalize(Normal);
float linearDepth = -(View * vec4(PositionWorld, 1)).z;

// view position from uv + linear depth
vec4 p = InverseProjection * vec4(uv * 2 - 1, .5, 1);
p.xyz /= p.w;
vec3 pos = p.xyz * (depth / -p.z);
```
