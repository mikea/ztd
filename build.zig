const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ztd", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    {
        // setup sdl2
        exe.addIncludePath("/usr/include");
        exe.addIncludePath("/usr/include/x86_64-linux-gnu");
        exe.linkSystemLibrary("sdl2");
        exe.linkSystemLibrary("sdl2_ttf");
        exe.linkLibC();
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
