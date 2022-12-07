const engine = @import("engine.zig");
const resources = @import("resources.zig");
const game = @import("game.zig");
const sdl = @import("sdl.zig");
const data = @import("data.zig");
const std = @import("std");

const model = @import("model.zig");
const Id = model.Id;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;


const Mode = enum {
    SELECT,
    BUILD,
};

pub const UI = struct {
    engine: *engine.Engine,
    resources: *resources.Resources,
    game: *game.Game,

    mode: Mode = Mode.SELECT,
    textId: Id,
    shadowId: Id,
    selId: Id,

    selectedTowerId: ?Id = null,

    pub fn init(g: *game.Game) !@This() {
        return .{
            .game = g,
            .engine = g.engine,
            .resources = g.resources,
            .textId = g.engine.ids.nextId(),
            .shadowId = g.engine.ids.nextId(),
            .selId = g.engine.ids.nextId(),
        };
    }

    pub fn event(self: *@This(), e: *const sdl.Event) !void {
        switch (e.type) {
            sdl.c.SDL_KEYDOWN => switch (e.key.keysym.sym) {
                sdl.c.SDLK_b => self.mode = Mode.BUILD,
                sdl.c.SDLK_ESCAPE => {
                    self.mode = Mode.SELECT;
                    self.selectedTowerId = null;
                },
                sdl.c.SDLK_1 => {
                    if (self.mode != Mode.SELECT) return;
                    if (self.selectedTowerId) |towerId| {
                        if (self.game.towers.find(towerId)) |tower| {
                            const upgradeCost = tower.*.upgradeCost;
                            if (self.game.money >= upgradeCost) {
                                self.game.money -= upgradeCost;
                                tower.*.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, upgradeCost) * 1.5));
                                const attacker = try self.game.attackers.get(towerId);
                                attacker.*.attackDelayMs = @floatToInt(usize, @round(@intToFloat(f32, attacker.*.attackDelayMs) / 1.2));
                            }
                        }
                    }
                },
                else => {},
            },
            sdl.c.SDL_MOUSEBUTTONDOWN => {
                switch (self.mode) {
                    Mode.BUILD => if (self.game.money >= data.MagicTower.tower.upgradeCost) {
                        try self.game.addTower(self.engine.mousePos.grid(8, 8), &data.MagicTower);
                        self.game.money -= 10;
                    },
                    Mode.SELECT => {
                        var towerFinder: struct {
                            towers: *game.TowersTable,
                            towerId: ?Id = null,

                            pub fn callback(s: *@This(), id: Id, _: Rect) error{OutOfMemory}!void {
                                if (s.towers.find(id) != null) {
                                    s.towerId = id;
                                }
                            }
                        } = .{
                            .towers = &self.game.towers,
                        };

                        try self.engine.bounds.findPoint(self.engine.mousePos, @TypeOf(towerFinder), &towerFinder, @TypeOf(towerFinder).callback);
                        self.selectedTowerId = towerFinder.towerId;
                    },
                }
            },
            else => {},
        }
    }

    pub fn update(self: *@This(), frameAllocator: std.mem.Allocator) !void {
        const selectedTower = try self.updateSelection();

        // update ui text
        const commonText = try std.fmt.allocPrintZ(frameAllocator, "mode: {}\n$ {}", .{ self.mode, self.game.money });

        const text = switch (self.mode) {
            Mode.BUILD => commonText,
            Mode.SELECT => if (selectedTower) |tower|
                try std.fmt.allocPrintZ(frameAllocator, "{s}\n1 - upgrade rate $ {}", .{ commonText, tower.upgradeCost })
            else
                commonText,
        };
        try self.engine.setText(self.textId, text, .{ .x = 0, .y = 0 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        // update build shadow
        if (self.mode == Mode.BUILD) {
            try self.engine.bounds.set(self.shadowId, Rect.centered(self.engine.mousePos.grid(8, 8), .{ .x = 8, .y = 8 }));
            // todo: store current template somewhere
            try self.engine.sprites.set(self.shadowId, (self.resources.getSheet(resources.SpriteSheets.WOOD_TOWER)).sprite(0, 0, 0));
        } else {
            try self.engine.bounds.delete(self.shadowId);
            try self.engine.sprites.delete(self.shadowId);
        }
    }

    fn updateSelection(self: *@This()) !?*model.Tower {
        if (self.mode == Mode.SELECT) {
            if (self.selectedTowerId) |towerId| {
                if (self.game.towers.find(towerId)) |tower| {
                    const pos = (try self.engine.bounds.get(towerId)).center();
                    const attacker = try self.game.attackers.get(towerId);
                    const range = attacker.range;
                    try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, range * 2, range * 2));
                    try self.engine.sprites.set(self.selId, try sdl.drawCircle(self.engine.renderer, range));
                    return tower;
                }
            }
        }

        self.selectedTowerId = null;
        try self.engine.bounds.delete(self.selId);
        try self.engine.sprites.delete(self.selId);
        return null;
    }
};
