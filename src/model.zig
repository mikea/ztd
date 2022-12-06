pub const Id = u32;
pub const maxId: usize = 1 << 18;

// row types definitions

pub const Health = struct {
    maxHealth: f32,
    health: f32,
};

pub const Tower = struct {
    upgradeCost: usize,
};

pub const Monster = struct {
    speed: f32,
    price: usize,
};

pub const Attacker = struct {
    range: f32,
    attack: union(AttackType) {
        direct: struct {
            damage: f32,
        },
        projectile: struct {
            damage: f32,
            speed: f32,
        },
    },
    attackDelayMs: u64,
    lastAttack: u64 = 0,
    target: Id = 0, // pointer to Health record
};

pub const AttackType = enum { direct, projectile };

