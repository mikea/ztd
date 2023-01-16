# ZTD

Zig Tower Defense

Status: Technological demo

## About

This game was written by me during fall 2022 holidays to learn Zig and Data Oriented Design approach.
It contains a highly optimized 2D sprite engine with custom OpenGL-based renderer.

To let the DOD shine, this project's goal was to push performance boundaries of the number of
units present in the simulation.
Currently on `Intel(R) Core(TM) i7-7500U CPU @ 2.70GHz` the engine achieves up to
10*10^6 units/sec of single-threaded performance.

## Runtime Requirements

- Linux with following packages: `libglfw3-dev`
- Windows 64

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

- linux, `libglfw3-dev` package
- Zig 0.11 (I use [zigup](https://github.com/marler8997/zigup) to fetch master version)

Commands:

- `zig build`
- `zig build run`
- `zig build run -Drelease-fast=true -- [<level>]`

## Docker multiplatform build

`./dev.sh dist` will build linux and win64 release .zip archives.

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

## License

- code in `src/` is licensed under GPL3.
- code in `lib/` is licensed under respective original licenses.
- [mini world sprites](https://opengameart.org/content/miniworld-sprites) are licensed under CC0
- [rubik font](https://fonts.google.com/specimen/Rubik/about) is licensed under Open Font License

## Screenshot

<img src="docs/Screenshot from 2023-01-16 10-16-28.png" width="400" />
