const std = @import("std");

const main = "src/main_glfw.zig";

pub fn build(b: *std.build.Builder) void {
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

    if (target.os_tag == std.Target.Os.Tag.windows) {
        // these are docker paths
        const sdl_path = "/win/SDL2/";
        exe.addIncludePath(sdl_path ++ "include");
        exe.addLibraryPath(sdl_path ++ "lib/x64/");
        b.installBinFile(sdl_path ++ "lib/x64/SDL2.dll", "SDL2.dll");
        exe.linkSystemLibraryName("SDL2");

        const sdl_ttf_path = "/win/SDL2_ttf/";
        exe.addIncludePath(sdl_ttf_path ++ "include");
        exe.addLibraryPath(sdl_ttf_path ++ "lib/x64/");
        b.installBinFile(sdl_ttf_path ++ "lib/x64/SDL2_ttf.dll", "SDL2_ttf.dll");
        exe.linkSystemLibraryName("SDL2_ttf");

        const sdl_image_path = "/win/SDL2_image/";
        exe.addIncludePath(sdl_image_path ++ "include");
        exe.addLibraryPath(sdl_image_path ++ "lib/x64/");
        b.installBinFile(sdl_image_path ++ "lib/x64/SDL2_image.dll", "SDL2_image.dll");
        exe.linkSystemLibraryName("SDL2_image");

        const cairo_path = "/win/cairo/";
        exe.addIncludePath(cairo_path ++ "include");
        exe.addLibraryPath(cairo_path ++ "lib/x64/");
        b.installBinFile(cairo_path ++ "lib/x64/cairo.dll", "cairo.dll");
        exe.linkSystemLibraryName("cairo");
    } else if (target.os_tag == std.Target.Os.Tag.macos) {
        exe.addIncludePath("/mac/includes");
        exe.addIncludePath("/mac/includes/SDL2");
    } else {
        exe.addIncludePath("lib/");
        exe.addIncludePath("lib/imgui-1.89.1/");
        exe.linkSystemLibraryName("glfw");
    }

    {
        const options = b.addOptions();
        exe.addOptions("build_options", options);
        options.addOption([]const u8, "content_dir", "res/");
    }

    {
        // install content
        const installStep = b.addInstallDirectory(.{
            .source_dir = "res",
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/res",
        });
        exe.step.dependOn(&installStep.step);
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
