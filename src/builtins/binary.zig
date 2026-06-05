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
