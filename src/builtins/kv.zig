const std = @import("std");
const fs = @import("fs.zig");

var mutex = std.Thread.Mutex{};
const DB = "tenun_data.json";

fn loadRoot(a: std.mem.Allocator) std.json.Value {
    const data = fs.baca(a, DB) catch return .{ .object = std.json.ObjectMap.init(a) };
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, data, .{}) catch return .{ .object = std.json.ObjectMap.init(a) };
    if (parsed != .object) return .{ .object = std.json.ObjectMap.init(a) };
    return parsed;
}

fn save(a: std.mem.Allocator, root: std.json.Value) !void {
    var buf = std.ArrayList(u8).init(a);
    try std.json.stringify(root, .{}, buf.writer());
    try fs.tulis(DB, buf.items);
}

pub fn muat(a: std.mem.Allocator, key: []const u8) []const u8 {
    mutex.lock();
    defer mutex.unlock();
    const root = loadRoot(a);
    const v = root.object.get(key) orelse return "";
    return switch (v) {
        .string => |s| s,
        else => "",
    };
}

pub fn simpan(a: std.mem.Allocator, key: []const u8, val: []const u8) !void {
    mutex.lock();
    defer mutex.unlock();
    var root = loadRoot(a);
    try root.object.put(try a.dupe(u8, key), .{ .string = try a.dupe(u8, val) });
    try save(a, root);
}

pub fn hapus(a: std.mem.Allocator, key: []const u8) !void {
    mutex.lock();
    defer mutex.unlock();
    var root = loadRoot(a);
    _ = root.object.swapRemove(key);
    try save(a, root);
}
