const std = @import("std");
const rt = @import("../rt.zig");

pub fn baca(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(rt.io, path, allocator, std.Io.Limit.limited(64 * 1024 * 1024));
}

pub fn tulis(path: []const u8, isi: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(rt.io, .{ .sub_path = path, .data = isi });
}

pub fn ada(path: []const u8) bool {
    std.Io.Dir.cwd().access(rt.io, path, .{}) catch return false;
    return true;
}

pub fn daftar(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var dir = std.Io.Dir.cwd().openDir(rt.io, path, .{ .iterate = true }) catch return &.{};
    defer dir.close(rt.io);
    var list = std.array_list.Managed([]const u8).init(allocator);
    var it = dir.iterate();
    while (it.next(rt.io) catch null) |entry| {
        list.append(allocator.dupe(u8, entry.name) catch continue) catch {};
    }
    return list.toOwnedSlice();
}

pub fn buatDir(path: []const u8) void {
    std.Io.Dir.cwd().createDirPath(rt.io, path) catch {};
}

pub fn hapusBerkas(path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(rt.io, path) catch {};
}

pub fn hapusDir(path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(rt.io, path) catch {};
}

pub fn ukuran(path: []const u8) i64 {
    const st = std.Io.Dir.cwd().statFile(rt.io, path, .{}) catch return -1;
    return @intCast(st.size);
}

pub fn apakahDir(path: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(rt.io, path, .{}) catch return false;
    d.close(rt.io);
    return true;
}
