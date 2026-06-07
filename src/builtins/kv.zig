const std = @import("std");
const rt = @import("../rt.zig");
const fs = @import("fs.zig");

var mutex: std.Io.Mutex = .init;
const DB = "tenun_data.json";

fn loadRoot(a: std.mem.Allocator) std.json.Value {
    const data = fs.baca(a, DB) catch return .{ .object = std.json.ObjectMap.empty };
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, data, .{}) catch return .{ .object = std.json.ObjectMap.empty };
    if (parsed != .object) return .{ .object = std.json.ObjectMap.empty };
    return parsed;
}

fn save(a: std.mem.Allocator, root: std.json.Value) !void {
    var aw = std.Io.Writer.Allocating.init(a);
    defer aw.deinit();
    try std.json.Stringify.value(root, .{}, &aw.writer);
    try fs.tulis(DB, aw.written());
}

pub fn muat(a: std.mem.Allocator, key: []const u8) []const u8 {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    const root = loadRoot(a);
    const v = root.object.get(key) orelse return "";
    return switch (v) {
        .string => |s| s,
        else => "",
    };
}

pub fn simpan(a: std.mem.Allocator, key: []const u8, val: []const u8) !void {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    var root = loadRoot(a);
    try root.object.put(a, try a.dupe(u8, key), .{ .string = try a.dupe(u8, val) });
    try save(a, root);
}

pub fn hapus(a: std.mem.Allocator, key: []const u8) !void {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    var root = loadRoot(a);
    _ = root.object.swapRemove(key);
    try save(a, root);
}
