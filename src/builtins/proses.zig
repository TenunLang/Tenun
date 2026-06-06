const std = @import("std");
const builtin = @import("builtin");

// Jalankan perintah lewat shell, kembalikan stdout. ("" bila gagal)
pub fn jalankan(a: std.mem.Allocator, perintah: []const u8) ![]u8 {
    const argv: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "cmd", "/c", perintah }
    else
        &.{ "sh", "-c", perintah };
    const res = std.process.Child.run(.{
        .allocator = a,
        .argv = argv,
        .max_output_bytes = 16 * 1024 * 1024,
    }) catch return a.dupe(u8, "");
    a.free(res.stderr);
    return res.stdout;
}
