const std = @import("std");

// Runtime global Io (Zig 0.16). Diisi sekali di main(), dipakai builtin yang
// butuh I/O (file, soket, http) tanpa harus dioper lewat tiap signature.
// Single-binary, single runtime — global di sini disengaja.
pub var io: std.Io = undefined;

// Peta environment variable (diisi di main dari process.Init). Builtin yang
// butuh env (TENUN_PORT/TENUN_WORKERS, os.env) membacanya lewat getenv().
pub var env_map: ?*std.process.Environ.Map = null;

pub fn getenv(key: []const u8) ?[]const u8 {
    if (env_map) |m| return m.get(key);
    return null;
}

// Waktu Unix (Zig 0.16: std.time.timestamp dihapus, pakai jam realtime Io).
pub fn waktuDetik() i64 {
    const t = std.Io.Clock.now(.real, io);
    return @intCast(@divTrunc(t.nanoseconds, std.time.ns_per_s));
}

pub fn waktuMili() i64 {
    const t = std.Io.Clock.now(.real, io);
    return @intCast(@divTrunc(t.nanoseconds, std.time.ns_per_ms));
}

// Acak (Zig 0.16: std.crypto.random dihapus, pakai sumber acak Io).
fn acakU64() u64 {
    var b: [8]u8 = undefined;
    io.random(&b);
    return std.mem.readInt(u64, &b, .little);
}

pub fn acakBytes(buf: []u8) void {
    io.random(buf);
}

pub fn acakRentang(lo: i64, hi: i64) i64 {
    if (hi <= lo) return lo;
    const span: u64 = @intCast(hi - lo);
    return lo + @as(i64, @intCast(acakU64() % span));
}

pub fn acakFloat() f64 {
    const v = acakU64() >> 11; // 53 bit mantissa
    return @as(f64, @floatFromInt(v)) / @as(f64, @floatFromInt(@as(u64, 1) << 53));
}

var stdout_w: std.Io.File.Writer = undefined;
var stdout_buf: [4096]u8 = undefined;
var stderr_w: std.Io.File.Writer = undefined;
var stderr_buf: [4096]u8 = undefined;

// Writer stdout/stderr terbuffer. Pemanggil wajib flush() setelah selesai,
// atau pakai helper cetak()/galat() di bawah yang otomatis flush.
pub fn out() *std.Io.Writer {
    stdout_w = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    return &stdout_w.interface;
}

pub fn err() *std.Io.Writer {
    stderr_w = std.Io.File.stderr().writerStreaming(io, &stderr_buf);
    return &stderr_w.interface;
}

// Cetak sekali ke stdout lalu flush. Abaikan galat I/O.
pub fn cetak(comptime fmt: []const u8, args: anytype) void {
    const w = out();
    w.print(fmt, args) catch {};
    w.flush() catch {};
}

// Cetak sekali ke stderr lalu flush. Abaikan galat I/O.
pub fn galat(comptime fmt: []const u8, args: anytype) void {
    const w = err();
    w.print(fmt, args) catch {};
    w.flush() catch {};
}
