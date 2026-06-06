const std = @import("std");

pub const TokenKind = enum {
    number,
    string,
    identifier,

    kw_biar,
    kw_tetap,
    kw_fungsi,
    kw_kembali,
    kw_kalau,
    kw_lain,
    kw_selama,
    kw_untuk,
    kw_dari,
    kw_sampai,
    kw_benar,
    kw_salah,
    kw_kosong,
    kw_henti,
    kw_lanjut,
    kw_coba,
    kw_tangkap,
    kw_cocok,

    ty_bulat,
    ty_desimal,
    ty_teks,
    ty_bool,
    ty_peta,
    ty_dinamis,

    plus,
    minus,
    star,
    slash,
    percent,
    assign,
    plus_plus,
    minus_minus,
    plus_eq,
    minus_eq,
    star_eq,
    slash_eq,
    percent_eq,
    eq,
    neq,
    lt,
    gt,
    le,
    ge,
    and_and,
    or_or,
    bang,
    amp,
    pipe,
    caret,
    shl,
    shr,

    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    comma,
    colon,
    semicolon,

    eof,
    invalid,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

pub const keywords = std.StaticStringMap(TokenKind).initComptime(.{
    .{ "biar", .kw_biar },
    .{ "tetap", .kw_tetap },
    .{ "fungsi", .kw_fungsi },
    .{ "kembali", .kw_kembali },
    .{ "kalau", .kw_kalau },
    .{ "lain", .kw_lain },
    .{ "selama", .kw_selama },
    .{ "untuk", .kw_untuk },
    .{ "dari", .kw_dari },
    .{ "sampai", .kw_sampai },
    .{ "benar", .kw_benar },
    .{ "salah", .kw_salah },
    .{ "kosong", .kw_kosong },
    .{ "henti", .kw_henti },
    .{ "lanjut", .kw_lanjut },
    .{ "coba", .kw_coba },
    .{ "tangkap", .kw_tangkap },
    .{ "cocok", .kw_cocok },
    .{ "bulat", .ty_bulat },
    .{ "desimal", .ty_desimal },
    .{ "teks", .ty_teks },
    .{ "bool", .ty_bool },
    .{ "peta", .ty_peta },
    .{ "dinamis", .ty_dinamis },
});

pub fn lookupKeyword(text: []const u8) ?TokenKind {
    return keywords.get(text);
}

test "lookup keyword vs identifier" {
    try std.testing.expectEqual(TokenKind.kw_biar, lookupKeyword("biar").?);
    try std.testing.expectEqual(TokenKind.ty_bulat, lookupKeyword("bulat").?);
    try std.testing.expect(lookupKeyword("namaVariabel") == null);
}
