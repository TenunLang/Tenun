const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "Versi rilis (mis. 0.0.18)") orelse "0.0.0-dev";
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "tenun",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", build_options);
    exe.linkLibC(); // Winsock send() lintas-thread untuk broadcast WebSocket
    if (target.result.os.tag == .windows) {
        exe.addWin32ResourceFile(.{ .file = b.path("app.rc") });
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Menjalankan CLI tenun");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addOptions("build_options", build_options);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Menjalankan seluruh unit test");
    test_step.dependOn(&run_unit_tests.step);
}
