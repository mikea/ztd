const gl = @import("gl.zig");
const utils = @import("utils.zig");
const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdarg.h");
    @cInclude("cimgui/cimgui.h");
});

const Error = error{ NullPointer, GenericError };

fn checkNotNull(ptr: anytype) !utils.Required(@TypeOf(ptr)) {
    return ptr orelse Error.NullPointer;
}

pub fn checkBool(b: bool) !void {
    if (!b) {
        return Error.GenericError;
    }
}

extern fn ImGui_ImplOpenGL3_Init(glslVersion: [*c]const u8) bool;
extern fn ImGui_ImplGlfw_InitForOpenGL(window: *gl.c.GLFWwindow, installCallbacks: bool) bool;
extern fn ImGui_ImplOpenGL3_NewFrame() void;
extern fn ImGui_ImplGlfw_NewFrame() void;
extern fn ImGui_ImplOpenGL3_RenderDrawData(data: *c.ImDrawData) void;

const Impl = struct {
    context: *c.ImGuiContext,

    pub fn deinit(self: *Impl) void {
        c.ImGui_DestroyContext(self.context);
    }

    pub fn newFrame(_: *Impl) void {
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        c.ImGui_NewFrame();
    }

    pub fn render(_: *Impl) void {
        c.ImGui_Render();
        ImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());
    }
};

pub fn init(window: *gl.c.GLFWwindow) !Impl {
    const imguiCtx = try checkNotNull(c.ImGui_CreateContext(null));

    var io = c.ImGui_GetIO();
    io.*.FontGlobalScale = 2;
    io.*.IniFilename = null;

    const glslVersion = if (builtin.os.tag == .macos) "#version 150" else "#version 130";
    try checkBool(ImGui_ImplGlfw_InitForOpenGL(window, true));
    try checkBool(ImGui_ImplOpenGL3_Init(glslVersion));
    c.ImGui_StyleColorsDark(null);
    return .{ .context = imguiCtx };
}
