# starlight

My garden/playground for Julia and computer graphics.

## NOTES
~~- current bugs can be approached by trying to render simpler CSG scenes~~
- something similar can be done for OBJ loading and rendering

## BUGS
- [X] csg transforms and bounding boxes are completely broken
- [X] ring pattern not working on csg cylinder
- [ ] can't load Stanford bunny
- [ ] large OBJ renders are slow

## TODO
- [ ] look into refactoring shapes and patterns with macros or something
- [ ] refactor test suite so that test names correspond to ones from the book
- [X] reimagine and rewrite module to not be organized by chapters
- [ ] reimagine and rewrite test suite to not be organized by chapters
- [ ] programatically find good resolution for "final" render (based on fov?)
- [ ] modularize (i.e. fir_branch probably shouldn't have it's own case in parse_entity along with geometric primitives)
- [ ] torus primitive
- [ ] pyramid primitive
- [ ] curves
- [ ] 2D drawing
- [ ] text drawing
- [ ] fonts
- [ ] anti-aliasing/supersampling
- [ ] multiprocess the raytrace function by canvas regions
- [ ] see about parallelizing divide!
- [ ] quaternions and animation
- [ ] OBJ texture coordinates
- [ ] MTL parsing
- [ ] full OBJ spec
- [ ] full MTL spec
- [ ] YAML scenes referencing other scenes
- [ ] OBJ export
- [ ] MTL export
- [ ] YAML export
- [ ] rasterization
- [ ] real-time stuff
- [ ] more sophisticated lighting model
