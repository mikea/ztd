const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const main = b.option([] const u8, "main", "path to main file") orelse "src/main.zig";

    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    b.installBinFile("README.md", "README.md");

    const exe = b.addExecutable("ztd", main);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC(); // for cimports

    const cflags = [_][]const u8{};
    exe.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    exe.addCSourceFile("lib/glad/glad.c", &cflags);
    exe.addCSourceFile("lib/cimgui/cimgui.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/imgui.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/imgui_tables.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/imgui_widgets.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/imgui_demo.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/imgui_draw.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/backends/imgui_impl_opengl3.cpp", &cflags);
    exe.addCSourceFile("lib/imgui-1.89.1/backends/imgui_impl_glfw.cpp", &cflags);
    exe.linkLibCpp();

    exe.addCSourceFile("lib/stb/stb.c", &cflags);
    exe.addIncludePath("lib/");
    exe.addIncludePath("lib/imgui-1.89.1/");

    if (target.os_tag == std.Target.Os.Tag.windows) {
        // Docker container paths
        exe.addIncludePath("/win/glfw/include");
        exe.addLibraryPath("/win/glfw/lib-vc2019");
        b.installBinFile("/win/glfw/lib-vc2019/glfw3.dll", "glfw3.dll");
        exe.linkSystemLibraryName("glfw3dll");

    } else if (target.os_tag == std.Target.Os.Tag.macos) {
        // Docker container paths
        exe.addIncludePath("/mac/includes");
        exe.addIncludePath("/mac/glfw/include");
    } else {
        exe.linkSystemLibraryName("glfw");
    }

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(main);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
