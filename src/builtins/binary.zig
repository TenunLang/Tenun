const std = @import("std");

pub fn keByte(a: std.mem.Allocator, nilai: i64, lebar_in: i64, besar: bool) ![]u8 {
    var lebar: usize = if (lebar_in < 1) 1 else @intCast(lebar_in);
    if (lebar > 8) lebar = 8;
    const buf = try a.alloc(u8, lebar);
    const v: u64 = @bitCast(nilai);
    var i: usize = 0;
    while (i < lebar) : (i += 1) {
        const shift: u6 = @intCast((if (besar) (lebar - 1 - i) else i) * 8);
        buf[i] = @truncate(v >> shift);
    }
    return buf;
}

// Baca float IEEE-754 little-endian (lebar 4 = single, 8 = double), format ke teks desimal.
pub fn bacaFloat(a: std.mem.Allocator, data: []const u8, offset_in: i64, lebar_in: i64) ![]u8 {
    if (offset_in < 0) return a.dupe(u8, "0");
    const offset: usize = @intCast(offset_in);
    const lebar: usize = if (lebar_in == 8) 8 else 4;
    if (offset + lebar > data.len) return a.dupe(u8, "0");
    var bits: u64 = 0;
    var i: usize = 0;
    while (i < lebar) : (i += 1) {
        bits |= @as(u64, data[offset + i]) << @intCast(i * 8);
    }
    const val: f64 = if (lebar == 8)
        @bitCast(bits)
    else blk: {
        const f32v: f32 = @bitCast(@as(u32, @truncate(bits)));
        break :blk @as(f64, f32v);
    };
    return std.fmt.allocPrint(a, "{d}", .{val});
}

pub fn bacaInt(data: []const u8, offset_in: i64, lebar_in: i64, besar: bool) i64 {
    if (offset_in < 0) return 0;
    const offset: usize = @intCast(offset_in);
    var lebar: usize = if (lebar_in < 1) 1 else @intCast(lebar_in);
    if (lebar > 8) lebar = 8;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < lebar and offset + i < data.len) : (i += 1) {
        const shift: u6 = @intCast((if (besar) (lebar - 1 - i) else i) * 8);
        v |= @as(u64, data[offset + i]) << shift;
    }
    return @bitCast(v);
}
