

# lovr-learning:

This is a project to learn LOVR (https://lovr.org).
LOVR is a simple and thin 3d rendering library for lua, originally intended for VR, now it has enough features to be used in proper 3d games.

Lovr version: `LOVR 0.19.1 (Forbidden Jorts)`.



## LOVR source code:
Full lovr source (git repo, with submodules) is at `../LOVR_SOURCE` (`C:\_PROGRAMMING\LOVR\LOVR_SOURCE`).
If unsure how an API behaves, read the source there. Lua API bindings: `src/api/l_*.c`, core impl: `src/modules/**`.
NOTE: it tracks the `dev` branch, which may be newer than 0.19.1. Use `git -C ../LOVR_SOURCE show v0.19.1:<path>` for the exact released version.

## LOVR gotchas (since 0.19.0):
lovr.math.vec3 no longer pools vectors, and lovr.math.drain is deprecated.


## GOALS OF THIS PROJECT: LEARNING.
you are working with an experienced engineer.
the engineer's main goal is to learn more about lovr, and for the engineer to get a solid grip on the entire lovr pipeline and api (which is pretty minimal.)


## architecture:
has multiple independent "projects", useful for testing and quick iterating.
```
main.lua: entrypoint
src/projects/<n>_<name>/<n>_<name>.lua: project n, self-contained program (returns a table of callbacks)
  e.g. src/projects/1_phong/1_phong.lua. Number keys switch project (sorted by numeric prefix, key 0 = project 10). `PROJECT=n lovr .` starts in project n.
.workspace/**: A scratchpad workspace: put temporary scripts, screenshots, or logs here
```
