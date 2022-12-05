const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ztd", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    if (target.os_tag == std.Target.Os.Tag.windows) {
        exe.linkLibC();

        const sdl_path = "/home/mike/Packages/SDL2-2.26.1/";
        exe.addIncludePath(sdl_path ++ "include");
        // exe.linkSystemLibrary("SDL2");

        const sdl_ttf_path = "/home/mike/Packages/SDL2_ttf-2.20.1/";
        exe.addIncludePath(sdl_ttf_path ++ "include");
        // exe.linkSystemLibrary("SDL2_ttf");

        const sdl_image_path = "/home/mike/Packages/SDL2_image-2.6.2/";
        exe.addIncludePath(sdl_image_path ++ "include");
        // // exe.addLibraryPath(sdl_image_path ++ "lib/x64/");
        // exe.linkSystemLibrary("SDL2_image");

        const cairo_path = "/home/mike/Packages/cairo-windows-1.17.2/";
        exe.addIncludePath(cairo_path ++ "include");
    }
    else {
        exe.linkLibC();

        exe.addIncludePath("/usr/include/SDL2/");
        exe.addIncludePath("/usr/include/cairo/");
        exe.addIncludePath("/usr/include/x86_64-linux-gnu");

        // setup sdl2
        exe.linkSystemLibrary("sdl2");
        exe.linkSystemLibrary("sdl2_ttf");
        exe.linkSystemLibrary("sdl2_image");
        
        // cairo for drawing
        exe.linkSystemLibrary("cairo");
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

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
