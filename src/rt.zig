const std = @import("std");

// Runtime global Io (Zig 0.16). Diisi sekali di main(), dipakai builtin yang
// butuh I/O (file, soket, http) tanpa harus dioper lewat tiap signature.
// Single-binary, single runtime — global di sini disengaja.
pub var io: std.Io = undefined;

// Peta environment variable (diisi di main dari process.Init). Builtin yang
// butuh env (TENUN_PORT/TENUN_WORKERS, os.env) membacanya lewat getenv().
pub var env_map: ?*std.process.Environ.Map = null;

// Overlay dari berkas .env (diisi loadDotenv di awal). Env proses asli menang;
// .env hanya mengisi yang belum diset — mirip perilaku dotenv pada umumnya.
pub var dotenv: ?std.StringHashMap([]const u8) = null;

pub fn getenv(key: []const u8) ?[]const u8 {
    if (env_map) |m| if (m.get(key)) |v| return v;
    if (dotenv) |d| return d.get(key);
    return null;
}

// Muat berkas .env dari direktori kerja (KEY=VALUE per baris) ke overlay.
// Format: lewati baris kosong & komentar (#), dukung prefix "export ",
// dan kutip "..."/'...' opsional di sekeliling nilai. Aman dipanggil sekali.
pub fn loadDotenv(gpa: std.mem.Allocator) void {
    const data = std.Io.Dir.cwd().readFileAlloc(io, ".env", gpa, std.Io.Limit.limited(1 << 20)) catch return;
    defer gpa.free(data);
    var map = std.StringHashMap([]const u8).init(gpa);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "export ")) line = std.mem.trim(u8, line["export ".len..], " \t");
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        if (key.len == 0) continue;
        var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
            val = val[1 .. val.len - 1];
        }
        const k = gpa.dupe(u8, key) catch continue;
        const v = gpa.dupe(u8, val) catch continue;
        map.put(k, v) catch {};
    }
    dotenv = map;
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
