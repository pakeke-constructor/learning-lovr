---
name: "lovr_shaders"
description: "Use for anything to do with LOVR shaders: GLSL builtins, uniforms/buffers/textures, render targets, fullscreen/post passes, compute, flags"
---

# LOVR 0.19 shaders: index

Sources: lovr `etc/shaders/lovr.glsl` @v0.19.1 (the prelude itself; treat as ground truth), lovr-docs `guides/Shaders.md`, local API dump `_ex6/lovr_docs/lovr_docs.json` (grep it for anything not covered here).

## 1. Overall setup

- GLSL 4.60 → compiled to SPIR-V → Vulkan. Coordinate conventions are Vulkan (NDC y down, texture v=0 at top row, depth 0..1).
- Your source is wrapped by LOVR: `#version 460`, multiview extension, then `#include "lovr.glsl"` (the prelude), then your code. The prelude declares every builtin below and defines `main()`, which calls your `lovrmain()`.
  - vertex: `vec4 lovrmain()` returns clip position. `main()` has already filled `PositionWorld, Normal, UV, UV2, Color, Tangent` before calling it (you may overwrite them).
  - fragment: `vec4 lovrmain()` returns color → `PixelColor` (location 0). After it, `main()` applies glow / tonemap / alphaCutoff if those flags are on.
  - compute: `void lovrmain()`.
- `{ raw = true }` option: no prelude, no `lovrmain`; write your own `main`.
- A graphics shader = vertex + fragment. Either stage may be a `DefaultShader` name string, reusing that stage's built-in code: `newShader('unlit', myFrag)`, `newShader(myVert, 'unlit')`, `newShader('fill', myFrag)`.
- Code args can be a GLSL string, a filename, or a Blob (SPIR-V from `lovr.graphics.compileShader`).
- Shaders are objects; state lives on the `Pass`: `pass:setShader(s)` → `pass:send(name, value)` → draw calls. `pass:setShader()` (nil) = automatic built-in per draw type (unlit for meshes, font for text...).
- Binding numbers aren't needed: plain `uniform float x;`, `uniform texture2D t;`, `buffer B {...};` work. LOVR assigns slots and matches `pass:send` by name.
- `newShader` / `compileShader` are async in 0.19 (changelog). Shaders can be created on any thread or inside `lovr.task`.
- Compile errors are raised as Lua errors from `newShader`.

## 2. Lua API

lovr.graphics
- `newShader(vertex, fragment, options?)`, `newShader(compute, options?)`, `newShader(defaultShader, options?)`
  - options: `flags` (table name|id → number|bool), `label` (string), `raw` (bool)
- `compileShader(vertex, fragment)` / `compileShader(compute)` → Blob(s) of SPIR-V
- `newSampler{ filter = 'linear'|{min,mag,mip}, wrap = 'repeat'|{u,v,w}, compare = CompareMode, anisotropy = 1, mipmaprange = {lo,hi} }`
- `newPass(...textures)` / `newPass(canvas)` / `newPass()`; canvas = `{ tex1, tex2.., depth = Texture|format|false|{format=,texture=}, samples = 1|4 }`. The depth format defaults to `'d32f'` and samples default to 4.
- `newTexture(w, h, { format=, mipmaps=, usage = {'sample','render','storage','transfer'}, linear=, label= })`
- `submit(...passes)`: submits in order. Returning `true` from `lovr.draw` skips the automatic window-pass submit (use it after calling `submit(a, b, windowPass)` yourself).
- `newBuffer(format, data|count)`, `newRaytracer(capacity, { dynamic, fasttrace, fastbuild, compress })`

Shader object
- `clone(flags)` cheap variant with different flags (no recompile)
- `getBufferFormat(name)` → format, length. Use it to build a matching `newBuffer`. Single-array and single-struct blocks get unwrapped.
- `getWorkgroupSize()` → x, y, z · `getType()` → 'graphics'|'compute' · `hasStage(stage)` · `hasAttribute(name|location)` · `hasVariable(name)` · `getLabel()`

Pass (shader-relevant)
- `setShader(shader|DefaultShader|nil)`
- `send(name, number|bool|table|vector|matrix)` uniform; `send(name, Texture)`; `send(name, Sampler)`; `send(name, Buffer, offset?, extent?)`. Values persist across `setShader` if the name and type still match.
- `setSampler(Sampler | 'nearest' | 'linear' | 'cubic')`: the sampler used by `getPixel` / `Sampler`
- `fill(texture?)`: fullscreen triangle. With a custom shader set, it runs that shader (build it with `newShader('fill', frag)`).
- `compute(x, y, z)` / `compute(buffer, offset)` (indirect). All computes in a Pass run before its draws, in parallel unless `pass:barrier()` is between them.
- `setCanvas(...)`, `getCanvas()`, `setClear(r,g,b,a | hex | bool | {colors..., depth=, stencil=})`, `reset()` (re-record a retained pass each frame)
- `setViewPose(view, mat4|pose[, inverted])`, `setProjection(view, mat4 | left,right,up,down,near,far)`, `getProjection(view, mat4)` → fills mat4 (copy the window's projection to offscreen passes)
- Render state: `setBlendMode([index,] mode?, alphaMode?)` (no args = blending off), `setDepthTest(CompareMode?)`, `setDepthWrite(bool)`, `setDepthOffset`, `setDepthClamp`, `setCullMode('back'|'front'|nil)`, `setWinding`, `setColorWrite([index,] bool | r,g,b,a)`, `setStencilTest`, `setStencilWrite`, `setMeshMode('triangles'|'lines'|'points')`, `setViewCull(bool)`, `setWireframe(bool)`, `setMaterial(Material|Texture|nil)`, `setColor(...)`

Enums
- DefaultShader: `unlit normal font cubemap equirect fill`
- ShaderType: `graphics compute` · ShaderStage: `vertex fragment compute`
- ShaderFlag (builtin, constant_id ≥ 1000; set via `flags = {}`): `pointSize(1) passColor(T) materialColor(T) vertexColors(T) uvTransform(T) alphaCutoff(F) glow(F) normalMap(F) vertexTangents(T) colorTexture(T) glowTexture(T) metalnessTexture(T) roughnessTexture(T) ambientOcclusion(T) clearcoatTexture(F) tonemap(F)`

## 3. GLSL builtins (from lovr.glsl)

Globals (vertex + fragment)
- `vec2 Resolution` (current pass canvas size, px) · `float Time`
- `sampler Sampler` (from `Pass:setSampler`)
- `int ViewIndex` (multiview eye; 0 on desktop)
- Camera macros: `View`, `Projection`, `ViewProjection`, `InverseProjection` (mat4, from `Cameras[ViewIndex]`), `vec3 CameraPositionWorld`. These work in the fragment stage too.
- Constants: `PI`, `TAU`, `PI_2`
- `ClipDistance`, `CullDistance`, `PrimitiveID`

Vertex-only
- Attributes (location): `vec4 VertexPosition(10)`, `vec3 VertexNormal(11)`, `vec2 VertexUV(12)`, `vec2 VertexUV2(13)`, `vec4 VertexColor(14)`, `vec4 VertexTangent(15)` (w = handedness). The guide's location table is stale; these numbers are from lovr.glsl.
- Custom attributes: `in vec3 myAttr;` matched by name to a Buffer/Mesh format field.
- Matrices: `Transform` (= `WorldFromLocal`), `NormalMatrix` (mat3), `PassColor` (vec4)
- Space macros: `ClipFromLocal ClipFromWorld ClipFromView ViewFromLocal ViewFromWorld ViewFromClip WorldFromLocal WorldFromView WorldFromClip`
- `DefaultPosition` = `ClipFromLocal * VertexPosition`
- `VertexIndex InstanceIndex BaseVertex BaseInstance DrawIndex PointSize Position`

Fragment-only
- Varyings (in): `vec3 PositionWorld`, `vec3 Normal` (world, not normalized), `vec2 UV`, `vec2 UV2`, `vec4 Color` (= pass × material × vertex color, depending on flags), `vec4 Tangent`
- `DefaultColor` = `Color * getPixel(ColorTexture, UV)` · `mat3 TangentMatrix`
- `FragCoord FragDepth FrontFacing PointCoord SampleID SampleMask SampleMaskIn SamplePosition`
- Output: `PixelColor` (location 0, = lovrmain return). Extra render targets: declare `layout(location = 1) out vec4 second;` and write it inside lovrmain. They map to the canvas textures in order.

Compute-only
- `layout(local_size_x = 8, local_size_y = 8) in;` (you declare it)
- `GlobalThreadID LocalThreadID LocalThreadIndex WorkgroupID WorkgroupSize WorkgroupCount SubgroupCount`

Material (from `Pass:setMaterial`; a Texture passed there becomes ColorTexture)
- `Material.color glow(vec4, a=strength) uvShift uvScale sdfRange metalness roughness clearcoat clearcoatRoughness occlusionStrength normalScale alphaCutoff`
- Textures: `ColorTexture GlowTexture MetalnessTexture(b) RoughnessTexture(g) ClearcoatTexture(r) OcclusionTexture(r) NormalTexture`. Defaults are 1x1 white (normal map: flat).

Helper functions
- Sampling with the pass sampler: `getPixel(texture2D, vec2)`, `(texture3D, vec3)`, `(textureCube, vec3)`, `(texture2DArray, vec2, float layer)`, `(textureCubeArray, vec4)`. The same overloads accept a combined `sampler2D(...)` etc. for a custom `uniform sampler`.
- Raw: `texture(sampler2D(tex, Sampler), uv)`; `texelFetch(tex, ivec2, lod)` needs `#extension GL_EXT_samplerless_texture_functions : require`.
- PBR: `struct Surface`, `getDefaultSurface()`, `newSurface()`, `applyMaterial(inout s)`, `finalizeSurface(inout s)`, `getLighting(s, vec3 lightDir, vec4 color, float visibility)`, `getIndirectLighting(s, textureCube env, vec3 sh[9])`, `D_GGX`, `G_SmithGGXCorrelated`, `F_Schlick`, `prefilteredBRDF`, `evaluateSphericalHarmonics`
- Color: `tonemap` (ACES), `gammaToLinear`, `linearToGamma`, `pqToLinear`, `linearToPQ`, `sRGBToRec2020`, `rec2020ToSRGB`
- Packing: `packSnorm10x3(vec4)`, `unpackSnorm10x3(uint)`
- Matrix: `cofactor3(mat4x3)` (vertex)

Resource declarations (all bound with `pass:send(name, ...)`)
- `uniform float/vec*/mat*/arrays`: loose uniforms. Send a number, a table, or a vector/matrix object. Arrays and structs are sent as tables (unverified here).
- `uniform Block { ... };` uniform buffer · `buffer Block { ... };` storage buffer (writable in compute). Add `layout(scalar)` to drop std140/std430 padding rules.
- `uniform texture2D|texture3D|textureCube|texture2DArray|textureCubeArray|texture2DMS name;` (needs a texture with usage 'sample')
- `layout(rgba8) uniform image2D name;` storage image (usage 'storage')
- `uniform sampler name;`
- `uniform raytracer name;` (= accelerationStructureEXT). Query it with `rayQueryEXT` / `rayQueryInitializeEXT(q, name, flags, 0xff, origin, tmin, dir, tmax)` / `rayQueryProceedEXT` / `rayQueryGetIntersectionTypeEXT`.
- Flags: `layout(constant_id = N) const bool|int|float flag_name = default;` with N < 1000. Override with `newShader(..., { flags = { name = v } })` or `shader:clone{...}` (the `flag_` prefix is stripped).

Built-in stage sources (for copying)
- `fill.vert`: fullscreen triangle from `VertexIndex`, `UV = ndc*.5+.5`, z=1. Projecting a view-space point with `Projection` gives `uv = clip.xy/clip.w*.5+.5`, which matches this UV.
- `unlit`: `DefaultPosition` / `DefaultColor` · `normal.frag`: `normalize(Normal)*.5+.5` · `cubemap`/`equirect`: skybox (use with `pass:skybox`) · `font.frag`: MSDF using `Material.sdfRange`

## 4. Recipes / gotchas (verified in this repo, src/projects/proj_3 = SSAO)

- Offscreen pipeline: create textures + `newPass({tex, depth='d32f', samples=1})` once (recreate on resize). Each frame: `p:reset()`, `p:setClear(...)`, copy the camera (`setViewPose`, `setProjection` from `windowPass:getProjection(1, mat4)`), record, then `lovr.graphics.submit(p1, p2, windowPass); return true`.
- G-buffer packing data in alpha: call `pass:setBlendMode()` (off) first. Default blending is alpha and will mangle the data.
- Use `rgba32f` when storing depth; 16f loses precision at distance. Read exact texels with `pass:setSampler('nearest')`.
- Sampling textures you render to needs `samples = 1` on that pass (or let MSAA resolve). A texture needs `usage = {'render','sample'}`.
- View-space normal: `mat3(View) * normalize(Normal)`; linear depth: `-(View * vec4(PositionWorld,1)).z`.
- Reconstruct the view position from UV + linear depth: `p = InverseProjection * vec4(uv*2-1, .5, 1); p.xyz /= p.w; pos = p.xyz * (depth / -p.z)`.
- `Pass:setClear` defaults to transparent black for new passes. Set it explicitly after `reset()`.
