const std = @import("std");
const table = @import("table.zig");
const sprites = @import("sprites.zig");
const model = @import("model.zig");
const data = @import("data.zig");
const truetype = @import("truetype.zig");
const gl = @import("gl.zig");
const rendering = @import("rendering.zig");
const geom = @import("geom.zig");

const Id = model.Id;
const maxId = model.maxId;
const Vec = geom.Vec;
const Rect = geom.Rect;
const SparseSet = @import("sparse_set.zig").SparseSet;
const Viewport = @import("viewport.zig").Viewport;

pub const IdManager = struct {
    i: Id = 0,
    avail: SparseSet(Id, maxId, void),

    pub fn init(allocator: std.mem.Allocator) !IdManager {
        return .{ .avail = try SparseSet(Id, maxId, void).init(allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.avail.deinit();
    }

    pub fn nextId(self: *@This()) Id {
        if (self.i == maxId) {
            if (self.avail.size() == 0) {
                @panic("too many ids");
            }
            return self.avail.pop();
        }
        // no id 0!
        self.i += 1;
        return self.i;
    }

    pub fn free(self: *@This(), id: Id) !void {
        try self.avail.set(id, {});
    }
};

pub const Alignment = enum {
    LEFT,
    CENTER,
    RIGHT,
};

pub const Engine = struct {
    const BoundsTable = table.RTable(Id, maxId);
    const SpritesTable = table.Table(Id, maxId, model.Sprite);
    const AnimationsTable = table.Table(Id, maxId, model.Animation);

    allocator: std.mem.Allocator,
    window: *gl.c.GLFWwindow,
    atlas: *sprites.Atlas,

    viewport: Viewport,
    spriteRenderer: sprites.BatchSpriteRenderer,
    healthRenderer: rendering.HealthRenderer,
    geometryRenderer: rendering.GeometryRenderer,
    textRenderer: truetype.TextRenderer,

    // tables
    // will be deleted at the end of the update
    toDelete: SparseSet(Id, maxId, void),
    bounds: BoundsTable,
    sprites: SpritesTable,
    animations: AnimationsTable,
    healths: model.HealthTable,
    particles: model.ParticleTable,
    geometries: model.GeometryTable,
    texts: model.TextTable,

    ids: IdManager,
    running: bool = true,
    mousePos: Vec = .{ .x = 0, .y = 0 },

    pub fn init(allocator: std.mem.Allocator, window: *gl.c.GLFWwindow, atlas: *sprites.Atlas) !Engine {
        return .{
            .allocator = allocator,
            .window = window,
            .atlas = atlas,
            .ids = try IdManager.init(allocator),
            .viewport = Viewport.init(window),
            .spriteRenderer = try sprites.BatchSpriteRenderer.init(allocator),
            .healthRenderer = try rendering.HealthRenderer.init(),
            .geometryRenderer = try rendering.GeometryRenderer.init(),
            .textRenderer = try truetype.TextRenderer.init(),
            .toDelete = try SparseSet(Id, maxId, void).init(allocator),
            .bounds = try BoundsTable.init(allocator),
            .sprites = try SpritesTable.init(allocator),
            .animations = try AnimationsTable.init(allocator),
            .healths = try model.HealthTable.init(allocator),
            .particles = try model.ParticleTable.init(allocator),
            .geometries = try model.GeometryTable.init(allocator),
            .texts = try model.TextTable.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.sprites.deinit();
        self.animations.deinit();
        self.healths.deinit();
        self.particles.deinit();
        self.toDelete.deinit();
        self.ids.deinit();
        self.spriteRenderer.deinit();
        self.geometryRenderer.deinit();
        self.healthRenderer.deinit();
        self.geometries.deinit();
        self.texts.deinit();
    }

    pub fn delete(self: *Engine, id: Id) !void {
        self.bounds.delete(id);
        self.sprites.delete(id);
        self.animations.delete(id);
        self.healths.delete(id);
        self.particles.delete(id);
        self.geometries.delete(id);
        try self.ids.free(id);
        if (self.texts.getDelete(id)) |text| {
            self.allocator.free(text.str);
        }
    }

    pub fn addAnimation(self: *Engine, id: Id, rect: Rect, sheet: *const sprites.SpriteSheet, animation: *const data.AnimationData, z: model.Layer) !void {
        try self.bounds.set(id, rect);
        try self.animations.set(id, .{ .animationDelay = animation.delay, .i = id % animation.sprites.len, .sheet = sheet, .coords = animation.sprites, .z = z });
    }

    pub fn addSprite(self: *Engine, id: Id, rect: Rect, sprite: model.Sprite) !void {
        try self.bounds.set(id, rect);
        try self.sprites.set(id, sprite);
    }

    pub fn addText(self: *Engine, id: Id, pos: Vec, height: f32, text: model.Text) !void {
        const rect = Rect.initSized(pos, text.font.bounds(text.str, height));
        try self.bounds.set(id, rect);
        var strCopy = try self.allocator.alloc(u8, text.str.len);
        std.mem.copy(u8, strCopy, text.str);
        var copy = text;
        copy.str = strCopy;
        try self.texts.set(id, copy);
    }

    pub fn onEvent(self: *Engine, event: *const gl.Event) void {
        switch (event.*) {
            .mouseMove => |mouseMove| {
                self.mousePos = self.viewport.screenToGame(mouseMove.pos);
            },
            else => {},
        }
        self.viewport.onEvent(event);
    }

    pub fn update(self: *Engine, ticks: u64) !void {
        try self.updateAnimations(ticks);
    }
    
    pub fn updateAnimations(self: *Engine, ticks: u64) !void {
        if (self.viewport.view.height() > 5000) {
            // do not update animation when zoomed out too much
            return;
        }

        var updater: struct {
            engine: *Engine,
            ticks: usize,
            pub fn callback(s: *@This(), id: Id, _: Rect) error{OutOfMemory}!void {
                if (s.engine.animations.find(id)) |animation| {
                    const i = (s.ticks / animation.animationDelay + animation.i) % animation.coords.len;
                    const coords = animation.coords[i];
                    try s.engine.sprites.set(id, animation.sheet.sprite(coords.x, coords.y, 0, animation.z));
                }
            }
        } = .{ .engine = self, .ticks = ticks };

        try self.bounds.findIntersect(self.viewport.view, @TypeOf(updater), &updater, @TypeOf(updater).callback);
    }

    pub fn updateParticles(self: *Engine, ticks: u64, dt: f32) !void {
        var it = self.particles.iterator();
        while (it.next()) |entry| {
            const particle = entry.value;
            if (ticks >= particle.endTicks) {
                try self.toDelete.set(entry.id, {});
                switch (particle.onComplete) {
                    .DO_NOTHING => {},
                }
                continue;
            }
            const bound = self.bounds.get(entry.id);
            try self.bounds.update(entry.id, bound.translate(particle.v.scale(dt)));
        }
    }

    pub fn render(self: *Engine) !void {
        gl.c.glClearColor(1.0, 1.0, 1.0, 1.0);
        gl.c.glClear(gl.c.GL_COLOR_BUFFER_BIT | gl.c.GL_DEPTH_BUFFER_BIT);

        self.viewport.update();
        try self.renderSprites();
        try self.renderHealth();
        try self.renderGeometry();
        try self.renderText();
    }

    fn renderSprites(self: *Engine) !void {
        self.spriteRenderer.startFrame(&self.viewport);

        var visitor: struct {
            engine: *Engine,
            pub fn callback(s: *@This(), id: Id, rect: Rect) error{OutOfMemory}!void {
                if (s.engine.sprites.find(id)) |sprite| {
                    try s.engine.spriteRenderer.addSprite(id, sprite, &rect);
                }
            }
        } = .{ .engine = self };

        try self.bounds.findIntersect(self.viewport.view, @TypeOf(visitor), &visitor, @TypeOf(visitor).callback);
        try self.spriteRenderer.render(self.atlas);
    }

    fn renderHealth(self: *Engine) !void {
        self.healthRenderer.startFrame(&self.viewport);

        var renderer: struct {
            engine: *Engine,

            pub fn callback(s: *@This(), id: Id, rect: Rect) !void {
                if (s.engine.healths.find(id)) |health| {
                    if (health.*.health < health.*.maxHealth) {
                        // display health underneath the main sprite
                        const healthRatio = std.math.max(health.*.health, 0) / health.*.maxHealth;
                        const healthRect = Rect{
                            .a = .{ .x = rect.a.x, .y = rect.a.y - 1 },
                            .b = .{ .x = rect.b.x, .y = rect.a.y },
                        };
                        s.engine.healthRenderer.renderHealth(healthRect, healthRatio);
                    }
                }
            }
        } = .{ .engine = self };

        try self.bounds.findIntersect(self.viewport.view, @TypeOf(renderer), &renderer, @TypeOf(renderer).callback);
    }

    fn renderGeometry(self: *Engine) !void {
        self.geometryRenderer.startFrame(&self.viewport);

        var processor: struct {
            engine: *Engine,
            pub fn callback(s: *@This(), id: Id, rect: Rect) !void {
                if (s.engine.geometries.find(id)) |geometry| {
                    s.engine.geometryRenderer.render(rect, geometry);
                }
            }
        } = .{ .engine = self };

        try self.bounds.findIntersect(self.viewport.view, @TypeOf(processor), &processor, @TypeOf(processor).callback);
    }
    
    fn renderText(self: *Engine) !void {
        self.textRenderer.startFrame(&self.viewport);
        var it = self.texts.iterator();
        while (it.next()) |entry| {
            var text = entry.value;
            var rect = self.bounds.get(entry.id);
            self.textRenderer.render(rect, text);
            // self.geometryRenderer.render(rect, &.{ .shape = .rect, .layer = .UI, .color = [4]f32{0, 0, 0, 0.5} });
        }
    }
};
