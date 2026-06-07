const std = @import("std");
const ast = @import("ast.zig");
const tok = @import("../lexer/token.zig");
const Token = tok.Token;
const TokenKind = tok.TokenKind;
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;

pub const Error = error{ParseError} || std.mem.Allocator.Error;

pub fn parse(arena: std.mem.Allocator, tokens: []const Token, diags: *Diagnostics) Error!ast.Program {
    var p = Parser{ .tokens = tokens, .diags = diags, .arena = arena };
    var list = std.array_list.Managed(*ast.Stmt).init(arena);
    while (!p.check(.eof)) {
        const s = try p.declaration();
        try list.append(s);
    }
    return .{ .stmts = try list.toOwnedSlice() };
}

const Parser = struct {
    tokens: []const Token,
    diags: *Diagnostics,
    arena: std.mem.Allocator,
    cur: usize = 0,

    fn declaration(self: *Parser) Error!*ast.Stmt {
        if (self.check(.kw_biar)) return self.varDecl(false);
        if (self.check(.kw_tetap)) return self.varDecl(true);
        if (self.check(.kw_fungsi)) return self.fungsiDecl();
        return self.statement();
    }

    fn varDecl(self: *Parser, is_const: bool) Error!*ast.Stmt {
        const kw = self.advance();
        const name = try self.expect(.identifier, "harap nama variabel setelah deklarasi");
        var type_anno: ?ast.Type = null;
        if (self.match(.colon)) type_anno = try self.parseType();
        _ = try self.expect(.assign, "harap '=' pada deklarasi variabel");
        const value = try self.expression();
        _ = try self.expect(.semicolon, "harap ';' di akhir deklarasi");
        return self.newStmt(posOf(kw), .{ .var_decl = .{
            .is_const = is_const,
            .name = name.lexeme,
            .type_anno = type_anno,
            .value = value,
        } });
    }

    fn fungsiDecl(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const name = try self.expect(.identifier, "harap nama fungsi");
        _ = try self.expect(.lparen, "harap '(' setelah nama fungsi");

        var params = std.array_list.Managed(ast.Param).init(self.arena);
        if (!self.check(.rparen)) {
            while (true) {
                const pname = try self.expect(.identifier, "harap nama parameter");
                _ = try self.expect(.colon, "parameter wajib beranotasi tipe");
                const ptype = try self.parseType();
                try params.append(.{ .name = pname.lexeme, .type = ptype });
                if (!self.match(.comma)) break;
            }
        }
        _ = try self.expect(.rparen, "harap ')' menutup parameter");
        _ = try self.expect(.colon, "harap ':' lalu tipe kembalian fungsi");
        const return_type = try self.parseType();
        const body = try self.block();

        return self.newStmt(posOf(kw), .{ .fungsi_decl = .{
            .name = name.lexeme,
            .params = try params.toOwnedSlice(),
            .return_type = return_type,
            .body = body,
        } });
    }

    fn statement(self: *Parser) Error!*ast.Stmt {
        if (self.check(.kw_kalau)) return self.ifStmt();
        if (self.check(.kw_selama)) return self.whileStmt();
        if (self.check(.kw_untuk)) return self.forStmt();
        if (self.check(.kw_kembali)) return self.returnStmt();
        if (self.check(.kw_coba)) return self.tryStmt();
        if (self.check(.kw_cocok)) return self.matchStmt();
        if (self.check(.kw_henti)) {
            const kw = self.advance();
            _ = try self.expect(.semicolon, "harap ';' setelah henti");
            return self.newStmt(posOf(kw), .break_stmt);
        }
        if (self.check(.kw_lanjut)) {
            const kw = self.advance();
            _ = try self.expect(.semicolon, "harap ';' setelah lanjut");
            return self.newStmt(posOf(kw), .continue_stmt);
        }
        if (self.check(.lbrace)) {
            const lb = self.peek();
            const stmts = try self.block();
            return self.newStmt(posOf(lb), .{ .block = stmts });
        }
        return self.exprStmt();
    }

    fn ifStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const cond = try self.expression();
        const then_block = try self.block();
        var else_branch: ?*ast.Stmt = null;
        if (self.match(.kw_lain)) {
            if (self.check(.kw_kalau)) {
                else_branch = try self.ifStmt();
            } else {
                const lb = self.peek();
                const stmts = try self.block();
                else_branch = try self.newStmt(posOf(lb), .{ .block = stmts });
            }
        }
        return self.newStmt(posOf(kw), .{ .if_stmt = .{
            .cond = cond,
            .then_block = then_block,
            .else_branch = else_branch,
        } });
    }

    fn whileStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const cond = try self.expression();
        const body = try self.block();
        return self.newStmt(posOf(kw), .{ .while_stmt = .{ .cond = cond, .body = body } });
    }

    fn forStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const name = try self.expect(.identifier, "harap nama variabel iterasi setelah 'untuk'");
        _ = try self.expect(.kw_dari, "harap 'dari' lalu nilai awal / larik");
        const start = try self.expression();
        // `untuk x dari A sampai B` (rentang) atau `untuk x dari larik` (foreach).
        if (self.match(.kw_sampai)) {
            const end = try self.expression();
            const body = try self.block();
            return self.newStmt(posOf(kw), .{ .for_stmt = .{
                .var_name = name.lexeme,
                .start = start,
                .end = end,
                .body = body,
            } });
        }
        const body = try self.block();
        return self.newStmt(posOf(kw), .{ .foreach_stmt = .{
            .var_name = name.lexeme,
            .iter = start,
            .body = body,
        } });
    }

    fn matchStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const subject = try self.expression();
        _ = try self.expect(.lbrace, "harap '{' setelah ekspresi 'cocok'");
        var arms = std.array_list.Managed(ast.Stmt.MatchArm).init(self.arena);
        var default: ?[]*ast.Stmt = null;
        while (!self.check(.rbrace) and !self.check(.eof)) {
            if (self.match(.kw_lain)) {
                default = try self.block();
                break;
            }
            const value = try self.expression();
            const body = try self.block();
            try arms.append(.{ .value = value, .body = body });
        }
        _ = try self.expect(.rbrace, "harap '}' menutup 'cocok'");
        return self.newStmt(posOf(kw), .{ .match_stmt = .{
            .subject = subject,
            .arms = try arms.toOwnedSlice(),
            .default = default,
        } });
    }

    fn tryStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        const body = try self.block();
        _ = try self.expect(.kw_tangkap, "harap 'tangkap' setelah blok 'coba'");
        _ = try self.expect(.lparen, "harap '(' lalu nama variabel galat");
        const name = try self.expect(.identifier, "harap nama variabel galat");
        _ = try self.expect(.rparen, "harap ')' setelah nama variabel galat");
        const handler = try self.block();
        return self.newStmt(posOf(kw), .{ .try_stmt = .{
            .body = body,
            .err_name = name.lexeme,
            .handler = handler,
        } });
    }

    fn returnStmt(self: *Parser) Error!*ast.Stmt {
        const kw = self.advance();
        var value: ?*ast.Expr = null;
        if (!self.check(.semicolon)) value = try self.expression();
        _ = try self.expect(.semicolon, "harap ';' setelah kembali");
        return self.newStmt(posOf(kw), .{ .return_stmt = value });
    }

    fn exprStmt(self: *Parser) Error!*ast.Stmt {
        const start = self.peek();
        const e = try self.expression();
        _ = try self.expect(.semicolon, "harap ';' di akhir ekspresi");
        return self.newStmt(posOf(start), .{ .expr_stmt = e });
    }

    fn block(self: *Parser) Error![]*ast.Stmt {
        _ = try self.expect(.lbrace, "harap '{' membuka blok");
        var list = std.array_list.Managed(*ast.Stmt).init(self.arena);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            try list.append(try self.declaration());
        }
        _ = try self.expect(.rbrace, "harap '}' menutup blok");
        return list.toOwnedSlice();
    }

    fn parseType(self: *Parser) Error!ast.Type {
        if (self.check(.lbracket)) {
            _ = self.advance();
            _ = try self.expect(.rbracket, "harap ']' untuk tipe larik");
            const el = try self.arena.create(ast.Type);
            el.* = try self.parseType();
            return .{ .array = el };
        }
        const t = self.peek();
        const ty: ?ast.Type = switch (t.kind) {
            .ty_bulat => .bulat,
            .ty_desimal => .desimal,
            .ty_teks => .teks,
            .ty_bool => .bool,
            .ty_peta => .peta,
            .ty_dinamis => .dinamis,
            .kw_fungsi => .fungsi,
            .kw_kosong => .kosong,
            else => null,
        };
        if (ty) |found| {
            _ = self.advance();
            return found;
        }
        try self.errorHere("tipe tidak valid (harap bulat/desimal/teks/bool/peta/fungsi/dinamis/kosong atau []T)");
        return Error.ParseError;
    }

    fn expression(self: *Parser) Error!*ast.Expr {
        return self.assignment();
    }

    fn assignment(self: *Parser) Error!*ast.Expr {
        const left = try self.logicOr();
        if (self.check(.assign)) {
            const eq = self.advance();
            const value = try self.assignment();
            const lt = std.meta.activeTag(left.data);
            if (lt == .ident or lt == .index) {
                return self.newExpr(left.pos, .{ .assign = .{ .target = left, .value = value } });
            }
            self.diags.report(.err, eq.line, eq.column, "target assignment harus variabel atau elemen larik") catch return Error.OutOfMemory;
            return Error.ParseError;
        }
        // Penugasan majemuk: x += e  ->  x = x + e
        const compound: ?ast.BinaryOp = switch (self.peek().kind) {
            .plus_eq => .add,
            .minus_eq => .sub,
            .star_eq => .mul,
            .slash_eq => .div,
            .percent_eq => .mod,
            else => null,
        };
        if (compound) |op| {
            const op_tok = self.advance();
            const value = try self.assignment();
            const lt = std.meta.activeTag(left.data);
            if (lt != .ident and lt != .index) {
                self.diags.report(.err, op_tok.line, op_tok.column, "target penugasan majemuk harus variabel atau elemen larik") catch return Error.OutOfMemory;
                return Error.ParseError;
            }
            const bin = try self.newExpr(left.pos, .{ .binary = .{ .op = op, .left = left, .right = value } });
            return self.newExpr(left.pos, .{ .assign = .{ .target = left, .value = bin } });
        }
        // Increment/decrement: x++ / x--  ->  x = x + 1 / x - 1
        if (self.check(.plus_plus) or self.check(.minus_minus)) {
            const t = self.advance();
            const op: ast.BinaryOp = if (t.kind == .plus_plus) .add else .sub;
            const lt = std.meta.activeTag(left.data);
            if (lt != .ident and lt != .index) {
                self.diags.report(.err, t.line, t.column, "'++'/'--' butuh variabel atau elemen larik") catch return Error.OutOfMemory;
                return Error.ParseError;
            }
            const one = try self.newExpr(left.pos, .{ .number = "1" });
            const bin = try self.newExpr(left.pos, .{ .binary = .{ .op = op, .left = left, .right = one } });
            return self.newExpr(left.pos, .{ .assign = .{ .target = left, .value = bin } });
        }
        return left;
    }

    fn logicOr(self: *Parser) Error!*ast.Expr {
        var left = try self.logicAnd();
        while (self.check(.or_or)) {
            _ = self.advance();
            const right = try self.logicAnd();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = .@"or", .left = left, .right = right } });
        }
        return left;
    }

    fn logicAnd(self: *Parser) Error!*ast.Expr {
        var left = try self.bitOr();
        while (self.check(.and_and)) {
            _ = self.advance();
            const right = try self.bitOr();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = .@"and", .left = left, .right = right } });
        }
        return left;
    }

    fn bitOr(self: *Parser) Error!*ast.Expr {
        var left = try self.bitXor();
        while (self.check(.pipe)) {
            _ = self.advance();
            const right = try self.bitXor();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = .bit_or, .left = left, .right = right } });
        }
        return left;
    }

    fn bitXor(self: *Parser) Error!*ast.Expr {
        var left = try self.bitAnd();
        while (self.check(.caret)) {
            _ = self.advance();
            const right = try self.bitAnd();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = .bit_xor, .left = left, .right = right } });
        }
        return left;
    }

    fn bitAnd(self: *Parser) Error!*ast.Expr {
        var left = try self.equality();
        while (self.check(.amp)) {
            _ = self.advance();
            const right = try self.equality();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = .bit_and, .left = left, .right = right } });
        }
        return left;
    }

    fn equality(self: *Parser) Error!*ast.Expr {
        var left = try self.comparison();
        while (self.check(.eq) or self.check(.neq)) {
            const op = self.advance();
            const right = try self.comparison();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = mapBinary(op.kind), .left = left, .right = right } });
        }
        return left;
    }

    fn comparison(self: *Parser) Error!*ast.Expr {
        var left = try self.shift();
        while (self.check(.lt) or self.check(.gt) or self.check(.le) or self.check(.ge)) {
            const op = self.advance();
            const right = try self.shift();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = mapBinary(op.kind), .left = left, .right = right } });
        }
        return left;
    }

    fn shift(self: *Parser) Error!*ast.Expr {
        var left = try self.term();
        while (self.check(.shl) or self.check(.shr)) {
            const op = self.advance();
            const right = try self.term();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = mapBinary(op.kind), .left = left, .right = right } });
        }
        return left;
    }

    fn term(self: *Parser) Error!*ast.Expr {
        var left = try self.factor();
        while (self.check(.plus) or self.check(.minus)) {
            const op = self.advance();
            const right = try self.factor();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = mapBinary(op.kind), .left = left, .right = right } });
        }
        return left;
    }

    fn factor(self: *Parser) Error!*ast.Expr {
        var left = try self.unary();
        while (self.check(.star) or self.check(.slash) or self.check(.percent)) {
            const op = self.advance();
            const right = try self.unary();
            left = try self.newExpr(left.pos, .{ .binary = .{ .op = mapBinary(op.kind), .left = left, .right = right } });
        }
        return left;
    }

    fn unary(self: *Parser) Error!*ast.Expr {
        if (self.check(.bang) or self.check(.minus)) {
            const op = self.advance();
            const operand = try self.unary();
            const uop: ast.UnaryOp = if (op.kind == .bang) .not else .neg;
            return self.newExpr(posOf(op), .{ .unary = .{ .op = uop, .operand = operand } });
        }
        return self.call();
    }

    fn call(self: *Parser) Error!*ast.Expr {
        var expr = try self.primary();
        while (true) {
            if (self.check(.lparen)) {
                _ = self.advance();
                var args = std.array_list.Managed(*ast.Expr).init(self.arena);
                if (!self.check(.rparen)) {
                    while (true) {
                        try args.append(try self.expression());
                        if (!self.match(.comma)) break;
                    }
                }
                _ = try self.expect(.rparen, "harap ')' menutup argumen");
                expr = try self.newExpr(expr.pos, .{ .call = .{ .callee = expr, .args = try args.toOwnedSlice() } });
            } else if (self.check(.lbracket)) {
                _ = self.advance();
                const idx = try self.expression();
                _ = try self.expect(.rbracket, "harap ']' menutup indeks");
                expr = try self.newExpr(expr.pos, .{ .index = .{ .target = expr, .idx = idx } });
            } else break;
        }
        return expr;
    }

    fn primary(self: *Parser) Error!*ast.Expr {
        const t = self.peek();
        switch (t.kind) {
            .number => {
                _ = self.advance();
                return self.newExpr(posOf(t), .{ .number = t.lexeme });
            },
            .string => {
                _ = self.advance();
                return self.newExpr(posOf(t), .{ .string = try self.decodeString(t.lexeme) });
            },
            .kw_benar => {
                _ = self.advance();
                return self.newExpr(posOf(t), .{ .boolean = true });
            },
            .kw_salah => {
                _ = self.advance();
                return self.newExpr(posOf(t), .{ .boolean = false });
            },
            .kw_kosong => {
                _ = self.advance();
                return self.newExpr(posOf(t), .nil);
            },
            .identifier => {
                _ = self.advance();
                return self.newExpr(posOf(t), .{ .ident = t.lexeme });
            },
            .lparen => {
                _ = self.advance();
                const e = try self.expression();
                _ = try self.expect(.rparen, "harap ')' menutup grup ekspresi");
                return e;
            },
            .lbracket => {
                _ = self.advance();
                var elems = std.array_list.Managed(*ast.Expr).init(self.arena);
                if (!self.check(.rbracket)) {
                    while (true) {
                        try elems.append(try self.expression());
                        if (!self.match(.comma)) break;
                    }
                }
                _ = try self.expect(.rbracket, "harap ']' menutup larik");
                return self.newExpr(posOf(t), .{ .array = try elems.toOwnedSlice() });
            },
            .ty_peta => {
                // literal peta: peta{ "kunci": nilai, ... }
                _ = self.advance();
                _ = try self.expect(.lbrace, "harap '{' setelah 'peta'");
                var entries = std.array_list.Managed(ast.Expr.MapEntry).init(self.arena);
                if (!self.check(.rbrace)) {
                    while (true) {
                        const key = try self.expression();
                        _ = try self.expect(.colon, "harap ':' antara kunci dan nilai peta");
                        const value = try self.expression();
                        try entries.append(.{ .key = key, .value = value });
                        if (!self.match(.comma)) break;
                    }
                }
                _ = try self.expect(.rbrace, "harap '}' menutup literal peta");
                return self.newExpr(posOf(t), .{ .map_lit = try entries.toOwnedSlice() });
            },
            else => {
                try self.errorHere("ekspresi tidak valid");
                return Error.ParseError;
            },
        }
    }

    fn decodeString(self: *Parser, lexeme: []const u8) Error![]const u8 {
        const content = lexeme[1 .. lexeme.len - 1];
        var buf = std.array_list.Managed(u8).init(self.arena);
        var i: usize = 0;
        while (i < content.len) {
            if (content[i] == '\\' and i + 1 < content.len) {
                i += 1;
                const mapped: u8 = switch (content[i]) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '0' => 0,
                    '"' => '"',
                    '\\' => '\\',
                    else => content[i],
                };
                try buf.append(mapped);
            } else {
                try buf.append(content[i]);
            }
            i += 1;
        }
        return buf.toOwnedSlice();
    }

    fn newExpr(self: *Parser, pos: ast.Pos, data: ast.Expr.Data) Error!*ast.Expr {
        const e = try self.arena.create(ast.Expr);
        e.* = .{ .pos = pos, .data = data };
        return e;
    }

    fn newStmt(self: *Parser, pos: ast.Pos, data: ast.Stmt.Data) Error!*ast.Stmt {
        const s = try self.arena.create(ast.Stmt);
        s.* = .{ .pos = pos, .data = data };
        return s;
    }

    fn expect(self: *Parser, kind: TokenKind, message: []const u8) Error!Token {
        if (self.check(kind)) return self.advance();
        try self.errorHere(message);
        return Error.ParseError;
    }

    fn errorHere(self: *Parser, message: []const u8) Error!void {
        const t = self.peek();
        self.diags.report(.err, t.line, t.column, message) catch return Error.OutOfMemory;
    }

    fn check(self: *const Parser, kind: TokenKind) bool {
        return self.peek().kind == kind;
    }

    fn match(self: *Parser, kind: TokenKind) bool {
        if (!self.check(kind)) return false;
        _ = self.advance();
        return true;
    }

    fn advance(self: *Parser) Token {
        const t = self.peek();
        if (t.kind != .eof) self.cur += 1;
        return t;
    }

    fn peek(self: *const Parser) Token {
        return self.tokens[self.cur];
    }
};

fn posOf(t: Token) ast.Pos {
    return .{ .line = t.line, .column = t.column };
}

fn mapBinary(kind: TokenKind) ast.BinaryOp {
    return switch (kind) {
        .plus => .add,
        .minus => .sub,
        .star => .mul,
        .slash => .div,
        .percent => .mod,
        .eq => .eq,
        .neq => .neq,
        .lt => .lt,
        .gt => .gt,
        .le => .le,
        .ge => .ge,
        .and_and => .@"and",
        .or_or => .@"or",
        .amp => .bit_and,
        .pipe => .bit_or,
        .caret => .bit_xor,
        .shl => .shl,
        .shr => .shr,
        else => unreachable,
    };
}

const Lexer = @import("../lexer/lexer.zig").Lexer;

fn parseToSexpr(allocator: std.mem.Allocator, source: []const u8, diags: *Diagnostics) ![]u8 {
    var lexer = Lexer.init(source, diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), tokens, diags);

    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    try ast.dumpProgram(program, &aw.writer);
    return aw.toOwnedSlice();
}

fn expectParse(source: []const u8, expected: []const u8) !void {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    const out = try parseToSexpr(std.testing.allocator, source, &diags);
    defer std.testing.allocator.free(out);
    try std.testing.expect(!diags.hasErrors());
    try std.testing.expectEqualStrings(expected, out);
}

test "precedence aritmatika" {
    try expectParse("1 + 2 * 3;", "(+ 1 (* 2 3))\n");
    try expectParse("(1 + 2) * 3;", "(* (+ 1 2) 3)\n");
}

test "precedence logika dan perbandingan" {
    try expectParse("1 < 2 && 3 == 4 || benar;", "(|| (&& (< 1 2) (== 3 4)) benar)\n");
}

test "unary dan assignment" {
    try expectParse("-a + b;", "(+ (neg a) b)\n");
    try expectParse("x = 1 + 2;", "(= x (+ 1 2))\n");
}

test "deklarasi variabel beranotasi" {
    try expectParse("biar umur: bulat = 17;", "(biar umur :bulat 17)\n");
    try expectParse("tetap pi = 3.14;", "(tetap pi 3.14)\n");
}

test "fungsi dengan parameter dan return" {
    try expectParse(
        "fungsi tambah(a: bulat, b: bulat): bulat { kembali a + b; }",
        "(fungsi tambah ((a bulat) (b bulat)) :bulat {(kembali (+ a b))})\n",
    );
}

test "kalau lain dan pemanggilan" {
    try expectParse(
        "kalau benar { f(1); } lain { f(2); }",
        "(kalau benar {(panggil f 1)} lain {(panggil f 2)})\n",
    );
}

test "selama loop" {
    try expectParse(
        "selama n > 0 { n = n - 1; }",
        "(selama (> n 0) {(= n (- n 1))})\n",
    );
}

test "untuk loop" {
    try expectParse(
        "untuk i dari 0 sampai 5 { cetak(i); }",
        "(untuk i dari 0 sampai 5 {(panggil cetak i)})\n",
    );
}

test "larik literal dan indeks" {
    try expectParse("biar a: []bulat = [1, 2, 3];", "(biar a :[]bulat (larik 1 2 3))\n");
    try expectParse("cetak(a[0]);", "(panggil cetak (indeks a 0))\n");
}

test "penugasan elemen larik" {
    try expectParse("a[1] = 9;", "(= (indeks a 1) 9)\n");
}

test "struktur var_decl" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    var lexer = Lexer.init("biar x: bulat = 10;", &diags);
    const tokens = try lexer.tokenize(std.testing.allocator);
    defer std.testing.allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try parse(arena.allocator(), tokens, &diags);

    try std.testing.expectEqual(@as(usize, 1), program.stmts.len);
    const d = program.stmts[0].data.var_decl;
    try std.testing.expect(!d.is_const);
    try std.testing.expectEqualStrings("x", d.name);
    try std.testing.expectEqual(ast.Type.bulat, d.type_anno.?);
    try std.testing.expectEqualStrings("10", d.value.data.number);
}

test "error parsing lapor diagnostik" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    var lexer = Lexer.init("biar = 5;", &diags);
    const tokens = try lexer.tokenize(std.testing.allocator);
    defer std.testing.allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(Error.ParseError, parse(arena.allocator(), tokens, &diags));
    try std.testing.expect(diags.hasErrors());
}
