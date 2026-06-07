const std = @import("std");
const rt = @import("../rt.zig");

// Pembungkus koneksi soket TCP untuk Zig 0.16: net.Stream tak lagi punya
// read/write langsung — operasi lewat Reader/Writer ber-buffer yang mengikat
// `io`. Reader/Writer wajib persisten per koneksi supaya byte yang sudah
// ter-buffer (mis. protokol biner client DB) tak hilang antar pemanggilan.
// Conn disimpan via pointer (stabil di heap); Reader/Writer mereferensikan
// buffer di dalam Conn yang sama.

pub const Conn = struct {
    stream: std.Io.net.Stream,
    r: std.Io.net.Stream.Reader,
    w: std.Io.net.Stream.Writer,
    rbuf: [64 * 1024]u8 = undefined,
    wbuf: [64 * 1024]u8 = undefined,
};

// Bungkus Stream yang sudah ada (mis. hasil accept) jadi *Conn ber-buffer.
pub fn wrap(allocator: std.mem.Allocator, stream: std.Io.net.Stream) !*Conn {
    const c = try allocator.create(Conn);
    c.stream = stream;
    c.r = stream.reader(rt.io, &c.rbuf);
    c.w = stream.writer(rt.io, &c.wbuf);
    return c;
}

// Sambung ke host:port lalu bungkus.
pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !*Conn {
    const addr = try std.Io.net.IpAddress.resolve(rt.io, host, port);
    const stream = try addr.connect(rt.io, .{ .mode = .stream });
    errdefer stream.close(rt.io);
    return wrap(allocator, stream);
}

pub fn send(c: *Conn, data: []const u8) !void {
    try c.w.interface.writeAll(data);
    try c.w.interface.flush();
}

// Baca sekali (hingga buf.len byte). Kembalikan jumlah byte; 0 = tutup/galat.
pub fn recv(c: *Conn, buf: []u8) usize {
    return c.r.interface.readSliceShort(buf) catch 0;
}

// Baca tepat buf.len byte (atau sampai koneksi tutup). Kembalikan jumlah byte.
pub fn recvExact(c: *Conn, buf: []u8) usize {
    var got: usize = 0;
    while (got < buf.len) {
        const n = c.r.interface.readSliceShort(buf[got..]) catch break;
        if (n == 0) break;
        got += n;
    }
    return got;
}

pub fn close(allocator: std.mem.Allocator, c: *Conn) void {
    c.w.interface.flush() catch {};
    c.stream.close(rt.io);
    allocator.destroy(c);
}
