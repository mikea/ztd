const Vec = @import("geom.zig").Vec;
const model = @import("model.zig");
const resources = @import("resources.zig");

pub const TowerData = struct {
    size: Vec,
    tower: model.Tower,
    health: model.Health,
    attack: model.Attacker,

    sheet: resources.SpriteSheets,
    sprite: model.SpriteCoords,
};

pub const MonsterData = struct {
    size: Vec,
    monster: model.Monster,
    health: model.Health,
    attack: model.Attacker,
    animations: struct {
        walk: AnimationData,
    },
};

pub const AnimationData = struct {
    delay: u32,
    sheet: resources.SpriteSheets,
    sprites: []const model.SpriteCoords,
};

pub const RedMonster = MonsterData{
    .size = .{ .x = 10, .y = 10 },
    .monster = .{ .speed = 8, .price = 10 },
    .attack = .{ .range = 10, .attack = .{ .direct = .{ .damage = 5 } }, .attackDelayMs = 1000 },
    .health = .{ .maxHealth = 1000, .health = 1000 },
    .animations = .{
        .walk = .{ .delay = 250, .sheet = resources.SpriteSheets.RED_DEMON, .sprites = &[_]model.SpriteCoords{
            .{ .x = 2, .y = 0 },
            .{ .x = 3, .y = 0 },
            .{ .x = 4, .y = 0 },
            .{ .x = 3, .y = 0 },
        } },
    },
};

pub const Orc = MonsterData{
    .size = .{ .x = 8, .y = 8 },
    .monster = .{ .speed = 10, .price = 1 },
    .attack = .{ .range = 8, .attack = .{ .direct = .{ .damage = 2 } }, .attackDelayMs = 1000 },
    .health = .{ .maxHealth = 100, .health = 100 },
    .animations = .{
        .walk = .{ .delay = 150, .sheet = resources.SpriteSheets.ORC, .sprites = &[_]model.SpriteCoords{
            .{ .x = 2, .y = 0 },
            .{ .x = 3, .y = 0 },
            .{ .x = 4, .y = 0 },
            .{ .x = 3, .y = 0 },
        } },
    },
};

pub const ArcherGoblin = MonsterData{
    .size = .{ .x = 8, .y = 8 },
    .monster = .{ .speed = 12, .price = 1 },
    .attack = .{
        .range = 90,
        .attack = .{ .projectile = .{ .damage = 1, .speed = 100, .sheet = resources.SpriteSheets.SHORT_ARROW } },
        .attackDelayMs = 500,
    },
    .health = .{ .maxHealth = 50, .health = 50 },
    .animations = .{
        .walk = .{ .delay = 150, .sheet = resources.SpriteSheets.ARCHER_GOBLIN, .sprites = &[_]model.SpriteCoords{
            .{ .x = 2, .y = 0 },
            .{ .x = 3, .y = 0 },
            .{ .x = 4, .y = 0 },
            .{ .x = 3, .y = 0 },
        } },
    },
};

pub const MagicTower = TowerData{
    .size = .{ .x = 8, .y = 8 },
    .tower = .{ .upgradeCost = 10 },
    .attack = .{
        .range = 100,
        .attackDelayMs = 200,
        .attack = .{ .projectile = .{ .damage = 90, .speed = 400, .sheet = resources.SpriteSheets.FIREBALL_PROJECTILE } },
    },
    .health = .{ .maxHealth = 100, .health = 100 },
    .sheet = resources.SpriteSheets.WOOD_TOWER,
    .sprite = .{ .x = 0, .y = 0 },
};

pub const Keep = TowerData{
    .size = .{ .x = 16, .y = 16 },
    .tower = .{ .upgradeCost = 100 },
    .attack = .{
        .range = 200,
        .attackDelayMs = 200,
        .attack = .{ .projectile = .{ .damage = 200, .speed = 400, .sheet = resources.SpriteSheets.FIREBALL_PROJECTILE } },
    },
    .health = .{ .maxHealth = 1000, .health = 1000 },
    .sheet = resources.SpriteSheets.WOOD_KEEP,
    .sprite = .{ .x = 0, .y = 0 },
};
