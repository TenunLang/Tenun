const std = @import("std");

pub fn baca(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 64 * 1024 * 1024);
}

pub fn tulis(path: []const u8, isi: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(isi);
}

pub fn ada(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
