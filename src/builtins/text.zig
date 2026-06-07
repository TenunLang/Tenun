const std = @import("std");

pub fn potong(allocator: std.mem.Allocator, s: []const u8, mulai: i64, jumlah: i64) ![]u8 {
    var start: usize = if (mulai < 0) 0 else @intCast(mulai);
    if (start > s.len) start = s.len;
    var n: usize = if (jumlah < 0) 0 else @intCast(jumlah);
    if (start + n > s.len) n = s.len - start;
    return allocator.dupe(u8, s[start .. start + n]);
}

pub fn cari(s: []const u8, sub: []const u8) i64 {
    if (std.mem.indexOf(u8, s, sub)) |i| return @intCast(i);
    return -1;
}

pub fn ganti(allocator: std.mem.Allocator, s: []const u8, dari: []const u8, ke: []const u8) ![]u8 {
    if (dari.len == 0) return allocator.dupe(u8, s);
    return std.mem.replaceOwned(u8, allocator, s, dari, ke);
}

pub fn pisah(allocator: std.mem.Allocator, s: []const u8, sep: []const u8) ![][]const u8 {
    var list = std.array_list.Managed([]const u8).init(allocator);
    if (sep.len == 0) {
        try list.append(s);
        return list.toOwnedSlice();
    }
    var it = std.mem.splitSequence(u8, s, sep);
    while (it.next()) |part| try list.append(part);
    return list.toOwnedSlice();
}

pub fn mulaiDengan(s: []const u8, pre: []const u8) bool {
    return std.mem.startsWith(u8, s, pre);
}

pub fn akhiriDengan(s: []const u8, suf: []const u8) bool {
    return std.mem.endsWith(u8, s, suf);
}

fn hexVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn urlDecode(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            if (hexVal(s[i + 1])) |hi| {
                if (hexVal(s[i + 2])) |lo| {
                    try buf.append(hi * 16 + lo);
                    i += 3;
                    continue;
                }
            }
            try buf.append(s[i]);
            i += 1;
        } else if (s[i] == '+') {
            try buf.append(' ');
            i += 1;
        } else {
            try buf.append(s[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice();
}

fn paramDari(allocator: std.mem.Allocator, qs: []const u8, key: []const u8) ![]u8 {
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) return urlDecode(allocator, pair[eq + 1 ..]);
    }
    return allocator.dupe(u8, "");
}

pub fn kueri(allocator: std.mem.Allocator, url: []const u8, key: []const u8) ![]u8 {
    const qs = if (std.mem.indexOfScalar(u8, url, '?')) |i| url[i + 1 ..] else url[0..0];
    return paramDari(allocator, qs, key);
}

pub fn form(allocator: std.mem.Allocator, body: []const u8, key: []const u8) ![]u8 {
    return paramDari(allocator, body, key);
}

pub fn cookieAmbil(allocator: std.mem.Allocator, header: []const u8, key: []const u8) ![]u8 {
    var it = std.mem.splitScalar(u8, header, ';');
    while (it.next()) |raw| {
        const pair = std.mem.trim(u8, raw, " ");
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], key)) return allocator.dupe(u8, pair[eq + 1 ..]);
    }
    return allocator.dupe(u8, "");
}

pub fn tipeKonten(nama: []const u8) []const u8 {
    const tabel = [_]struct { ext: []const u8, mime: []const u8 }{
        .{ .ext = ".html", .mime = "text/html; charset=utf-8" },
        .{ .ext = ".css", .mime = "text/css" },
        .{ .ext = ".js", .mime = "application/javascript" },
        .{ .ext = ".json", .mime = "application/json" },
        .{ .ext = ".png", .mime = "image/png" },
        .{ .ext = ".jpg", .mime = "image/jpeg" },
        .{ .ext = ".jpeg", .mime = "image/jpeg" },
        .{ .ext = ".gif", .mime = "image/gif" },
        .{ .ext = ".svg", .mime = "image/svg+xml" },
        .{ .ext = ".ico", .mime = "image/x-icon" },
        .{ .ext = ".txt", .mime = "text/plain; charset=utf-8" },
    };
    for (tabel) |t| {
        if (std.mem.endsWith(u8, nama, t.ext)) return t.mime;
    }
    return "application/octet-stream";
}

pub fn pangkas(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    return allocator.dupe(u8, std.mem.trim(u8, s, " \t\r\n"));
}

pub fn keBesar(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return buf;
}

pub fn keKecil(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf;
}
