const std = @import("std");
const sdl = @import("sdl.zig").sdl;
const table = @import("table.zig");
const geom = @import("geom.zig");

const Vec2 = geom.Vec2;
const Rect = geom.Rect;


pub const Id = u32;
pub const maxId: usize = 1 << 18;

const IdManager = struct {
    i: Id = 0,

    pub fn nextId(self: *@This()) Id {
        if (self.i == maxId) {
            std.log.err("too many ids allocated: max={}", .{maxId});
            @panic("too many ids");
        }
        const result = self.i;
        self.i += 1;
        return result;
    }
};

pub const Text = struct {
    str: [] const u8,
};

pub const Engine = struct {
    ids: IdManager = .{},
    bounds: table.Table(Id, maxId, Rect) = undefined,
    texts: table.Table(Id, maxId, Text) = undefined,

    pub fn init(self: *Engine, allocator: std.mem.Allocator, _: *sdl.SDL_Renderer) !void {
        self.bounds = try @TypeOf(self.bounds).init(allocator);
        self.texts = try @TypeOf(self.texts).init(allocator);
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.texts.deinit();
    }
};