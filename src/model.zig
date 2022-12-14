const resources = @import("resources.zig");
const sdl = @import("sdl.zig");
const table = @import("table.zig");
const Vec = @import("geom.zig").Vec;

pub const Id = u32;
pub const maxId: usize = 1 << 18;

// row types definitions

pub const Health = struct {
    maxHealth: f32,
    health: f32,
};
pub const HealthsTable = table.Table(Id, maxId, Health);

pub const Tower = struct {
    name: []const u8,
    upgradeCost: usize,
};
pub const TowersTable = table.Table(Id, maxId, Tower);

pub const Monster = struct {
    speed: f32,
    price: usize,
};
pub const MonstersTable = table.Table(Id, maxId, Monster);

pub const DamageType = union(enum) {
    direct: void,
    splash: struct {
        radius: f32,
    },
};

pub const AttackType = union(enum) {
    direct: void,
    splash: struct {
        radius: f32,
    },
    projectile: struct {
        speed: f32,
        sheet: resources.SpriteSheets,
        navigation: enum { POS, FOLLOW },
        damageType: DamageType,
    },
};

pub const Attacker = struct {
    range: f32,
    damage: f32,
    attackType: AttackType,
    attackDelayMs: u64,
    lastAttack: u64 = 0,
    target: Id = 0, // pointer to Health record
};
pub const AttackersTable = table.Table(Id, maxId, Attacker);

pub const SpriteCoords = struct { x: u8, y: u8 };

pub const Animation = union(enum) {
    sprites: struct {
        sheet: *const sdl.SpriteSheet,
        coords: []const SpriteCoords,
        animationDelay: u32,
        z: Layer,
        i: usize = 0,
    },
    timed: struct {
        endTicks: usize,
        onComplete: enum { NOTHING, FREE_TEXTURE },
    },
};

pub const Navigation = union(enum) {
    pos: Vec,
    target: Id,
};

pub const Projectile = struct {
    v: f32,
    damage: f32,
    damageType: DamageType,
    navigation: Navigation,
};
pub const ProjectilesTable = table.Table(Id, maxId, Projectile);

pub const Layer = enum {
    SPLASH_DAMAGE,
    MONSTER,
    TOWER,
    DAMAGE,
    PROJECTILE,
    UI,
};

pub const Sprite = struct {
    texture: *sdl.c.SDL_Texture,
    src: sdl.c.SDL_Rect,
    angle: f64,
    z: Layer,
};

pub const Particle = struct {
    v: Vec,
    startTicks: usize,
    endTicks: usize,
};
pub const ParticlesTable = table.Table(Id, maxId, Particle);
