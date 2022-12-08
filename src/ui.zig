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

const ActionType = enum {
    BUILD_MODE,
    CANCEL,
    SET_TOWER_PROTOTYPE,
    UPGRADE_RATE,
    UPGRADE_DAMAGE,
    UPGRADE_RANGE,
};

const Action = union(ActionType) {
    BUILD_MODE: void,
    CANCEL: void,
    SET_TOWER_PROTOTYPE: *const data.TowerData,
    UPGRADE_RATE: void,
    UPGRADE_DAMAGE: void,
    UPGRADE_RANGE: void,
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

    selectedTowerId: ?Id = null,
    selectedTower: ?*model.TowersTable.Entry = null,
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

                        try self.menu.append(.{ .text = "Upgrade Damage", .key = sdl.c.SDLK_1, .action = Action.UPGRADE_DAMAGE });
                        try self.menu.append(.{ .text = "Upgrade Range", .key = sdl.c.SDLK_2, .action = Action.UPGRADE_RANGE });
                        try self.menu.append(.{ .text = "Upgrade Rate", .key = sdl.c.SDLK_3, .action = Action.UPGRADE_RATE });

                        try self.menu.append(.{ .text = "Cancel", .key = sdl.c.SDLK_ESCAPE, .action = Action.CANCEL });
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
            .UPGRADE_DAMAGE => if (self.selectedTower) |tower| {
                if (self.game.money >= tower.value.upgradeCost) {
                    self.game.money -= tower.value.upgradeCost;
                    tower.value.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, tower.value.upgradeCost) * 1.1));
                    const attacker = try self.game.attackers.get(tower.id);
                    attacker.*.damage = @round(attacker.*.damage * 1.2);
                }
            },
            .UPGRADE_RATE => if (self.selectedTower) |tower| {
                if (self.game.money >= tower.value.upgradeCost) {
                    self.game.money -= tower.value.upgradeCost;
                    tower.value.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, tower.value.upgradeCost) * 1.1));
                    const attacker = try self.game.attackers.get(tower.id);
                    attacker.*.attackDelayMs = @floatToInt(usize, @round(@intToFloat(f32, attacker.*.attackDelayMs) / 1.2));
                }
            },
            .UPGRADE_RANGE => if (self.selectedTower) |tower| {
                if (self.game.money >= tower.value.upgradeCost) {
                    self.game.money -= tower.value.upgradeCost;
                    tower.value.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, tower.value.upgradeCost) * 1.1));
                    const attacker = try self.game.attackers.get(tower.id);
                    attacker.*.range = @round(attacker.*.range * 1.2);
                }
            },
        }
    }

    fn findTower(self: *@This(), pos: Vec) !?*model.TowersTable.Entry {
        var towerFinder: struct {
            towers: *model.TowersTable,
            tower: ?*model.TowersTable.Entry = null,

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

        var textArray = std.ArrayList(u8).init(frameAllocator);
        var writer = textArray.writer();
        try self.printStatus(writer);
        try writer.print("\n", .{});
        try self.printMenu(writer);
        try textArray.append(0);

        try self.engine.setText(self.textId, textArray.items[0..(textArray.items.len - 1) :0], .{ .x = 0, .y = 0 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        // update build shadow
        if (self.mode == Mode.BUILD) {
            try self.engine.bounds.set(self.shadowId, Rect.centered(self.engine.mousePos.grid(8, 8), .{ .x = 8, .y = 8 }));
            try self.engine.sprites.set(self.shadowId, self.resources.getSheet(self.towerPrototype.sheet).sprite(self.towerPrototype.sprite.x, self.towerPrototype.sprite.y, 0));
        } else {
            try self.engine.bounds.delete(self.shadowId);
            try self.engine.sprites.delete(self.shadowId);
        }
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
                    try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, range * 2, range * 2));
                    try self.engine.sprites.set(self.selId, try sdl.drawCircle(self.engine.renderer, range));
                    return;
                }
            }
        }

        self.selectedTower = null;
        try self.engine.bounds.delete(self.selId);
        try self.engine.sprites.delete(self.selId);
    }
};
