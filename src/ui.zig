const engine = @import("engine.zig");
const resources = @import("resources.zig");
const game = @import("game.zig");
const data = @import("data.zig");
const std = @import("std");
const gl = @import("gl.zig");
const imgui = @import("imgui.zig");

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
    key: c_int,
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

    pub fn onEvent(self: *@This(), e: *const gl.Event) !void {
        switch (e.*) {
            .keyPress => |keyPress| {
                for (self.menu.items) |*item| {
                    if (item.key == keyPress.key) {
                        try self.onAction(item.action);
                        return;
                    }
                }
            },
            .mouseButton => {
                switch (self.mode) {
                    // todo: go through onAction
                    Mode.BUILD => {
                        if (self.game.money >= self.game.towerPrice and (try self.findTower(self.engine.mousePos) == null)) {
                            const towerSheet = self.game.resources.getSheet(self.towerPrototype.sheet);
                            const pos = self.engine.mousePos.grid(Vec.init(towerSheet.desc.spriteWidth, towerSheet.desc.spriteHeight));
                            try self.game.addTower(pos, self.towerPrototype);
                            self.game.money -= self.game.towerPrice;
                            self.game.towerPrice = @floatToInt(usize, std.math.round(@intToFloat(f32, self.game.towerPrice) * 1.1));
                        }
                    },
                    Mode.SELECT => {
                        self.selectedTower = try self.findTower(self.engine.mousePos);
                        self.menu.clearRetainingCapacity();

                        if (self.selectedTower != null) {
                            try self.menu.append(.{ .text = "Upgrade Damage", .key = gl.c.GLFW_KEY_1, .action = .{ .UPGRADE_TOWER = .{ .attribute = .DAMAGE } } });
                            try self.menu.append(.{ .text = "Upgrade Range", .key = gl.c.GLFW_KEY_2, .action = .{ .UPGRADE_TOWER = .{ .attribute = .RANGE } } });
                            try self.menu.append(.{ .text = "Upgrade Rate", .key = gl.c.GLFW_KEY_3, .action = .{ .UPGRADE_TOWER = .{ .attribute = .RATE } } });
                            try self.menu.append(.{ .text = "Cancel", .key = gl.c.GLFW_KEY_ESCAPE, .action = .CANCEL });
                        }
                        try self.menu.append(.{ .text = "Build", .key = gl.c.GLFW_KEY_B, .action = .BUILD_MODE });
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
                self.menu.clearRetainingCapacity();
                for (data.BuildTowers) |tower, i| {
                    try self.menu.append(.{
                        .text = tower.tower.name,
                        .key = gl.c.GLFW_KEY_1 + @intCast(i32, i),
                        .action = .{ .SET_TOWER_PROTOTYPE = tower },
                    });
                }
                try self.menu.append(.{ .text = "Cancel", .key = gl.c.GLFW_KEY_ESCAPE, .action = Action.CANCEL });
            },
            .CANCEL => {
                self.mode = Mode.SELECT;
                self.selectedTower = null;
                self.menu.clearRetainingCapacity();
                try self.menu.append(.{ .text = "Build", .key = gl.c.GLFW_KEY_B, .action = Action.BUILD_MODE });
            },
            .SET_TOWER_PROTOTYPE => |tower| {
                self.towerPrototype = tower;
            },
            .UPGRADE_TOWER => |upgrade| if (self.selectedTower) |towerEntry| {
                const tower = towerEntry.value;
                if (self.game.money >= tower.upgradeCost) {
                    self.game.money -= tower.upgradeCost;
                    tower.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, tower.upgradeCost) * 1.1));
                    const attacker = self.game.attackers.get(towerEntry.id);

                    switch (upgrade.attribute) {
                        .DAMAGE => attacker.*.damage = @round(attacker.*.damage * 1.2),
                        // todo: don't take money if at the limit
                        .RATE => attacker.*.attackDelayMs = @floatToInt(usize, std.math.max(25, @round(@intToFloat(f32, attacker.*.attackDelayMs) / 1.05))),
                        .RANGE => attacker.*.range = @round(std.math.min(attacker.*.range * 1.05, 200)),
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

    pub fn update(self: *@This(), _: std.mem.Allocator) !void {
        try self.updateSelection();
        try self.updateBuildShadow();
    }

    pub fn render(self: *@This(), frameAllocator: std.mem.Allocator) !void {
        var textArray = std.ArrayList(u8).init(frameAllocator);
        var writer = textArray.writer();
        try self.printStatus(writer);
        try writer.print("\n", .{});
        try self.printMenu(writer);
        try textArray.append(0);

        const text = textArray.items[0..(textArray.items.len - 1) :0];
        imgui.c.ImGui_Text(text);
    }


    fn printStatus(self: *@This(), writer: anytype) !void {
        try writer.print("monsters {}\n", .{self.game.monsters.size()});
        try writer.print("$ {}\n", .{self.game.money});
        switch (self.mode) {
            Mode.BUILD => {
                try writer.print("Tower Price: $ {}\n", .{self.game.towerPrice});
            },
            Mode.SELECT => {
                if (self.selectedTower) |tower| {
                    try writer.print("{s} Tower\n", .{tower.value.name});
                    const attacker = self.game.attackers.get(tower.id);
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
            if (item.key == gl.c.GLFW_KEY_ESCAPE) {
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
                    const pos = (self.engine.bounds.get(towerEntry.id)).center();
                    const attacker = self.game.attackers.get(towerEntry.id);
                    const range = attacker.range;
                    // const c = try sdl.drawCircle(self.engine.renderer, range, .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.5 }, .{ .stroke = .{ .w = 0.5 } });
                    // try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, @intToFloat(f32, c.w), @intToFloat(f32, c.h)));
                    // try self.engine.sprites.set(self.selId, .{ .texture = c.texture, .src = .{ .x = 0, .y = 0, .w = c.w, .h = c.h }, .angleRad = 0, .z = .UI });
                    _ = range;
                    _ = pos;
                    return;
                }
            }
        }

        self.selectedTower = null;
        self.engine.bounds.delete(self.selId);
        self.engine.sprites.delete(self.selId);
    }

    fn updateBuildShadow(self: *@This()) !void {
        if (self.mode == Mode.BUILD) {
            const towerPrototype = self.towerPrototype;
            const towerSheet = self.game.resources.getSheet(towerPrototype.sheet);
            const pos = self.engine.mousePos.grid(Vec.init(towerSheet.desc.spriteWidth, towerSheet.desc.spriteHeight));
            const sprite = towerSheet.sprite(towerPrototype.sprite.x, towerPrototype.sprite.y, 0, .UI);
            try self.engine.bounds.set(self.shadowId, Rect.initCentered(pos, Vec.init(towerSheet.desc.spriteWidth, towerSheet.desc.spriteHeight)));
            try self.engine.sprites.set(self.shadowId, sprite);
        } else {
            self.engine.bounds.delete(self.shadowId);
            self.engine.sprites.delete(self.shadowId);
        }
    }
};

pub const Statistics = struct {
    lastTicks: u64 = 0,

    pub fn render(self: *Statistics, ticks: u64, frameAllocator: std.mem.Allocator, g: *game.Game, updateDurationNs: u64, renderDurationNs: u64) !void {
        defer self.lastTicks = ticks;
        if (self.lastTicks == 0 or ticks == self.lastTicks) {
            return;
        }
        const text = try std.fmt.allocPrintZ(frameAllocator, "{d} fps\n{d:.0} ms/update\n{d:.0} ms/render\n{d} sprites\n{e:.1} monsters/sec", .{
            1000 / (ticks - self.lastTicks),
            @intToFloat(f64, updateDurationNs) / 1000000,
            @intToFloat(f64, renderDurationNs) / 1000000,
            g.engine.spriteRenderer.rects.items.len / 4,
            @intToFloat(f64, g.monsters.size()) * 1000000000 / @intToFloat(f64, updateDurationNs + renderDurationNs),
        });

        const viewport = imgui.c.ImGui_GetMainViewport();
        imgui.c.ImGui_SetNextWindowPosEx(.{ .x = viewport.*.Size.x, .y = viewport.*.Size.y}, imgui.c.ImGuiCond_Appearing, .{.x = 1, .y = 1});
        if (imgui.c.ImGui_Begin("Statistics", null, 0)) {
            imgui.c.ImGui_Text(text);
        }
        imgui.c.ImGui_End();
    }
};

