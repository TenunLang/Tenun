const ast = @import("../parser/ast.zig");
const Type = ast.Type;

const teks_el: Type = .teks;
const teks_array = Type{ .array = &teks_el };

pub const Spec = struct {
    name: []const u8,
    params: []const Type,
    ret: Type,
};

pub const list = [_]Spec{
    .{ .name = "ambil", .params = &.{.teks}, .ret = .teks },
    .{ .name = "akar", .params = &.{.desimal}, .ret = .desimal },
    .{ .name = "pangkat", .params = &.{ .desimal, .desimal }, .ret = .desimal },
    .{ .name = "mutlak", .params = &.{.desimal}, .ret = .desimal },
    .{ .name = "bulatkan", .params = &.{.desimal}, .ret = .bulat },
    .{ .name = "panjangTeks", .params = &.{.teks}, .ret = .bulat },
    .{ .name = "potong", .params = &.{ .teks, .bulat, .bulat }, .ret = .teks },
    .{ .name = "bacaFile", .params = &.{.teks}, .ret = .teks },
    .{ .name = "tulisFile", .params = &.{ .teks, .teks }, .ret = .kosong },
    .{ .name = "layani", .params = &.{.bulat}, .ret = .kosong },
    .{ .name = "statusKan", .params = &.{.bulat}, .ret = .kosong },
    .{ .name = "headerKan", .params = &.{ .teks, .teks }, .ret = .kosong },
    .{ .name = "cari", .params = &.{ .teks, .teks }, .ret = .bulat },
    .{ .name = "ganti", .params = &.{ .teks, .teks, .teks }, .ret = .teks },
    .{ .name = "pisah", .params = &.{ .teks, .teks }, .ret = teks_array },
    .{ .name = "gabung", .params = &.{ teks_array, .teks }, .ret = .teks },
    .{ .name = "mulaiDengan", .params = &.{ .teks, .teks }, .ret = .bool },
    .{ .name = "akhiriDengan", .params = &.{ .teks, .teks }, .ret = .bool },
    .{ .name = "tipeKonten", .params = &.{.teks}, .ret = .teks },
    .{ .name = "jsonTeks", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "jsonAngka", .params = &.{ .teks, .teks }, .ret = .bulat },
    .{ .name = "jsonBool", .params = &.{ .teks, .teks }, .ret = .bool },
    .{ .name = "adaFile", .params = &.{.teks}, .ret = .bool },
    .{ .name = "kueri", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "form", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "headerMasuk", .params = &.{.teks}, .ret = .teks },
    .{ .name = "cookie", .params = &.{.teks}, .ret = .teks },
    .{ .name = "simpan", .params = &.{ .teks, .teks }, .ret = .kosong },
    .{ .name = "muat", .params = &.{.teks}, .ret = .teks },
    .{ .name = "hapus", .params = &.{.teks}, .ret = .kosong },
    .{ .name = "sambung", .params = &.{ .teks, .bulat }, .ret = .bulat },
    .{ .name = "kirim", .params = &.{ .bulat, .teks }, .ret = .kosong },
    .{ .name = "terima", .params = &.{ .bulat, .bulat }, .ret = .teks },
    .{ .name = "tutup", .params = &.{.bulat}, .ret = .kosong },
    .{ .name = "sha256", .params = &.{.teks}, .ret = .teks },
    .{ .name = "sha1", .params = &.{.teks}, .ret = .teks },
    .{ .name = "md5", .params = &.{.teks}, .ret = .teks },
    .{ .name = "hmacSha256", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "base64", .params = &.{.teks}, .ret = .teks },
    .{ .name = "dariBase64", .params = &.{.teks}, .ret = .teks },
    .{ .name = "acak", .params = &.{.bulat}, .ret = .teks },
    .{ .name = "keByte", .params = &.{ .bulat, .bulat, .bool }, .ret = .teks },
    .{ .name = "bacaInt", .params = &.{ .teks, .bulat, .bulat, .bool }, .ret = .bulat },
    .{ .name = "sha1Raw", .params = &.{.teks}, .ret = .teks },
    .{ .name = "xor", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "terimaPasti", .params = &.{ .bulat, .bulat }, .ret = .teks },
    .{ .name = "keBulat", .params = &.{.teks}, .ret = .bulat },
    .{ .name = "keTeks", .params = &.{.bulat}, .ret = .teks },
    .{ .name = "dorong", .params = &.{ teks_array, .teks }, .ret = teks_array },
    .{ .name = "sha256Raw", .params = &.{.teks}, .ret = .teks },
    .{ .name = "hmacSha256Raw", .params = &.{ .teks, .teks }, .ret = .teks },
    .{ .name = "pbkdf2", .params = &.{ .teks, .teks, .bulat }, .ret = .teks },
    .{ .name = "bacaFloat", .params = &.{ .teks, .bulat, .bulat }, .ret = .teks },
    .{ .name = "petaPunya", .params = &.{ .peta, .teks }, .ret = .bool },
    .{ .name = "petaKunci", .params = &.{.peta}, .ret = teks_array },
    .{ .name = "petaHapus", .params = &.{ .peta, .teks }, .ret = .kosong },
    .{ .name = "httpKirim", .params = &.{ .teks, .teks, .teks, .teks }, .ret = .teks },
    .{ .name = "sambungAman", .params = &.{ .teks, .bulat }, .ret = .bulat },
    .{ .name = "kirimAman", .params = &.{ .bulat, .teks }, .ret = .kosong },
    .{ .name = "terimaAman", .params = &.{ .bulat, .bulat }, .ret = .teks },
    .{ .name = "tutupAman", .params = &.{.bulat}, .ret = .kosong },
    .{ .name = "layaniSoket", .params = &.{.bulat}, .ret = .kosong },
    .{ .name = "siarkan", .params = &.{.teks}, .ret = .kosong },
    .{ .name = "argumen", .params = &.{}, .ret = teks_array },
    .{ .name = "waktu", .params = &.{}, .ret = .bulat },
    .{ .name = "acakAngka", .params = &.{ .bulat, .bulat }, .ret = .bulat },
    .{ .name = "keDesimal", .params = &.{.teks}, .ret = .desimal },
    .{ .name = "pangkas", .params = &.{.teks}, .ret = .teks },
    .{ .name = "keBesar", .params = &.{.teks}, .ret = .teks },
    .{ .name = "keKecil", .params = &.{.teks}, .ret = .teks },
    .{ .name = "tanggal", .params = &.{ .bulat, .bulat }, .ret = .teks },
    .{ .name = "waktuMili", .params = &.{}, .ret = .bulat },
};

pub const layani_id = 9;


pub fn indexOf(name: []const u8) ?usize {
    const std = @import("std");
    for (list, 0..) |s, i| {
        if (std.mem.eql(u8, s.name, name)) return i;
    }
    return null;
}
