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

const Action = union(enum) {
    BUILD_MODE: void,
    CANCEL: void,
    SET_TOWER_PROTOTYPE: *const data.TowerData,
    UPGRADE_TOWER: struct { attribute: enum { RANGE, DAMAGE, RATE } },
};

const MenuItem = struct {
    text: []const u8,
    key: sdl.c.SDL_Keycode,
    action: Action,
};

pub const UI = struct {
    engine: *engine.Engine,
    resources: *resources.Resources,
    game: *game.Game,

    menu: std.ArrayList(MenuItem),

    mode: Mode = Mode.SELECT,
    textId: Id,
    shadowId: Id,
    selId: Id,

    selectedTower: ?model.TowersTable.Entry = null,
    towerPrototype: *const data.TowerData,

    pub fn init(allocator: std.mem.Allocator, g: *game.Game) !@This() {
        var result: @This() = .{
            .game = g,
            .engine = g.engine,
            .resources = g.resources,
            .textId = g.engine.ids.nextId(),
            .shadowId = g.engine.ids.nextId(),
            .selId = g.engine.ids.nextId(),
            .menu = std.ArrayList(MenuItem).init(allocator),
            .towerPrototype = data.BuildTowers[0],
        };
        try result.onAction(Action.CANCEL);
        return result;
    }

    pub fn deinit(self: *@This()) void {
        self.menu.deinit();
    }

    pub fn event(self: *@This(), e: *const sdl.Event) !void {
        switch (e.type) {
            sdl.c.SDL_KEYDOWN => {
                for (self.menu.items) |*item| {
                    if (item.key == e.key.keysym.sym) {
                        try self.onAction(item.action);
                    }
                }
            },
            sdl.c.SDL_MOUSEBUTTONDOWN => {
                const pos = self.engine.mousePos.grid(8, 8);

                switch (self.mode) {
                    Mode.BUILD => if (self.game.money >= self.game.towerPrice and (try self.findTower(pos) == null)) {
                        try self.game.addTower(pos, self.towerPrototype);
                        self.game.money -= self.game.towerPrice;
                        self.game.towerPrice = @floatToInt(usize, std.math.round(@intToFloat(f32, self.game.towerPrice) * 1.1));
                    },
                    Mode.SELECT => {
                        self.selectedTower = try self.findTower(pos);
                        self.menu.clearAndFree();

                        try self.menu.append(.{ .text = "Upgrade Damage", .key = sdl.c.SDLK_1, .action = .{ .UPGRADE_TOWER = .{ .attribute = .DAMAGE } } });
                        try self.menu.append(.{ .text = "Upgrade Range", .key = sdl.c.SDLK_2, .action = .{ .UPGRADE_TOWER = .{ .attribute = .RANGE } } });
                        try self.menu.append(.{ .text = "Upgrade Rate", .key = sdl.c.SDLK_3, .action = .{ .UPGRADE_TOWER = .{ .attribute = .RATE } } });

                        try self.menu.append(.{ .text = "Cancel", .key = sdl.c.SDLK_ESCAPE, .action = .CANCEL });
                    },
                }
            },
            else => {},
        }
    }

    fn onAction(self: *@This(), action: Action) !void {
        switch (action) {
            .BUILD_MODE => {
                self.mode = Mode.BUILD;
                self.towerPrototype = data.BuildTowers[0];
                self.menu.clearAndFree();
                for (data.BuildTowers) |tower, i| {
                    try self.menu.append(.{
                        .text = tower.tower.name,
                        .key = sdl.c.SDLK_1 + @intCast(i32, i),
                        .action = .{ .SET_TOWER_PROTOTYPE = tower },
                    });
                }
                try self.menu.append(.{ .text = "Cancel", .key = sdl.c.SDLK_ESCAPE, .action = Action.CANCEL });
            },
            .CANCEL => {
                self.mode = Mode.SELECT;
                self.selectedTower = null;
                self.menu.clearAndFree();
                try self.menu.append(.{ .text = "Build", .key = sdl.c.SDLK_b, .action = Action.BUILD_MODE });
            },
            .SET_TOWER_PROTOTYPE => |tower| {
                self.towerPrototype = tower;
            },
            // todo: clean up upgrades
            .UPGRADE_TOWER => |upgrade| if (self.selectedTower) |towerEntry| {
                const tower = towerEntry.value;
                if (self.game.money >= tower.upgradeCost) {
                    self.game.money -= tower.upgradeCost;
                    tower.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, tower.upgradeCost) * 1.1));
                    const attacker = try self.game.attackers.get(towerEntry.id);

                    switch (upgrade.attribute) {
                        .DAMAGE => attacker.*.damage = @round(attacker.*.damage * 1.2),
                        .RATE => attacker.*.attackDelayMs = @floatToInt(usize, @round(@intToFloat(f32, attacker.*.attackDelayMs) / 1.2)),

                        .RANGE => attacker.*.range = @round(attacker.*.range * 1.2),
                    }
                }
            },
        }
    }

    fn findTower(self: *@This(), pos: Vec) !?model.TowersTable.Entry {
        var towerFinder: struct {
            towers: *model.TowersTable,
            tower: ?model.TowersTable.Entry = null,

            pub fn callback(s: *@This(), id: Id, _: Rect) error{OutOfMemory}!void {
                if (s.towers.findEntry(id)) |entry| {
                    s.tower = entry;
                }
            }
        } = .{
            .towers = &self.game.towers,
        };

        try self.engine.bounds.findPoint(pos, @TypeOf(towerFinder), &towerFinder, @TypeOf(towerFinder).callback);
        return towerFinder.tower;
    }

    pub fn update(self: *@This(), frameAllocator: std.mem.Allocator) !void {
        try self.updateSelection();
        try self.updateBuildShadow();
        try self.updateText(frameAllocator);
    }

    pub fn updateText(self: *@This(), frameAllocator: std.mem.Allocator) !void {
        var textArray = std.ArrayList(u8).init(frameAllocator);
        var writer = textArray.writer();
        try self.printStatus(writer);
        try writer.print("\n", .{});
        try self.printMenu(writer);
        try textArray.append(0);

        try self.engine.setText(self.textId, textArray.items[0..(textArray.items.len - 1) :0], .{ .x = 0, .y = 0 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);
    }

    fn printStatus(self: *@This(), writer: anytype) !void {
        try writer.print("$ {}\n", .{self.game.money});
        switch (self.mode) {
            Mode.BUILD => {
                try writer.print("Tower Price: $ {}\n", .{self.game.towerPrice});
            },
            Mode.SELECT => {
                if (self.selectedTower) |tower| {
                    try writer.print("{s} Tower\n", .{tower.value.name});
                    const attacker = try self.game.attackers.get(tower.id);
                    try writer.print("{} Damage\n", .{@floatToInt(usize, attacker.damage)});
                    try writer.print("{} Cooldown\n", .{attacker.attackDelayMs});
                    try writer.print("{} Range\n", .{@floatToInt(usize, attacker.range)});
                    try writer.print("Upgrade Price: $ {}\n", .{tower.value.upgradeCost});
                }
            },
        }
    }

    fn printMenu(self: *@This(), writer: anytype) !void {
        for (self.menu.items) |*item| {
            if (item.key == sdl.c.SDLK_ESCAPE) {
                try writer.writeAll("ESC");
            } else {
                try writer.writeAll(&[_]u8{@intCast(u8, item.key)});
            }
            try writer.print(" - {s}\n", .{item.text});
        }
    }

    fn updateSelection(self: *@This()) !void {
        if (self.mode == Mode.SELECT) {
            if (self.selectedTower) |selTower| {
                if (self.game.towers.findEntry(selTower.id)) |towerEntry| {
                    self.selectedTower = towerEntry;
                    const pos = (try self.engine.bounds.get(towerEntry.id)).center();
                    const attacker = try self.game.attackers.get(towerEntry.id);
                    const range = attacker.range;
                    const c = try sdl.drawCircle(self.engine.renderer, range, .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.5 }, .{ .stroke = .{ .w = 0.5 } });
                    try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, @intToFloat(f32, c.w), @intToFloat(f32, c.h)));
                    try self.engine.sprites.set(self.selId, .{ .texture = c.texture, .src = .{ .x = 0, .y = 0, .w = c.w, .h = c.h }, .angle = 0, .z = .UI });
                    return;
                }
            }
        }

        self.selectedTower = null;
        try self.engine.bounds.delete(self.selId);
        try self.engine.sprites.delete(self.selId);
    }

    fn updateBuildShadow(self: *@This()) !void {
        if (self.mode == Mode.BUILD) {
            try self.engine.bounds.set(self.shadowId, Rect.centered(self.engine.mousePos.grid(8, 8), .{ .x = 8, .y = 8 }));
            const sprite = self.resources.getSheet(self.towerPrototype.sheet).sprite(self.towerPrototype.sprite.x, self.towerPrototype.sprite.y, 0, .UI);
            try self.engine.sprites.set(self.shadowId, sprite);
        } else {
            try self.engine.bounds.delete(self.shadowId);
            try self.engine.sprites.delete(self.shadowId);
        }
    }
};
