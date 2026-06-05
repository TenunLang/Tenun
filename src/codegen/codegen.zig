const std = @import("std");
const ast = @import("../parser/ast.zig");
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;
const Type = ast.Type;

pub const Error = error{Unsupported} || std.mem.Allocator.Error;

const FnSig = struct {
    params: []const Type,
    ret: Type,
};

pub fn generate(allocator: std.mem.Allocator, program: ast.Program, diags: *Diagnostics) ![]u8 {
    var g = Codegen{
        .allocator = allocator,
        .diags = diags,
        .out = std.ArrayList(u8).init(allocator),
        .functions = std.StringHashMap(FnSig).init(allocator),
        .globals = std.StringHashMap(Type).init(allocator),
        .scopes = std.ArrayList(std.StringHashMap(Type)).init(allocator),
        .type_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer g.deinit();
    errdefer g.out.deinit();

    try g.run(program);
    return g.out.toOwnedSlice();
}

const Codegen = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: std.ArrayList(u8),
    functions: std.StringHashMap(FnSig),
    globals: std.StringHashMap(Type),
    scopes: std.ArrayList(std.StringHashMap(Type)),
    type_arena: std.heap.ArenaAllocator,
    depth: i32 = 0,

    fn deinit(self: *Codegen) void {
        var it = self.functions.valueIterator();
        while (it.next()) |s| self.allocator.free(@constCast(s.params));
        self.functions.deinit();
        self.globals.deinit();
        for (self.scopes.items) |*sc| sc.deinit();
        self.scopes.deinit();
        self.type_arena.deinit();
    }

    fn run(self: *Codegen, program: ast.Program) Error!void {
        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .fungsi_decl) {
                const f = s.data.fungsi_decl;
                var ptypes = try self.allocator.alloc(Type, f.params.len);
                for (f.params, 0..) |p, i| ptypes[i] = p.type;
                try self.functions.put(f.name, .{ .params = ptypes, .ret = f.return_type });
            }
        }

        try self.w(
            \\#include <stdio.h>
            \\#include <stdint.h>
            \\#include <string.h>
            \\#include <stdlib.h>
            \\#include <math.h>
            \\typedef struct { void* data; int64_t len; } TenunArr;
            \\static const char* tenun_concat(const char* a, const char* b){size_t la=strlen(a),lb=strlen(b);char* r=(char*)malloc(la+lb+1);memcpy(r,a,la);memcpy(r+la,b,lb+1);return r;}
            \\
        );

        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .var_decl) {
                const d = s.data.var_decl;
                const t = if (d.type_anno) |a| a else try self.typeOf(d.value);
                try self.globals.put(d.name, t);
                try self.w("static ");
                try self.w(cType(t) catch return self.unsupported(s.pos, "tipe global tidak didukung di codegen native"));
                try self.w(" t_");
                try self.w(d.name);
                try self.w(";\n");
            }
        }

        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .fungsi_decl) {
                const f = s.data.fungsi_decl;
                try self.fnSignature(f);
                try self.w(";\n");
            }
        }

        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .fungsi_decl) try self.fnDef(s.data.fungsi_decl);
        }

        try self.w("int main(void){\n");
        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) != .fungsi_decl) try self.stmt(s);
        }
        try self.w("return 0;\n}\n");
    }

    fn fnSignature(self: *Codegen, f: ast.Stmt.FungsiDecl) Error!void {
        try self.w(cType(f.return_type) catch return self.unsupported(.{ .line = 0, .column = 0 }, "tipe kembalian tidak didukung"));
        try self.w(" tf_");
        try self.w(f.name);
        try self.w("(");
        if (f.params.len == 0) try self.w("void");
        for (f.params, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.w(cType(p.type) catch return self.unsupported(.{ .line = 0, .column = 0 }, "tipe parameter tidak didukung"));
            try self.w(" t_");
            try self.w(p.name);
        }
        try self.w(")");
    }

    fn fnDef(self: *Codegen, f: ast.Stmt.FungsiDecl) Error!void {
        try self.fnSignature(f);
        try self.w("{\n");
        try self.pushScope();
        self.depth = 1;
        for (f.params) |p| try self.define(p.name, p.type);
        for (f.body) |s| try self.stmt(s);
        self.depth = 0;
        self.popScope();
        try self.w("}\n");
    }

    fn block(self: *Codegen, stmts: []*ast.Stmt) Error!void {
        try self.w("{\n");
        try self.pushScope();
        self.depth += 1;
        for (stmts) |s| try self.stmt(s);
        self.depth -= 1;
        self.popScope();
        try self.w("}\n");
    }

    fn stmt(self: *Codegen, s: *ast.Stmt) Error!void {
        switch (s.data) {
            .var_decl => |d| {
                const t = if (d.type_anno) |a| a else try self.typeOf(d.value);
                if (self.depth == 0) {
                    try self.w("t_");
                    try self.w(d.name);
                    try self.w(" = ");
                    try self.expr(d.value);
                    try self.w(";\n");
                } else {
                    try self.define(d.name, t);
                    try self.w(cType(t) catch return self.unsupported(s.pos, "tipe variabel tidak didukung"));
                    try self.w(" t_");
                    try self.w(d.name);
                    try self.w(" = ");
                    try self.expr(d.value);
                    try self.w(";\n");
                }
            },
            .fungsi_decl => {},
            .expr_stmt => |e| {
                if (std.meta.activeTag(e.data) == .call and std.meta.activeTag(e.data.call.callee.data) == .ident and std.mem.eql(u8, e.data.call.callee.data.ident, "cetak")) {
                    try self.emitCetak(e.data.call.args[0]);
                } else {
                    try self.expr(e);
                    try self.w(";\n");
                }
            },
            .block => |stmts| try self.block(stmts),
            .if_stmt => |d| {
                try self.w("if (");
                try self.expr(d.cond);
                try self.w(") ");
                try self.block(d.then_block);
                if (d.else_branch) |e| {
                    try self.w("else ");
                    try self.stmt(e);
                }
            },
            .while_stmt => |d| {
                try self.w("while (");
                try self.expr(d.cond);
                try self.w(") ");
                try self.block(d.body);
            },
            .for_stmt => |d| {
                try self.pushScope();
                self.depth += 1;
                try self.define(d.var_name, .bulat);
                try self.w("for (int64_t t_");
                try self.w(d.var_name);
                try self.w(" = ");
                try self.expr(d.start);
                try self.w("; t_");
                try self.w(d.var_name);
                try self.w(" < ");
                try self.expr(d.end);
                try self.w("; t_");
                try self.w(d.var_name);
                try self.w("++) {\n");
                for (d.body) |b| try self.stmt(b);
                try self.w("}\n");
                self.depth -= 1;
                self.popScope();
            },
            .return_stmt => |maybe| {
                if (maybe) |e| {
                    try self.w("return ");
                    try self.expr(e);
                    try self.w(";\n");
                } else try self.w("return;\n");
            },
        }
    }

    fn emitCetak(self: *Codegen, arg: *ast.Expr) Error!void {
        const t = try self.typeOf(arg);
        switch (t) {
            .bulat => {
                try self.w("printf(\"%lld\\n\", (long long)(");
                try self.expr(arg);
                try self.w("));\n");
            },
            .desimal => {
                try self.w("printf(\"%g\\n\", (double)(");
                try self.expr(arg);
                try self.w("));\n");
            },
            .bool => {
                try self.w("printf(\"%s\\n\", (");
                try self.expr(arg);
                try self.w(") ? \"benar\" : \"salah\");\n");
            },
            .teks => {
                try self.w("printf(\"%s\\n\", ");
                try self.expr(arg);
                try self.w(");\n");
            },
            .array => |el| {
                const inner: []const u8 = switch (el.*) {
                    .bulat => "printf(\"%lld\", (long long)((int64_t*)_a.data)[_i]);",
                    .desimal => "printf(\"%g\", ((double*)_a.data)[_i]);",
                    .bool => "printf(\"%s\", (((int*)_a.data)[_i]) ? \"benar\" : \"salah\");",
                    .teks => "printf(\"%s\", ((const char**)_a.data)[_i]);",
                    .array, .kosong => return self.unsupported(arg.pos, "cetak larik bersarang belum didukung di codegen native (pakai VM)"),
                };
                try self.w("{ TenunArr _a = ");
                try self.expr(arg);
                try self.w("; printf(\"[\"); for (int64_t _i = 0; _i < _a.len; _i++) { if (_i) printf(\", \"); ");
                try self.w(inner);
                try self.w(" } printf(\"]\\n\"); }\n");
            },
            else => return self.unsupported(arg.pos, "cetak untuk tipe ini belum didukung di codegen native"),
        }
    }

    fn expr(self: *Codegen, e: *ast.Expr) Error!void {
        switch (e.data) {
            .number => |s| try self.w(s),
            .string => |s| try self.w(s),
            .boolean => |b| try self.w(if (b) "1" else "0"),
            .nil => try self.w("0"),
            .ident => |name| {
                try self.w("t_");
                try self.w(name);
            },
            .unary => |u| {
                try self.w(if (u.op == .neg) "(-(" else "(!(");
                try self.expr(u.operand);
                try self.w("))");
            },
            .binary => |b| {
                if (b.op == .add and std.meta.activeTag(try self.typeOf(b.left)) == .teks) {
                    try self.w("tenun_concat(");
                    try self.expr(b.left);
                    try self.w(", ");
                    try self.expr(b.right);
                    try self.w(")");
                    return;
                }
                if (b.op == .mod and std.meta.activeTag(try self.typeOf(b.left)) == .desimal) {
                    try self.w("fmod(");
                    try self.expr(b.left);
                    try self.w(", ");
                    try self.expr(b.right);
                    try self.w(")");
                    return;
                }
                try self.w("(");
                try self.expr(b.left);
                try self.w(cBinOp(b.op));
                try self.expr(b.right);
                try self.w(")");
            },
            .call => |c| {
                const name = c.callee.data.ident;
                if (std.mem.eql(u8, name, "panjang")) {
                    try self.w("(");
                    try self.expr(c.args[0]);
                    try self.w(").len");
                    return;
                }
                if (std.mem.eql(u8, name, "cetak")) {
                    return self.unsupported(e.pos, "'cetak' hanya didukung sebagai pernyataan di codegen native");
                }
                try self.w("tf_");
                try self.w(name);
                try self.w("(");
                for (c.args, 0..) |a, i| {
                    if (i > 0) try self.w(", ");
                    try self.expr(a);
                }
                try self.w(")");
            },
            .assign => |a| {
                switch (a.target.data) {
                    .ident => |name| {
                        try self.w("(t_");
                        try self.w(name);
                        try self.w(" = ");
                        try self.expr(a.value);
                        try self.w(")");
                    },
                    .index => |ix| {
                        const et = try self.typeOf(a.target);
                        try self.w("(((");
                        try self.w(cType(et) catch return self.unsupported(e.pos, "tipe elemen larik tidak didukung"));
                        try self.w("*)(");
                        try self.expr(ix.target);
                        try self.w(").data)[");
                        try self.expr(ix.idx);
                        try self.w("] = ");
                        try self.expr(a.value);
                        try self.w(")");
                    },
                    else => return self.unsupported(e.pos, "target penugasan tidak didukung"),
                }
            },
            .array => |elems| {
                if (elems.len == 0) return self.unsupported(e.pos, "larik kosong belum didukung di codegen native");
                const et = try self.typeOf(elems[0]);
                const cet = cType(et) catch return self.unsupported(e.pos, "tipe elemen larik tidak didukung");
                try self.w("({ ");
                try self.w(cet);
                try self.w("* _arr = (");
                try self.w(cet);
                try self.w("*)malloc(");
                try self.wInt(elems.len);
                try self.w(" * sizeof(");
                try self.w(cet);
                try self.w(")); ");
                for (elems, 0..) |el, i| {
                    try self.w("_arr[");
                    try self.wInt(i);
                    try self.w("] = ");
                    try self.expr(el);
                    try self.w("; ");
                }
                try self.w("(TenunArr){ .data = (void*)_arr, .len = ");
                try self.wInt(elems.len);
                try self.w(" }; })");
            },
            .index => |ix| {
                const et = try self.typeOf(e);
                try self.w("((");
                try self.w(cType(et) catch return self.unsupported(e.pos, "tipe elemen larik tidak didukung"));
                try self.w("*)(");
                try self.expr(ix.target);
                try self.w(").data)[");
                try self.expr(ix.idx);
                try self.w("]");
            },
        }
    }

    fn wInt(self: *Codegen, n: usize) Error!void {
        var buf: [24]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
        try self.w(s);
    }

    fn typeOf(self: *Codegen, e: *ast.Expr) Error!Type {
        return switch (e.data) {
            .number => |s| if (std.mem.indexOfScalar(u8, s, '.') != null) .desimal else .bulat,
            .string => .teks,
            .boolean => .bool,
            .nil => .kosong,
            .ident => |name| self.lookup(name) orelse .kosong,
            .unary => |u| self.typeOf(u.operand),
            .binary => |b| switch (b.op) {
                .eq, .neq, .lt, .gt, .le, .ge, .@"and", .@"or" => .bool,
                else => self.typeOf(b.left),
            },
            .call => |c| blk: {
                const name = c.callee.data.ident;
                if (std.mem.eql(u8, name, "panjang")) break :blk .bulat;
                if (self.functions.get(name)) |sig| break :blk sig.ret;
                break :blk .kosong;
            },
            .assign => |a| self.typeOf(a.value),
            .array => |elems| blk: {
                if (elems.len == 0) break :blk .kosong;
                const el = try self.type_arena.allocator().create(Type);
                el.* = try self.typeOf(elems[0]);
                break :blk .{ .array = el };
            },
            .index => |ix| blk: {
                const tt = try self.typeOf(ix.target);
                break :blk if (std.meta.activeTag(tt) == .array) tt.array.* else .kosong;
            },
        };
    }

    fn define(self: *Codegen, name: []const u8, t: Type) Error!void {
        try self.scopes.items[self.scopes.items.len - 1].put(name, t);
    }
    fn lookup(self: *Codegen, name: []const u8) ?Type {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].get(name)) |t| return t;
        }
        return self.globals.get(name);
    }
    fn pushScope(self: *Codegen) Error!void {
        try self.scopes.append(std.StringHashMap(Type).init(self.allocator));
    }
    fn popScope(self: *Codegen) void {
        var sc = self.scopes.pop().?;
        sc.deinit();
    }

    fn w(self: *Codegen, s: []const u8) Error!void {
        try self.out.appendSlice(s);
    }
    fn unsupported(self: *Codegen, pos: ast.Pos, msg: []const u8) Error {
        self.diags.report(.err, pos.line, pos.column, msg) catch {};
        return Error.Unsupported;
    }
};

fn cType(t: Type) ![]const u8 {
    return switch (t) {
        .bulat => "int64_t",
        .desimal => "double",
        .teks => "const char*",
        .bool => "int",
        .kosong => "void",
        .array => "TenunArr",
    };
}

fn cBinOp(op: ast.BinaryOp) []const u8 {
    return switch (op) {
        .add => " + ",
        .sub => " - ",
        .mul => " * ",
        .div => " / ",
        .mod => " % ",
        .eq => " == ",
        .neq => " != ",
        .lt => " < ",
        .gt => " > ",
        .le => " <= ",
        .ge => " >= ",
        .@"and" => " && ",
        .@"or" => " || ",
    };
}

test "codegen menghasilkan C untuk program skalar" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const Lexer = @import("../lexer/lexer.zig").Lexer;
    const parser = @import("../parser/parser.zig");
    const sema = @import("../sema/sema.zig");

    const src =
        \\fungsi tambah(a: bulat, b: bulat): bulat { kembali a + b; }
        \\biar x: bulat = tambah(2, 3);
        \\cetak(x);
    ;
    var lexer = Lexer.init(src, &diags);
    const tokens = try lexer.tokenize(std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try parser.parse(arena.allocator(), tokens, &diags);
    try sema.check(std.testing.allocator, program, &diags);
    try std.testing.expect(!diags.hasErrors());

    const c = try generate(std.testing.allocator, program, &diags);
    defer std.testing.allocator.free(c);

    try std.testing.expect(std.mem.indexOf(u8, c, "int64_t tf_tambah(int64_t t_a, int64_t t_b)") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "return (t_a + t_b);") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "printf(\"%lld\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "int main(void)") != null);
}

test "codegen mendukung larik" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    const Lexer = @import("../lexer/lexer.zig").Lexer;
    const parser = @import("../parser/parser.zig");
    const sema = @import("../sema/sema.zig");

    const src =
        \\biar a: []bulat = [10, 20, 30];
        \\a[1] = 99;
        \\cetak(a[1]);
        \\cetak(panjang(a));
    ;
    var lexer = Lexer.init(src, &diags);
    const tokens = try lexer.tokenize(std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try parser.parse(arena.allocator(), tokens, &diags);
    try sema.check(std.testing.allocator, program, &diags);
    try std.testing.expect(!diags.hasErrors());

    const c = try generate(std.testing.allocator, program, &diags);
    defer std.testing.allocator.free(c);

    try std.testing.expect(std.mem.indexOf(u8, c, "TenunArr t_a;") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "(TenunArr){ .data") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, ").len") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "((int64_t*)(t_a).data)[1] = 99") != null);
}
