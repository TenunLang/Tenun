const std = @import("std");
const rt = @import("../rt.zig");

// Registry soket aktif untuk broadcast lintas koneksi (layaniSoket = VM per koneksi,
// jadi global Tenun tak terbagi; registry ini hidup di runtime, mutex-guarded).
// Dipakai builtin `siarkan(data)` + auto register/unregister oleh layaniSoket.

var mutex: std.Io.Mutex = .init;
var streams: std.ArrayList(?std.Io.net.Stream) = .empty;
const pa = std.heap.page_allocator;

pub fn register(s: std.Io.net.Stream) i64 {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    for (streams.items, 0..) |x, i| {
        if (x == null) {
            streams.items[i] = s;
            return @intCast(i);
        }
    }
    streams.append(pa, s) catch return -1;
    return @intCast(streams.items.len - 1);
}

pub fn unregister(id: i64) void {
    if (id < 0) return;
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    const i: usize = @intCast(id);
    if (i < streams.items.len) streams.items[i] = null;
}

// Kirim byte mentah (frame lengkap) ke semua soket terdaftar.
pub fn broadcast(data: []const u8) void {
    mutex.lockUncancelable(rt.io);
    defer mutex.unlock(rt.io);
    for (streams.items) |x| {
        if (x) |s| {
            var buf: [4096]u8 = undefined;
            var w = s.writer(rt.io, &buf);
            w.interface.writeAll(data) catch continue;
            w.interface.flush() catch {};
        }
    }
}
