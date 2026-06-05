const std = @import("std");

fn field(a: std.mem.Allocator, src: []const u8, key: []const u8) ?std.json.Value {
    const root = std.json.parseFromSliceLeaky(std.json.Value, a, src, .{}) catch return null;
    if (root != .object) return null;
    return root.object.get(key);
}

pub fn teks(a: std.mem.Allocator, src: []const u8, key: []const u8) []const u8 {
    const v = field(a, src, key) orelse return "";
    return switch (v) {
        .string => |s| s,
        else => "",
    };
}

pub fn angka(a: std.mem.Allocator, src: []const u8, key: []const u8) i64 {
    const v = field(a, src, key) orelse return 0;
    return switch (v) {
        .integer => |n| n,
        .float => |f| @intFromFloat(f),
        .string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
        else => 0,
    };
}

pub fn boolean(a: std.mem.Allocator, src: []const u8, key: []const u8) bool {
    const v = field(a, src, key) orelse return false;
    return switch (v) {
        .bool => |b| b,
        else => false,
    };
}
