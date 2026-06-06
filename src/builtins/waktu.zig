const std = @import("std");

// Format unix timestamp (detik) jadi "YYYY-MM-DD HH:MM:SS" pada offset zona waktu
// (jam, mis. 7 untuk WIB). Algoritma civil-from-days (Howard Hinnant).
pub fn tanggal(a: std.mem.Allocator, ts: i64, offset_jam: i64) ![]u8 {
    const total = ts + offset_jam * 3600;
    const days = @divFloor(total, 86400);
    const secs = @mod(total, 86400);
    const jam = @divFloor(secs, 3600);
    const menit = @divFloor(@mod(secs, 3600), 60);
    const detik = @mod(secs, 60);

    const z = days + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe = z - era * 146097; // [0, 146096]
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    if (m <= 2) y += 1;

    return std.fmt.allocPrint(a, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        @as(u64, @intCast(y)),    @as(u64, @intCast(m)),     @as(u64, @intCast(d)),
        @as(u64, @intCast(jam)),  @as(u64, @intCast(menit)), @as(u64, @intCast(detik)),
    });
}
