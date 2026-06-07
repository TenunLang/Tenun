const std = @import("std");
const rt = @import("../rt.zig");

// Pool koneksi TLS klien. Handle = indeks ke daftar. Dipakai oleh builtin
// sambungAman/kirimAman/terimaAman/tutupAman (IMAPS, SMTPS, REST ber-TLS).
// Struktur persisten pakai page_allocator agar hidup lintas reset arena.
//
// Zig 0.16: tls.Client kini pakai antarmuka Io.Reader/Io.Writer. Tiap koneksi
// mengikat reader/writer soket + buffer-nya, jadi Conn wajib stabil di heap
// (disimpan sebagai pointer, bukan nilai, supaya tak pindah saat list tumbuh).

const min = std.crypto.tls.Client.min_buffer_len;

const Conn = struct {
    stream: std.Io.net.Stream,
    sr: std.Io.net.Stream.Reader,
    sw: std.Io.net.Stream.Writer,
    client: std.crypto.tls.Client,
    sock_read_buf: [min]u8 = undefined,
    sock_write_buf: [min]u8 = undefined,
    tls_read_buf: [min]u8 = undefined,
    tls_write_buf: [min]u8 = undefined,
};

var mutex: std.Io.Mutex = .init;
var conns: std.ArrayList(?*Conn) = .empty;
var bundle: ?std.crypto.Certificate.Bundle = null;
var bundle_lock: std.Io.RwLock = .init;

const pa = std.heap.page_allocator;

// Sambung TCP + handshake TLS. Kembalikan handle (>=0) atau galat.
pub fn connect(host: []const u8, port: u16) !i64 {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);

    const io = rt.io;
    const now = std.Io.Clock.now(.real, io);

    if (bundle == null) {
        var b: std.crypto.Certificate.Bundle = .empty;
        try b.rescan(pa, io, now);
        bundle = b;
    }

    const host_z = try pa.dupe(u8, host);
    errdefer pa.free(host_z);

    const addr = try std.Io.net.IpAddress.resolve(io, host, port);
    const stream = try addr.connect(io, .{ .mode = .stream });
    errdefer stream.close(io);

    const c = try pa.create(Conn);
    errdefer pa.destroy(c);
    c.stream = stream;
    c.sr = stream.reader(io, &c.sock_read_buf);
    c.sw = stream.writer(io, &c.sock_write_buf);

    var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
    io.random(&entropy);

    c.client = try std.crypto.tls.Client.init(&c.sr.interface, &c.sw.interface, .{
        .host = .{ .explicit = host_z },
        .ca = .{ .bundle = .{
            .gpa = pa,
            .io = io,
            .lock = &bundle_lock,
            .bundle = &bundle.?,
        } },
        .read_buffer = &c.tls_read_buf,
        .write_buffer = &c.tls_write_buf,
        .entropy = &entropy,
        .realtime_now = now,
    });

    try conns.append(pa, c);
    return @intCast(conns.items.len - 1);
}

fn get(idx: i64) ?*Conn {
    if (idx < 0) return null;
    const i: usize = @intCast(idx);
    if (i >= conns.items.len) return null;
    return conns.items[i];
}

pub fn send(idx: i64, data: []const u8) !void {
    const c = get(idx) orelse return error.HandleTidakValid;
    try c.client.writer.writeAll(data);
    try c.client.writer.flush();
}

// Baca hingga `n` byte (satu pembacaan). Buffer dialokasi dari `a`.
pub fn recv(a: std.mem.Allocator, idx: i64, n: usize) ![]u8 {
    const c = get(idx) orelse return error.HandleTidakValid;
    const buf = try a.alloc(u8, n);
    const got = c.client.reader.readSliceShort(buf) catch 0;
    return buf[0..got];
}

pub fn close(idx: i64) void {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    const i: usize = if (idx < 0) return else @intCast(idx);
    if (i >= conns.items.len) return;
    if (conns.items[i]) |c| {
        c.client.writer.flush() catch {};
        c.stream.close(rt.io);
        pa.destroy(c);
        conns.items[i] = null;
    }
}
