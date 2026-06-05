const std = @import("std");
const token = @import("token.zig");
const Token = token.Token;
const TokenKind = token.TokenKind;
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;

pub const Lexer = struct {
    source: []const u8,
    diags: *Diagnostics,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,
    col: usize = 1,
    start_line: usize = 1,
    start_col: usize = 1,

    pub fn init(source: []const u8, diags: *Diagnostics) Lexer {
        var src = source;
        if (std.mem.startsWith(u8, src, "\xEF\xBB\xBF")) src = src[3..];
        return .{ .source = src, .diags = diags };
    }

    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var list = std.ArrayList(Token).init(allocator);
        errdefer list.deinit();
        while (true) {
            const tok = try self.next();
            try list.append(tok);
            if (tok.kind == .eof) break;
        }
        return list.toOwnedSlice();
    }

    fn next(self: *Lexer) !Token {
        self.skipTrivia();
        self.start = self.current;
        self.start_line = self.line;
        self.start_col = self.col;

        if (self.isAtEnd()) return self.make(.eof);

        const c = self.advance();
        return switch (c) {
            '(' => self.make(.lparen),
            ')' => self.make(.rparen),
            '{' => self.make(.lbrace),
            '}' => self.make(.rbrace),
            '[' => self.make(.lbracket),
            ']' => self.make(.rbracket),
            ',' => self.make(.comma),
            ':' => self.make(.colon),
            ';' => self.make(.semicolon),
            '+' => self.make(.plus),
            '-' => self.make(.minus),
            '*' => self.make(.star),
            '/' => self.make(.slash),
            '%' => self.make(.percent),
            '=' => self.make(if (self.match('=')) .eq else .assign),
            '!' => self.make(if (self.match('=')) .neq else .bang),
            '<' => self.make(if (self.match('=')) .le else .lt),
            '>' => self.make(if (self.match('=')) .ge else .gt),
            '&' => if (self.match('&')) self.make(.and_and) else self.invalidChar("operator '&' tidak valid, maksudnya '&&'?"),
            '|' => if (self.match('|')) self.make(.or_or) else self.invalidChar("operator '|' tidak valid, maksudnya '||'?"),
            '"' => self.string(),
            else => {
                if (isDigit(c)) return self.number();
                if (isAlpha(c)) return self.identifier();
                return self.invalidChar("karakter tidak dikenal");
            },
        };
    }

    fn string(self: *Lexer) !Token {
        while (!self.isAtEnd() and self.peek() != '"') {
            if (self.peek() == '\\') {
                _ = self.advance();
                if (!self.isAtEnd()) _ = self.advance();
            } else {
                _ = self.advance();
            }
        }
        if (self.isAtEnd()) {
            try self.diags.report(.err, self.start_line, self.start_col, "string belum ditutup");
            return self.make(.invalid);
        }
        _ = self.advance();
        return self.make(.string);
    }

    fn number(self: *Lexer) Token {
        while (isDigit(self.peek())) _ = self.advance();
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
        }
        return self.make(.number);
    }

    fn identifier(self: *Lexer) Token {
        while (isAlphaNum(self.peek())) _ = self.advance();
        const text = self.source[self.start..self.current];
        return self.make(token.lookupKeyword(text) orelse .identifier);
    }

    fn invalidChar(self: *Lexer, message: []const u8) !Token {
        try self.diags.report(.err, self.start_line, self.start_col, message);
        return self.make(.invalid);
    }

    fn skipTrivia(self: *Lexer) void {
        while (!self.isAtEnd()) {
            switch (self.peek()) {
                ' ', '\t', '\r', '\n' => _ = self.advance(),
                '/' => {
                    if (self.peekNext() == '/') {
                        while (!self.isAtEnd() and self.peek() != '\n') _ = self.advance();
                    } else return;
                },
                else => return,
            }
        }
    }

    fn make(self: *Lexer, kind: TokenKind) Token {
        return .{
            .kind = kind,
            .lexeme = self.source[self.start..self.current],
            .line = self.start_line,
            .column = self.start_col,
        };
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }

    fn peek(self: *const Lexer) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current];
    }

    fn peekNext(self: *const Lexer) u8 {
        return if (self.current + 1 >= self.source.len) 0 else self.source[self.current + 1];
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

fn tokenizeForTest(allocator: std.mem.Allocator, source: []const u8, diags: *Diagnostics) ![]Token {
    var lexer = Lexer.init(source, diags);
    return lexer.tokenize(allocator);
}

test "tokenisasi deklarasi variabel" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "biar angka = 10;", &diags);
    defer std.testing.allocator.free(toks);

    const expected = [_]TokenKind{ .kw_biar, .identifier, .assign, .number, .semicolon, .eof };
    try std.testing.expectEqual(expected.len, toks.len);
    for (expected, toks) |want, got| {
        try std.testing.expectEqual(want, got.kind);
    }
    try std.testing.expect(!diags.hasErrors());
}

test "operator dua karakter dan tipe" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "x >= 5 && y != 3 || !z", &diags);
    defer std.testing.allocator.free(toks);

    const expected = [_]TokenKind{
        .identifier, .ge, .number, .and_and, .identifier, .neq, .number, .or_or, .bang, .identifier, .eof,
    };
    try std.testing.expectEqual(expected.len, toks.len);
    for (expected, toks) |want, got| {
        try std.testing.expectEqual(want, got.kind);
    }
}

test "float, string, komentar diabaikan" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const src =
        \\tetap pi = 3.14; // konstanta
        \\cetak("halo");
    ;
    const toks = try tokenizeForTest(std.testing.allocator, src, &diags);
    defer std.testing.allocator.free(toks);

    const expected = [_]TokenKind{
        .kw_tetap,   .identifier, .assign, .number, .semicolon,
        .identifier, .lparen,     .string, .rparen, .semicolon,
        .eof,
    };
    try std.testing.expectEqual(expected.len, toks.len);
    for (expected, toks) |want, got| {
        try std.testing.expectEqual(want, got.kind);
    }
    try std.testing.expectEqualStrings("3.14", toks[3].lexeme);
    try std.testing.expectEqualStrings("\"halo\"", toks[7].lexeme);
}

test "posisi line dan kolom" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "biar\n  x", &diags);
    defer std.testing.allocator.free(toks);

    try std.testing.expectEqual(@as(usize, 1), toks[0].line);
    try std.testing.expectEqual(@as(usize, 1), toks[0].column);
    try std.testing.expectEqual(@as(usize, 2), toks[1].line);
    try std.testing.expectEqual(@as(usize, 3), toks[1].column);
}

test "string belum ditutup lapor diagnostik" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "cetak(\"halo", &diags);
    defer std.testing.allocator.free(toks);

    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqual(TokenKind.invalid, toks[toks.len - 2].kind);
    try std.testing.expectEqual(TokenKind.eof, toks[toks.len - 1].kind);
}

test "karakter tidak dikenal lapor diagnostik" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "biar x = @;", &diags);
    defer std.testing.allocator.free(toks);

    try std.testing.expect(diags.hasErrors());
}

test "sumber kosong hanya eof" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const toks = try tokenizeForTest(std.testing.allocator, "", &diags);
    defer std.testing.allocator.free(toks);

    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.eof, toks[0].kind);
}
