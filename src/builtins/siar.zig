const std = @import("std");

// Registry soket aktif untuk broadcast lintas koneksi (layaniSoket = VM per koneksi,
// jadi global Tenun tak terbagi; registry ini hidup di runtime, mutex-guarded).
// Dipakai builtin `siarkan(data)` + auto register/unregister oleh layaniSoket.

var mutex: std.Thread.Mutex = .{};
var streams: std.ArrayListUnmanaged(?std.net.Stream) = .{};
const pa = std.heap.page_allocator;

pub fn register(s: std.net.Stream) i64 {
    mutex.lock();
    defer mutex.unlock();
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
    mutex.lock();
    defer mutex.unlock();
    const i: usize = @intCast(id);
    if (i < streams.items.len) streams.items[i] = null;
}

// Kirim byte mentah (frame lengkap) ke semua soket terdaftar.
pub fn broadcast(data: []const u8) void {
    mutex.lock();
    defer mutex.unlock();
    for (streams.items) |x| {
        if (x) |s| {
            // Pakai send() Winsock/posix (bukan WriteFile std.net) agar pengiriman
            // lintas-thread (broadcast dari koneksi lain) tersampaikan di Windows.
            var off: usize = 0;
            while (off < data.len) {
                const w = std.posix.send(s.handle, data[off..], 0) catch break;
                if (w == 0) break;
                off += w;
            }
        }
    }
}
