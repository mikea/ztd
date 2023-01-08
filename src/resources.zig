const std = @import("std");
const gl = @import("gl.zig");
const sprites = @import("sprites.zig");
const truetype = @import("truetype.zig");

pub const SpriteSheets = enum {
    ARCHER_GOBLIN,
    ORC,
    RED_DEMON,
    WOOD_KEEP,
    WOOD_TOWER,
    WOOD_TOWER2,

    // projectiles
    FIREBALL_PROJECTILE,
    SHORT_ARROW,
    LONG_ARROW,

    // particles
    FLAME_PARTICLE,
};

pub const Resources = struct {
    const sheetSize = @typeInfo(SpriteSheets).Enum.fields.len;

    atlas: sprites.Atlas,
    rubik: truetype.FontInfo,

    pub fn init(allocator: std.mem.Allocator) !Resources {
        var files: [sheetSize]sprites.SpriteFile = undefined;
        for (files) |_, i| {
            files[i] = spriteFile(@intToEnum(SpriteSheets, i));
        }
        
        return .{
            .atlas = try sprites.loadAtlas(allocator, &files),
            .rubik = try truetype.FontInfo.init(@embedFile("res/RubikMonoOne-Regular.ttf")),
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.atlas.deinit(allocator);
    }

    pub fn getSheet(self: *@This(), sheet: SpriteSheets) *const sprites.SpriteSheet {
        return &self.atlas.sheets[@enumToInt(sheet)];
    }
};

const pi2 = (std.math.pi / 2.0);

pub fn spriteFile(sheet: SpriteSheets) sprites.SpriteFile {
    return switch (sheet) {
        SpriteSheets.ARCHER_GOBLIN => return .{
            .content = @embedFile("res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = 0 },
        },
        SpriteSheets.ORC => return .{
            .content = @embedFile("res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = 0 },
        },
        SpriteSheets.RED_DEMON => return .{
            .content = @embedFile("res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = 0 },
        },
        SpriteSheets.WOOD_KEEP => return .{
            .content = @embedFile("res/MiniWorldSprites/Buildings/Wood/Keep.png"),
            .desc = .{ .spriteWidth = 32, .spriteHeight = 32, .angle = 0 },
        },
        SpriteSheets.WOOD_TOWER => return .{
            .content = @embedFile("res/MiniWorldSprites/Buildings/Wood/Tower.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = 0 },
        },
        SpriteSheets.WOOD_TOWER2 => return .{
            .content = @embedFile("res/MiniWorldSprites/Buildings/Wood/Tower2.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = 0 },
        },
        SpriteSheets.FIREBALL_PROJECTILE => return .{
            .content = @embedFile("res/MiniWorldSprites/Objects/FireballProjectile.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = pi2 },
        },
        SpriteSheets.SHORT_ARROW => return .{
            .content = @embedFile("res/MiniWorldSprites/Objects/ArrowShort.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = pi2 },
        },
        SpriteSheets.LONG_ARROW => return .{
            .content = @embedFile("res/MiniWorldSprites/Objects/ArrowLong.png"),
            .desc = .{ .spriteWidth = 16, .spriteHeight = 16, .angle = pi2 },
        },
        SpriteSheets.FLAME_PARTICLE => return .{
            .content = @embedFile("res/particles/flame_06.png"),
            .desc = .{ .spriteWidth = 13, .spriteHeight = 15, .angle = 0 },
        },
    };
}
