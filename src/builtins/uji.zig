const std = @import("std");
const rt = @import("../rt.zig");

// Kerangka uji unit gaya Jest/Mocha. Berkas `*.uji.tenun` memanggil tegas*()
// untuk menyatakan ekspektasi; `tenun check` mereset penghitung sebelum tiap
// berkas, menjalankannya, lalu membaca jumlah lulus/gagal di sini.

var pass: usize = 0;
var fail: usize = 0;

pub fn reset() void {
    pass = 0;
    fail = 0;
}

pub fn lulus() usize {
    return pass;
}

pub fn gagal() usize {
    return fail;
}

pub fn tegas(cond: bool, nama: []const u8) void {
    if (cond) {
        pass += 1;
        rt.cetak("  LULUS {s}\n", .{nama});
    } else {
        fail += 1;
        rt.cetak("  GAGAL {s}\n", .{nama});
    }
}

pub fn tegasSama(a: []const u8, b: []const u8, nama: []const u8) void {
    if (std.mem.eql(u8, a, b)) {
        pass += 1;
        rt.cetak("  LULUS {s}\n", .{nama});
    } else {
        fail += 1;
        rt.cetak("  GAGAL {s} (harap \"{s}\", dapat \"{s}\")\n", .{ nama, b, a });
    }
}

pub fn tegasSamaBulat(a: i64, b: i64, nama: []const u8) void {
    if (a == b) {
        pass += 1;
        rt.cetak("  LULUS {s}\n", .{nama});
    } else {
        fail += 1;
        rt.cetak("  GAGAL {s} (harap {d}, dapat {d})\n", .{ nama, b, a });
    }
}
