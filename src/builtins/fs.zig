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

pub fn daftar(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return &.{};
    defer dir.close();
    var list = std.ArrayList([]const u8).init(allocator);
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        list.append(allocator.dupe(u8, entry.name) catch continue) catch {};
    }
    return list.toOwnedSlice();
}

pub fn buatDir(path: []const u8) void {
    std.fs.cwd().makePath(path) catch {};
}

pub fn hapusBerkas(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

pub fn hapusDir(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch {};
}

pub fn ukuran(path: []const u8) i64 {
    const st = std.fs.cwd().statFile(path) catch return -1;
    return @intCast(st.size);
}

pub fn apakahDir(path: []const u8) bool {
    var d = std.fs.cwd().openDir(path, .{}) catch return false;
    d.close();
    return true;
}
