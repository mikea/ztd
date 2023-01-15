# ZTD

Zig Tower Defense

Status: Technological demo

## About

This game was created to learn Zig and Data Oriented Design approach.
To let DOD shine, the goal was to push performance boundaries of the number of
units present in the simulation.

Currently on `Intel(R) Core(TM) i7-7500U CPU @ 2.70GHz` the engine achieves
~20*10^6 units/sec of single-threaded performance.



## Runtime Requirements

- Linux with following packages: `libglfw3-dev`
- Win

## Usage

Start: `./ztd` or `./ztd <level>`.
Available levels: `level1`, `level2`, `level3`, `stress1`

Keys:

- PgUp/PgDn, Mouse Wheel - zoom
- B - build mode
- ESC - exit build mode, clear selection
- q - quit

## Development

Requirements:

- Zig 0.11 (I use [zigup](https://github.com/marler8997/zigup) to fetch master version)
- devel versions of packages

Commands:

- `zig build`
- `zig build run`
- `zig build run -Drelease-fast=true -- [<level>]`
- `zig build -Drelease-fast=true -Dtarget=x86_64-windows`

## Docker multiplatform build

`./dev.sh dist`

## Code Organization

Underlying data structures:

- [src/geom.zig](src/geom.zig) - 2d geometry primitives
- [src/sparse_set.zig](src/sparse_set.zig) - sparse set implementation
- [src/denset_set.zig](src/denset_set.zig) - denset set implementation
- [src/r_tree.zig](src/r_tree.zig) - R Tree
- [src/table.zig](src/table.zig) - fast table of records and table of bounds
- [src/rects.zig](src/rects.zig) - SIMD-friendly columnar []Rect

Game engine:

- [src/gl.zig](src/gl.zig) - OpenGL interface code
- [src/imgui.zig](src/imgui.zig) - imgui interface code
- [src/shaders.zig](src/shaders.zig) - opengl shaders utilities
- [src/rendering.zig](src/rendering.zig) - different shader renderers
- [src/sprites.zig](src/sprites.zig) - sprite atlas building and rendering
- [src/viewport.zig](src/viewport.zig) - viewport calculations and update
- [src/engine.zig](src/engine.zig) - game engine
- [src/engine_testbed.zig](src/engine_testbed.zig) - simple testbed to debug the engine

Game:

- [src/model.zig](src/model.zig) - model objects stored in table
- [src/game.zig](src/game.zig) - game logic
- [src/resources.zig](src/resources.zig) - game resources
- [src/levels.zig](src/levels.zig) - game levels
- [src/ui.zig](src/ui.zig) - game UI and user interaction
- [src/data.zig](src/data.zig) - units and buildings data (hp, damage, etc)
- [src/main.zig](src/main.zig) - main entry poitn and game loop
