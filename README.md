# ztd
Zig Tower Defense

This was written to learn Zig and Data Oriented Design approach.

## Requirements

- Linux
- Following packages: `libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libcairo2-dev`

## Usage

Start: `./ztd`

Keys:

- PgUp/PgDn, Mouse Wheel - zoom
- B - build mode
- ESC - exit build mode, clear selection
- 1 - upgrade selected tower rate of fire
- q - quit

## Development

Zig 0.11

- `zig build`
- `zig build run`
- `zig build run -Drelease-fast=true`

## Code Organization

Underlying data structures:

- [src/sparse_set.zig](src/sparse_set.zig) - sparse set implementation
- [src/r_tree.zig](src/r_tree.zig) - R Tree
- [src/table.zig](src/table.zig) - fast table of records and table of bounds

Game engine:

- [src/sdl.zig](src/sdl.zig) - SDL interface code
- [src/engine.zig](src/engine.zig) - game engine

Game:

- [src/game.zig](src/game.zig) - game logic
- [src/resources.zig](src/resources.zig) - game resources
- [src/levels.zig](src/levels.zig) - game levels
- [src/main.zig](src/main.zig) - main entry poitn and game loop

