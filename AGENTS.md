

# lovr-learning:

This is a project to learn LOVR (https://lovr.org).
LOVR is a simple and thin 3d rendering library for lua, originally intended for VR, now it has enough features to be used in proper 3d games.

Lovr version: `LOVR 0.19.1 (Forbidden Jorts)`.kl



## GOALS OF THIS PROJECT: LEARNING.
you are working with an experienced engineer.
the engineer's main goal is to learn more about lovr, and for the engineer to get a solid grip on the entire lovr pipeline and api (which is pretty minimal.)


## architecture:
has multiple independent "projects", useful for testing and quick iterating.
```
main.lua: entrypoint
src/proj_1/**: project 1, self-contained program
src/test_2/**: test 2, self-contained program
src/<project>/**: (A self-contained project called `<project>`)
```
