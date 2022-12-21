# ZTD

Zig Tower Defense

Status: Technological demo

## About

This game was created to learn Zig and Data Oriented Design approach.
The goal is to push performance boundaries of the number of
units present in the simulation.

Currently on `Intel(R) Core(TM) i7-7500U CPU @ 2.70GHz` the engine achieves
~25*10^6 units/sec of single-threaded performance.

## Runtime Requirements

- Linux with following packages: `libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libcairo2-dev`
- Win

## Usage

Start: `./ztd` or `./ztd <level>`.
Available levels: `level1`, `level2`, `level3`, `stress1`

Keys:

- PgUp/PgDn, Mouse Wheel - zoom
- B - build mode
- ESC - exit build mode, clear selection
- 1 - upgrade selected tower rate of fire
- q - quit

## Known Issues

- Render performance suffers when zoomed out a lot

## Development

Requirements:

- Zig 0.11 (I use [zigup](https://github.com/marler8997/zigup) to fetch master version)
- devel versions of packages

Commands:

- `zig build`
- `zig build run`
- `zig build run -Drelease-fast=true -- [<level>]`
- `zig build -Drelease-fast=true -Dtarget=x86_64-windows`

## Code Organization

Underlying data structures:

- [src/geom.zig](src/geom.zig) - 2d geometry primitives
- [src/sparse_set.zig](src/sparse_set.zig) - sparse set implementation
- [src/r_tree.zig](src/r_tree.zig) - R Tree
- [src/table.zig](src/table.zig) - fast table of records and table of bounds
- [src/rects.zig](src/rects.zig) - SIMD-friendly columnar []Rect

Game engine:

- [src/sdl.zig](src/sdl.zig) - SDL interface code
- [src/cairo.zig](src/cairo.zig) - Cairo interface code
- [src/engine.zig](src/engine.zig) - game engine

Game:

- [src/model.zig](src/model.zig) - model objects stored in table
- [src/game.zig](src/game.zig) - game logic
- [src/resources.zig](src/resources.zig) - game resources
- [src/levels.zig](src/levels.zig) - game levels
- [src/ui.zig](src/ui.zig) - game UI and user interaction
- [src/data.zig](src/data.zig) - units and buildings data (hp, damage, etc)
- [src/main.zig](src/main.zig) - main entry poitn and game loop
