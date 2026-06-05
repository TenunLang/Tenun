const std = @import("std");

fn toHex(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const digits = "0123456789abcdef";
    var buf = try a.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        buf[i * 2] = digits[b >> 4];
        buf[i * 2 + 1] = digits[b & 0xf];
    }
    return buf;
}

pub fn sha256(a: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &out, .{});
    return toHex(a, &out);
}

pub fn sha1(a: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &out, .{});
    return toHex(a, &out);
}

pub fn md5(a: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(data, &out, .{});
    return toHex(a, &out);
}

pub fn hmacSha256(a: std.mem.Allocator, key: []const u8, data: []const u8) ![]u8 {
    var out: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&out, data, key);
    return toHex(a, &out);
}

pub fn base64Enkode(a: std.mem.Allocator, data: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const buf = try a.alloc(u8, enc.calcSize(data.len));
    _ = enc.encode(buf, data);
    return buf;
}

pub fn base64Dekode(a: std.mem.Allocator, data: []const u8) ![]u8 {
    const dec = std.base64.standard.Decoder;
    const n = dec.calcSizeForSlice(data) catch return error.InvalidBase64;
    const buf = try a.alloc(u8, n);
    dec.decode(buf, data) catch return error.InvalidBase64;
    return buf;
}

pub fn acak(a: std.mem.Allocator, n: usize) ![]u8 {
    const raw = try a.alloc(u8, n);
    std.crypto.random.bytes(raw);
    return toHex(a, raw);
}

pub fn sha1Raw(a: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(data, &out, .{});
    return a.dupe(u8, &out);
}

pub fn sha256Raw(a: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &out, .{});
    return a.dupe(u8, &out);
}

pub fn hmacSha256Raw(a: std.mem.Allocator, key: []const u8, data: []const u8) ![]u8 {
    var out: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&out, data, key);
    return a.dupe(u8, &out);
}

pub fn pbkdf2Sha256(a: std.mem.Allocator, password: []const u8, salt: []const u8, iter: i64) ![]u8 {
    var out: [32]u8 = undefined;
    const rounds: u32 = if (iter < 1) 1 else @intCast(iter);
    try std.crypto.pwhash.pbkdf2(&out, password, salt, rounds, std.crypto.auth.hmac.sha2.HmacSha256);
    return a.dupe(u8, &out);
}

pub fn xorBytes(a: std.mem.Allocator, x: []const u8, y: []const u8) ![]u8 {
    const n = @min(x.len, y.len);
    const buf = try a.alloc(u8, n);
    for (0..n) |i| buf[i] = x[i] ^ y[i];
    return buf;
}
