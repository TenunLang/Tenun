const std = @import("std");

// Pool koneksi TLS klien. Handle = indeks ke daftar. Dipakai oleh builtin
// sambungAman/kirimAman/terimaAman/tutupAman (IMAPS, SMTPS, REST ber-TLS).
// Struktur persisten pakai page_allocator agar hidup lintas reset arena.

const Conn = struct {
    stream: std.net.Stream,
    client: *std.crypto.tls.Client,
};

var mutex: std.Thread.Mutex = .{};
var conns: std.ArrayListUnmanaged(?Conn) = .{};
var bundle: ?std.crypto.Certificate.Bundle = null;

const pa = std.heap.page_allocator;

// Sambung TCP + handshake TLS. Kembalikan handle (>=0) atau galat.
pub fn connect(host: []const u8, port: u16) !i64 {
    mutex.lock();
    defer mutex.unlock();

    if (bundle == null) {
        var b: std.crypto.Certificate.Bundle = .{};
        try b.rescan(pa);
        bundle = b;
    }

    const host_z = try pa.dupe(u8, host);
    const stream = try std.net.tcpConnectToHost(pa, host, port);

    const client = try pa.create(std.crypto.tls.Client);
    client.* = try std.crypto.tls.Client.init(stream, .{
        .host = .{ .explicit = host_z },
        .ca = .{ .bundle = bundle.? },
    });

    try conns.append(pa, .{ .stream = stream, .client = client });
    return @intCast(conns.items.len - 1);
}

fn get(idx: i64) ?*Conn {
    if (idx < 0) return null;
    const i: usize = @intCast(idx);
    if (i >= conns.items.len) return null;
    if (conns.items[i]) |*c| return c;
    return null;
}

pub fn send(idx: i64, data: []const u8) !void {
    const c = get(idx) orelse return error.HandleTidakValid;
    try c.client.writeAll(c.stream, data);
}

// Baca hingga `n` byte (satu pembacaan record TLS). Buffer dialokasi dari `a`.
pub fn recv(a: std.mem.Allocator, idx: i64, n: usize) ![]u8 {
    const c = get(idx) orelse return error.HandleTidakValid;
    const buf = try a.alloc(u8, n);
    const got = c.client.read(c.stream, buf) catch 0;
    return buf[0..got];
}

pub fn close(idx: i64) void {
    mutex.lock();
    defer mutex.unlock();
    const i: usize = if (idx < 0) return else @intCast(idx);
    if (i >= conns.items.len) return;
    if (conns.items[i]) |c| {
        _ = c.client.writeAllEnd(c.stream, "", true) catch {};
        c.stream.close();
        pa.destroy(c.client);
        conns.items[i] = null;
    }
}
