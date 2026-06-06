const std = @import("std");
const ast = @import("../parser/ast.zig");
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;
const spec = @import("../builtins/spec.zig");
const Type = ast.Type;

const VarInfo = struct {
    type: Type,
    is_const: bool,
};

const FnSig = struct {
    params: []const Type,
    ret: Type,
};

pub fn check(allocator: std.mem.Allocator, program: ast.Program, diags: *Diagnostics) !void {
    var s = Sema{
        .allocator = allocator,
        .diags = diags,
        .functions = std.StringHashMap(FnSig).init(allocator),
        .scopes = std.ArrayList(std.StringHashMap(VarInfo)).init(allocator),
        .type_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer s.deinit();

    try s.pushScope();

    for (program.stmts) |stmt| {
        if (std.meta.activeTag(stmt.data) == .fungsi_decl) {
            const f = stmt.data.fungsi_decl;
            if (s.functions.contains(f.name)) {
                try s.report(stmt.pos, "fungsi dengan nama ini sudah dideklarasikan");
            } else {
                var ptypes = try allocator.alloc(Type, f.params.len);
                for (f.params, 0..) |p, i| ptypes[i] = p.type;
                try s.functions.put(f.name, .{ .params = ptypes, .ret = f.return_type });
            }
        }
    }

    for (program.stmts) |stmt| {
        if (std.meta.activeTag(stmt.data) != .fungsi_decl) try s.checkStmt(stmt, null);
    }

    for (program.stmts) |stmt| {
        if (std.meta.activeTag(stmt.data) == .fungsi_decl) try s.checkFungsi(stmt.data.fungsi_decl);
    }
}

const Sema = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    functions: std.StringHashMap(FnSig),
    scopes: std.ArrayList(std.StringHashMap(VarInfo)),
    type_arena: std.heap.ArenaAllocator,
    loop_depth: usize = 0,

    fn deinit(self: *Sema) void {
        var it = self.functions.valueIterator();
        while (it.next()) |sig| self.allocator.free(@constCast(sig.params));
        self.functions.deinit();
        for (self.scopes.items) |*sc| sc.deinit();
        self.scopes.deinit();
        self.type_arena.deinit();
    }

    fn pushScope(self: *Sema) !void {
        try self.scopes.append(std.StringHashMap(VarInfo).init(self.allocator));
    }

    fn popScope(self: *Sema) void {
        var sc = self.scopes.pop().?;
        sc.deinit();
    }

    fn define(self: *Sema, pos: ast.Pos, name: []const u8, info: VarInfo) !void {
        var top = &self.scopes.items[self.scopes.items.len - 1];
        if (top.contains(name)) {
            try self.report(pos, "variabel sudah dideklarasikan di scope ini");
            return;
        }
        try top.put(name, info);
    }

    fn lookup(self: *Sema, name: []const u8) ?VarInfo {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].get(name)) |info| return info;
        }
        return null;
    }

    fn checkFungsi(self: *Sema, f: ast.Stmt.FungsiDecl) !void {
        try self.pushScope();
        defer self.popScope();
        for (f.params) |p| {
            try self.define(.{ .line = 0, .column = 0 }, p.name, .{ .type = p.type, .is_const = false });
        }
        try self.checkBlock(f.body, f.return_type);
    }

    fn checkBlock(self: *Sema, stmts: []*ast.Stmt, ret: ?Type) !void {
        try self.pushScope();
        defer self.popScope();
        for (stmts) |stmt| try self.checkStmt(stmt, ret);
    }

    fn checkStmt(self: *Sema, stmt: *ast.Stmt, ret: ?Type) anyerror!void {
        switch (stmt.data) {
            .var_decl => |d| {
                const vt = try self.checkExpr(d.value);
                var declared = d.type_anno;
                if (d.type_anno) |anno| {
                    if (vt) |found| {
                        if (!found.eql(anno)) try self.report(stmt.pos, "tipe nilai tidak cocok dengan anotasi");
                    }
                } else {
                    declared = vt;
                }
                if (declared) |t| {
                    try self.define(stmt.pos, d.name, .{ .type = t, .is_const = d.is_const });
                }
            },
            .fungsi_decl => |d| try self.checkFungsi(d),
            .expr_stmt => |e| _ = try self.checkExpr(e),
            .if_stmt => |d| {
                const c = try self.checkExpr(d.cond);
                if (c) |t| if (!t.eql(.bool)) try self.report(stmt.pos, "kondisi 'kalau' harus bertipe bool");
                try self.checkBlock(d.then_block, ret);
                if (d.else_branch) |e| try self.checkStmt(e, ret);
            },
            .while_stmt => |d| {
                const c = try self.checkExpr(d.cond);
                if (c) |t| if (!t.eql(.bool)) try self.report(stmt.pos, "kondisi 'selama' harus bertipe bool");
                self.loop_depth += 1;
                try self.checkBlock(d.body, ret);
                self.loop_depth -= 1;
            },
            .for_stmt => |d| {
                const st = try self.checkExpr(d.start);
                if (st) |t| if (!t.eql(.bulat)) try self.report(stmt.pos, "nilai awal 'untuk' harus bertipe bulat");
                const et = try self.checkExpr(d.end);
                if (et) |t| if (!t.eql(.bulat)) try self.report(stmt.pos, "nilai akhir 'untuk' harus bertipe bulat");
                try self.pushScope();
                defer self.popScope();
                try self.define(stmt.pos, d.var_name, .{ .type = .bulat, .is_const = false });
                self.loop_depth += 1;
                try self.checkBlock(d.body, ret);
                self.loop_depth -= 1;
            },
            .foreach_stmt => |d| {
                const it = try self.checkExpr(d.iter);
                var elem: Type = .dinamis;
                if (it) |t| {
                    if (std.meta.activeTag(t) == .array) {
                        elem = t.array.*;
                    } else if (std.meta.activeTag(t) != .dinamis) {
                        try self.report(stmt.pos, "'untuk x dari <larik>' butuh larik");
                    }
                }
                try self.pushScope();
                defer self.popScope();
                try self.define(stmt.pos, d.var_name, .{ .type = elem, .is_const = false });
                self.loop_depth += 1;
                try self.checkBlock(d.body, ret);
                self.loop_depth -= 1;
            },
            .try_stmt => |d| {
                try self.checkBlock(d.body, ret);
                try self.pushScope();
                defer self.popScope();
                try self.define(stmt.pos, d.err_name, .{ .type = .teks, .is_const = false });
                try self.checkBlock(d.handler, ret);
            },
            .break_stmt => {
                if (self.loop_depth == 0) try self.report(stmt.pos, "'henti' hanya boleh di dalam loop");
            },
            .continue_stmt => {
                if (self.loop_depth == 0) try self.report(stmt.pos, "'lanjut' hanya boleh di dalam loop");
            },
            .return_stmt => |maybe| {
                if (ret == null) {
                    try self.report(stmt.pos, "'kembali' hanya boleh di dalam fungsi");
                    return;
                }
                if (maybe) |e| {
                    const rt = try self.checkExpr(e);
                    if (rt) |t| if (!t.eql(ret.?)) try self.report(stmt.pos, "tipe nilai 'kembali' tidak cocok dengan tipe kembalian fungsi");
                } else if (!ret.?.eql(.kosong)) {
                    try self.report(stmt.pos, "fungsi ini harus mengembalikan nilai");
                }
            },
            .block => |stmts| try self.checkBlock(stmts, ret),
        }
    }

    fn checkExpr(self: *Sema, expr: *ast.Expr) anyerror!?Type {
        switch (expr.data) {
            .number => |s| return if (std.mem.indexOfScalar(u8, s, '.') != null) .desimal else .bulat,
            .string => return .teks,
            .boolean => return .bool,
            .nil => return .kosong,
            .ident => |name| {
                if (self.lookup(name)) |info| return info.type;
                // Nama fungsi top-level dipakai sebagai nilai (first-class) -> tipe fungsi.
                if (self.functions.contains(name)) return .fungsi;
                try self.report(expr.pos, "nama tidak dikenal");
                return null;
            },
            .unary => |u| {
                const t = try self.checkExpr(u.operand);
                if (t == null) return null;
                switch (u.op) {
                    .neg => {
                        if (!isNumeric(t.?)) {
                            try self.report(expr.pos, "operator '-' butuh operand bulat/desimal");
                            return null;
                        }
                        return t.?;
                    },
                    .not => {
                        if (!t.?.eql(.bool)) {
                            try self.report(expr.pos, "operator '!' butuh operand bool");
                            return null;
                        }
                        return .bool;
                    },
                }
            },
            .binary => |b| return self.checkBinary(expr, b),
            .call => |c| return self.checkCall(expr, c),
            .assign => |a| {
                const vt = try self.checkExpr(a.value);
                switch (a.target.data) {
                    .ident => |name| {
                        const info = self.lookup(name) orelse {
                            try self.report(expr.pos, "nama tidak dikenal");
                            return null;
                        };
                        if (info.is_const) try self.report(expr.pos, "tidak boleh mengubah nilai konstanta 'tetap'");
                        if (vt) |t| if (!t.eql(info.type)) try self.report(expr.pos, "tipe nilai tidak cocok dengan tipe variabel");
                        return info.type;
                    },
                    .index => {
                        const et = try self.checkExpr(a.target);
                        if (et) |elem| if (vt) |v| if (!v.eql(elem)) try self.report(expr.pos, "tipe nilai tidak cocok dengan tipe elemen larik");
                        return et;
                    },
                    else => {
                        try self.report(expr.pos, "target assignment tidak valid");
                        return null;
                    },
                }
            },
            .array => |elems| {
                if (elems.len == 0) {
                    // Larik kosong: elemen bertipe dinamis (cocok dengan []T mana pun).
                    const el = try self.type_arena.allocator().create(Type);
                    el.* = .dinamis;
                    return .{ .array = el };
                }
                const first = try self.checkExpr(elems[0]);
                if (first == null) return null;
                for (elems[1..]) |e| {
                    const et = try self.checkExpr(e);
                    if (et) |t| if (!t.eql(first.?)) {
                        try self.report(expr.pos, "semua elemen larik harus bertipe sama");
                        return null;
                    };
                }
                const el = try self.type_arena.allocator().create(Type);
                el.* = first.?;
                return .{ .array = el };
            },
            .index => |ix| {
                const tt = try self.checkExpr(ix.target);
                if (tt == null) return null;
                const it = try self.checkExpr(ix.idx);
                if (std.meta.activeTag(tt.?) == .peta) {
                    if (it) |t| if (!t.eql(.teks)) try self.report(expr.pos, "kunci peta harus bertipe teks");
                    return .dinamis; // nilai peta bisa tipe apa pun
                }
                if (std.meta.activeTag(tt.?) != .array) {
                    try self.report(expr.pos, "hanya larik atau peta yang bisa diindeks");
                    return null;
                }
                if (it) |t| if (!t.eql(.bulat)) try self.report(expr.pos, "indeks larik harus bertipe bulat");
                return tt.?.array.*;
            },
            .map_lit => |entries| {
                for (entries) |e| {
                    const kt = try self.checkExpr(e.key);
                    if (kt) |t| if (!t.eql(.teks)) try self.report(expr.pos, "kunci peta harus bertipe teks");
                    _ = try self.checkExpr(e.value); // nilai bisa tipe apa pun
                }
                return .peta;
            },
        }
    }

    fn checkBinary(self: *Sema, expr: *ast.Expr, b: ast.Expr.Binary) anyerror!?Type {
        const lt = try self.checkExpr(b.left);
        const rt = try self.checkExpr(b.right);
        if (lt == null or rt == null) return null;
        const l = lt.?;
        const r = rt.?;
        // Operand dinamis: lewati pengecekan ketat (dispatch dinamis).
        if (std.meta.activeTag(l) == .dinamis or std.meta.activeTag(r) == .dinamis) {
            return switch (b.op) {
                .lt, .gt, .le, .ge, .eq, .neq, .@"and", .@"or" => .bool,
                else => .dinamis,
            };
        }
        switch (b.op) {
            .add, .sub, .mul, .div, .mod => {
                if (b.op == .add and std.meta.activeTag(l) == .teks and std.meta.activeTag(r) == .teks) return .teks;
                if (l.isNumeric() and l.eql(r)) return l;
                try self.report(expr.pos, "operand aritmatika harus dua angka bertipe sama (atau dua teks untuk '+')");
                return null;
            },
            .lt, .gt, .le, .ge => {
                if (l.isNumeric() and l.eql(r)) return .bool;
                try self.report(expr.pos, "operand perbandingan harus dua angka bertipe sama");
                return null;
            },
            .eq, .neq => {
                if (l.eql(r)) return .bool;
                try self.report(expr.pos, "operand '==' / '!=' harus bertipe sama");
                return null;
            },
            .@"and", .@"or" => {
                if (std.meta.activeTag(l) == .bool and std.meta.activeTag(r) == .bool) return .bool;
                try self.report(expr.pos, "operand '&&' / '||' harus bertipe bool");
                return null;
            },
            .bit_and, .bit_or, .bit_xor, .shl, .shr => {
                if (std.meta.activeTag(l) == .bulat and std.meta.activeTag(r) == .bulat) return .bulat;
                try self.report(expr.pos, "operand bitwise (& | ^ << >>) harus bertipe bulat");
                return null;
            },
        }
    }

    fn checkCall(self: *Sema, expr: *ast.Expr, c: ast.Expr.Call) anyerror!?Type {
        // Callee bukan ident (mis. larik[i]() atau peta-akses) -> panggilan tak langsung.
        if (std.meta.activeTag(c.callee.data) != .ident) {
            const ct = try self.checkExpr(c.callee);
            if (ct) |t| if (std.meta.activeTag(t) != .fungsi and std.meta.activeTag(t) != .dinamis) {
                try self.report(expr.pos, "hanya nilai fungsi yang bisa dipanggil");
                return null;
            };
            for (c.args) |arg| _ = try self.checkExpr(arg);
            return .dinamis;
        }
        const name = c.callee.data.ident;

        // Variabel lokal/global bertipe fungsi dipanggil -> panggilan tak langsung.
        if (self.lookup(name)) |info| {
            if (std.meta.activeTag(info.type) == .fungsi or std.meta.activeTag(info.type) == .dinamis) {
                for (c.args) |arg| _ = try self.checkExpr(arg);
                return .dinamis;
            }
        }

        // dorong polimorfik: (larik T, T) -> larik T (runtime sudah generik).
        if (std.mem.eql(u8, name, "dorong")) {
            if (c.args.len != 2) {
                try self.report(expr.pos, "'dorong' butuh 2 argumen (larik, item)");
                return null;
            }
            const at = try self.checkExpr(c.args[0]);
            _ = try self.checkExpr(c.args[1]);
            if (at) |t| {
                if (std.meta.activeTag(t) != .array) {
                    try self.report(expr.pos, "'dorong' butuh argumen pertama larik");
                    return null;
                }
                return t;
            }
            return null;
        }

        if (std.mem.eql(u8, name, "cetak")) {
            if (c.args.len != 1) {
                try self.report(expr.pos, "'cetak' butuh tepat 1 argumen");
            } else {
                _ = try self.checkExpr(c.args[0]);
            }
            return .kosong;
        }

        if (std.mem.eql(u8, name, "panjang")) {
            if (c.args.len != 1) {
                try self.report(expr.pos, "'panjang' butuh tepat 1 argumen");
            } else {
                const at = try self.checkExpr(c.args[0]);
                if (at) |t| if (std.meta.activeTag(t) != .array) try self.report(expr.pos, "'panjang' butuh argumen larik");
            }
            return .bulat;
        }

        if (spec.indexOf(name)) |id| {
            const bs = spec.list[id];
            if (c.args.len != bs.params.len) {
                try self.report(expr.pos, "jumlah argumen builtin tidak sesuai");
            } else {
                for (c.args, bs.params) |arg, ptype| {
                    const at = try self.checkExpr(arg);
                    if (at) |t| if (!t.eql(ptype)) try self.report(arg.pos, "tipe argumen builtin tidak cocok");
                }
            }
            return bs.ret;
        }

        const sig = self.functions.get(name) orelse {
            try self.report(expr.pos, "fungsi tidak dikenal");
            return null;
        };
        if (c.args.len != sig.params.len) {
            try self.report(expr.pos, "jumlah argumen tidak sesuai dengan parameter fungsi");
        } else {
            for (c.args, sig.params) |arg, ptype| {
                const at = try self.checkExpr(arg);
                if (at) |t| if (!t.eql(ptype)) try self.report(arg.pos, "tipe argumen tidak cocok dengan parameter");
            }
        }
        return sig.ret;
    }

    fn report(self: *Sema, pos: ast.Pos, message: []const u8) !void {
        try self.diags.report(.err, pos.line, pos.column, message);
    }
};

fn isNumeric(t: Type) bool {
    return t.isNumeric();
}

const Lexer = @import("../lexer/lexer.zig").Lexer;
const parser = @import("../parser/parser.zig");

fn analyze(allocator: std.mem.Allocator, source: []const u8, diags: *Diagnostics) !void {
    var lexer = Lexer.init(source, diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = try parser.parse(arena.allocator(), tokens, diags);
    try check(allocator, program, diags);
}

test "program valid lolos sema" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator,
        \\fungsi tambah(a: bulat, b: bulat): bulat { kembali a + b; }
        \\biar x: bulat = tambah(1, 2);
        \\kalau x > 0 { cetak("ok"); }
    , &diags);
    try std.testing.expect(!diags.hasErrors());
}

test "tipe tidak cocok ketahuan" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "biar x: bulat = \"halo\";", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "variabel tidak dikenal ketahuan" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "biar x: bulat = y + 1;", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "ubah konstanta ditolak" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "tetap pi = 3.14; pi = 4.0;", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "kondisi non-bool ditolak" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "biar x: bulat = 1; kalau x { cetak(\"x\"); }", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "untuk dengan batas non-bulat ditolak" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "untuk i dari 0 sampai \"x\" { cetak(i); }", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "var iterasi untuk terlihat di body" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "untuk i dari 0 sampai 3 { cetak(i); }", &diags);
    try std.testing.expect(!diags.hasErrors());
}

test "penugasan elemen larik tipe salah ditolak" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator, "biar a: []bulat = [1, 2]; a[0] = \"x\";", &diags);
    try std.testing.expect(diags.hasErrors());
}

test "argumen salah jumlah ditolak" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();
    try analyze(std.testing.allocator,
        \\fungsi f(a: bulat): bulat { kembali a; }
        \\biar y: bulat = f(1, 2);
    , &diags);
    try std.testing.expect(diags.hasErrors());
}
