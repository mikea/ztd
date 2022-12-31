const std = @import("std");
const gl = @import("gl.zig");
const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

pub const Viewport = struct {
    window: *gl.c.GLFWwindow,
    // these define the viewport
    center: Vec,
    scale: f32,

    // these are calculated
    view: Rect = undefined,
    mat: [16]gl.c.GLfloat = undefined,

    pub fn init(window: *gl.c.GLFWwindow) Viewport {
        // initially 1000 wide, centered on origin
        var viewport = Viewport{ .window = window, .scale = 0.5, .center = .{ .x = 0, .y = 0 } };
        viewport.update();
        return viewport;
    }

    pub fn update(self: *Viewport) void {
        const size = gl.framebufferSize(self.window).scale(self.scale);

        const s = self.scale;
        const w = size.x;
        const h = size.y;
        const sw = s * w;
        const sh = s * h;
        const cx = self.center.x;
        const cy = self.center.y;

        self.view = .{
            .a = .{ .x = cx - sw / 2, .y = cy - sh / 2 },
            .b = .{ .x = cx + sw / 2, .y = cy + sh / 2 },
        };
        self.mat = [16]gl.c.GLfloat{
            2 / sw,       0,            0, 0,
            0,            2 / sh,       0, 0,
            0,            0,            1, 0,
            -2 * cx / sw, -2 * cy / sh, 0, 1,
        };
    }

    // screen coordinates origin is top-left
    pub fn screenToGame(self: *const Viewport, v: Vec) Vec {
        const size = gl.framebufferSize(self.window);
        const s = self.scale;
        return self.center.add(.{ .x = s * (v.x - size.x / 2), .y = s * (size.y / 2 - v.y) });
    }

    pub fn onEvent(self: *Viewport, event: *const gl.Event) void {
        const mouseZoom = 1.1;
        const kbdZoom = 1.7;
        const delta = self.view.size().scale(1.0 / 10.0);
        switch (event.*) {
            .keyPress => |keyPress| switch (keyPress.key) {
                gl.c.GLFW_KEY_UP => {
                    self.center = self.center.add(.{ .x = 0, .y = -delta.y });
                },
                gl.c.GLFW_KEY_DOWN => {
                    self.center = self.center.add(.{ .x = 0, .y = delta.y });
                },
                gl.c.GLFW_KEY_LEFT => {
                    self.center = self.center.add(.{ .x = -delta.x, .y = 0 });
                },
                gl.c.GLFW_KEY_RIGHT => {
                    self.center = self.center.add(.{ .x = delta.x, .y = 0 });
                },
                gl.c.GLFW_KEY_PAGE_UP => {
                    self.scale *= kbdZoom;
                },
                gl.c.GLFW_KEY_PAGE_DOWN => {
                    self.scale /= kbdZoom;
                },
                else => {},
            },
            .mouseWheel => |mouseWheel| {
                self.scale *= if (mouseWheel.dy > 0) mouseZoom else 1.0 / mouseZoom;
            },
            else => {},
        }
        self.update();
    }
};
