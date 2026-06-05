const std = @import("std");
const ast = @import("../parser/ast.zig");
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;

pub const Value = union(enum) {
    bulat: i64,
    desimal: f64,
    teks: []const u8,
    bool: bool,
    kosong,
    array: []Value,
};

const Scope = std.StringHashMap(Value);

pub const Error = anyerror;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: std.io.AnyWriter,
    functions: std.StringHashMap(*ast.Stmt),
    global: Scope,
    locals: std.ArrayList(Scope),
    vals: std.heap.ArenaAllocator,
    returning: bool = false,
    ret_value: Value = .kosong,

    pub fn init(allocator: std.mem.Allocator, diags: *Diagnostics, out: std.io.AnyWriter) Interpreter {
        return .{
            .allocator = allocator,
            .diags = diags,
            .out = out,
            .functions = std.StringHashMap(*ast.Stmt).init(allocator),
            .global = Scope.init(allocator),
            .locals = std.ArrayList(Scope).init(allocator),
            .vals = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.functions.deinit();
        self.global.deinit();
        for (self.locals.items) |*sc| sc.deinit();
        self.locals.deinit();
        self.vals.deinit();
    }

    pub fn run(self: *Interpreter, program: ast.Program) Error!void {
        for (program.stmts) |stmt| {
            if (std.meta.activeTag(stmt.data) == .fungsi_decl) {
                try self.functions.put(stmt.data.fungsi_decl.name, stmt);
            }
        }
        for (program.stmts) |stmt| {
            if (std.meta.activeTag(stmt.data) != .fungsi_decl) {
                try self.exec(stmt);
                if (self.returning) break;
            }
        }
    }

    fn exec(self: *Interpreter, stmt: *ast.Stmt) Error!void {
        switch (stmt.data) {
            .var_decl => |d| {
                const v = try self.eval(d.value);
                try self.define(d.name, v);
            },
            .fungsi_decl => {},
            .expr_stmt => |e| _ = try self.eval(e),
            .if_stmt => |d| {
                const c = try self.eval(d.cond);
                if (c.bool) {
                    try self.execBlock(d.then_block);
                } else if (d.else_branch) |e| {
                    try self.exec(e);
                }
            },
            .while_stmt => |d| {
                while ((try self.eval(d.cond)).bool) {
                    try self.execBlock(d.body);
                    if (self.returning) break;
                }
            },
            .for_stmt => |d| {
                const start_v = try self.eval(d.start);
                const end_v = try self.eval(d.end);
                try self.locals.append(Scope.init(self.allocator));
                defer {
                    var sc = self.locals.pop().?;
                    sc.deinit();
                }
                const loop_idx = self.locals.items.len - 1;
                var i = start_v.bulat;
                while (i < end_v.bulat) : (i += 1) {
                    try self.locals.items[loop_idx].put(d.var_name, .{ .bulat = i });
                    try self.execBlock(d.body);
                    if (self.returning) break;
                }
            },
            .return_stmt => |maybe| {
                self.ret_value = if (maybe) |e| try self.eval(e) else .kosong;
                self.returning = true;
            },
            .block => |stmts| try self.execBlock(stmts),
        }
    }

    fn execBlock(self: *Interpreter, stmts: []*ast.Stmt) Error!void {
        try self.locals.append(Scope.init(self.allocator));
        defer {
            var sc = self.locals.pop().?;
            sc.deinit();
        }
        for (stmts) |stmt| {
            try self.exec(stmt);
            if (self.returning) break;
        }
    }

    fn eval(self: *Interpreter, expr: *ast.Expr) Error!Value {
        switch (expr.data) {
            .number => |s| {
                if (std.mem.indexOfScalar(u8, s, '.') != null) {
                    return .{ .desimal = std.fmt.parseFloat(f64, s) catch 0 };
                }
                return .{ .bulat = std.fmt.parseInt(i64, s, 10) catch 0 };
            },
            .string => |s| return .{ .teks = s[1 .. s.len - 1] },
            .boolean => |b| return .{ .bool = b },
            .nil => return .kosong,
            .ident => |name| return self.get(name).?,
            .unary => |u| {
                const v = try self.eval(u.operand);
                return switch (u.op) {
                    .neg => switch (v) {
                        .bulat => .{ .bulat = -v.bulat },
                        .desimal => .{ .desimal = -v.desimal },
                        else => unreachable,
                    },
                    .not => .{ .bool = !v.bool },
                };
            },
            .binary => |b| return self.evalBinary(expr, b),
            .call => |c| return self.evalCall(c),
            .assign => |a| {
                const v = try self.eval(a.value);
                switch (a.target.data) {
                    .ident => |name| _ = self.set(name, v),
                    .index => |ix| {
                        const arr_v = try self.eval(ix.target);
                        const idx = try self.eval(ix.idx);
                        if (idx.bulat < 0 or idx.bulat >= arr_v.array.len) {
                            return self.runtimeError(ix.target.pos, "indeks larik di luar batas");
                        }
                        arr_v.array[@intCast(idx.bulat)] = v;
                    },
                    else => {},
                }
                return v;
            },
            .array => |elems| {
                const arr = try self.vals.allocator().alloc(Value, elems.len);
                for (elems, 0..) |e, i| arr[i] = try self.eval(e);
                return .{ .array = arr };
            },
            .index => |ix| {
                const target = try self.eval(ix.target);
                const idx = try self.eval(ix.idx);
                if (idx.bulat < 0 or idx.bulat >= target.array.len) {
                    return self.runtimeError(ix.target.pos, "indeks larik di luar batas");
                }
                return target.array[@intCast(idx.bulat)];
            },
        }
    }

    fn evalBinary(self: *Interpreter, expr: *ast.Expr, b: ast.Expr.Binary) Error!Value {
        const l = try self.eval(b.left);
        const r = try self.eval(b.right);

        if (std.meta.activeTag(l) == .teks and b.op == .add) {
            const joined = try std.fmt.allocPrint(self.vals.allocator(), "{s}{s}", .{ l.teks, r.teks });
            return .{ .teks = joined };
        }

        switch (b.op) {
            .eq => return .{ .bool = valueEql(l, r) },
            .neq => return .{ .bool = !valueEql(l, r) },
            .@"and" => return .{ .bool = l.bool and r.bool },
            .@"or" => return .{ .bool = l.bool or r.bool },
            else => {},
        }

        if (std.meta.activeTag(l) == .bulat) {
            const x = l.bulat;
            const y = r.bulat;
            return switch (b.op) {
                .add => .{ .bulat = x + y },
                .sub => .{ .bulat = x - y },
                .mul => .{ .bulat = x * y },
                .div => if (y == 0) self.runtimeError(expr.pos, "pembagian dengan nol") else .{ .bulat = @divTrunc(x, y) },
                .mod => if (y == 0) self.runtimeError(expr.pos, "modulo dengan nol") else .{ .bulat = @rem(x, y) },
                .lt => .{ .bool = x < y },
                .gt => .{ .bool = x > y },
                .le => .{ .bool = x <= y },
                .ge => .{ .bool = x >= y },
                else => unreachable,
            };
        } else {
            const x = l.desimal;
            const y = r.desimal;
            return switch (b.op) {
                .add => .{ .desimal = x + y },
                .sub => .{ .desimal = x - y },
                .mul => .{ .desimal = x * y },
                .div => .{ .desimal = x / y },
                .mod => .{ .desimal = @rem(x, y) },
                .lt => .{ .bool = x < y },
                .gt => .{ .bool = x > y },
                .le => .{ .bool = x <= y },
                .ge => .{ .bool = x >= y },
                else => unreachable,
            };
        }
    }

    fn evalCall(self: *Interpreter, c: ast.Expr.Call) Error!Value {
        const name = c.callee.data.ident;

        if (std.mem.eql(u8, name, "cetak")) {
            const v = try self.eval(c.args[0]);
            try self.printValue(v);
            try self.out.writeByte('\n');
            return .kosong;
        }

        if (std.mem.eql(u8, name, "panjang")) {
            const v = try self.eval(c.args[0]);
            return .{ .bulat = @intCast(v.array.len) };
        }

        const fn_stmt = self.functions.get(name).?;
        const f = fn_stmt.data.fungsi_decl;

        var arg_values = try self.allocator.alloc(Value, c.args.len);
        defer self.allocator.free(arg_values);
        for (c.args, 0..) |arg, i| arg_values[i] = try self.eval(arg);

        const saved = self.locals;
        self.locals = std.ArrayList(Scope).init(self.allocator);
        defer {
            for (self.locals.items) |*sc| sc.deinit();
            self.locals.deinit();
            self.locals = saved;
        }

        try self.locals.append(Scope.init(self.allocator));
        for (f.params, 0..) |p, i| {
            try self.locals.items[0].put(p.name, arg_values[i]);
        }

        for (f.body) |stmt| {
            try self.exec(stmt);
            if (self.returning) break;
        }

        const result = if (self.returning) self.ret_value else Value.kosong;
        self.returning = false;
        return result;
    }

    fn printValue(self: *Interpreter, v: Value) Error!void {
        switch (v) {
            .bulat => |n| try self.out.print("{d}", .{n}),
            .desimal => |n| try self.out.print("{d}", .{n}),
            .teks => |s| try self.out.writeAll(s),
            .bool => |b| try self.out.writeAll(if (b) "benar" else "salah"),
            .kosong => try self.out.writeAll("kosong"),
            .array => |arr| {
                try self.out.writeByte('[');
                for (arr, 0..) |el, i| {
                    if (i > 0) try self.out.writeAll(", ");
                    try self.printValue(el);
                }
                try self.out.writeByte(']');
            },
        }
    }

    fn define(self: *Interpreter, name: []const u8, value: Value) Error!void {
        if (self.locals.items.len == 0) {
            try self.global.put(name, value);
        } else {
            try self.locals.items[self.locals.items.len - 1].put(name, value);
        }
    }

    fn get(self: *Interpreter, name: []const u8) ?Value {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (self.locals.items[i].get(name)) |v| return v;
        }
        return self.global.get(name);
    }

    fn set(self: *Interpreter, name: []const u8, value: Value) bool {
        var i = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (self.locals.items[i].getPtr(name)) |ptr| {
                ptr.* = value;
                return true;
            }
        }
        if (self.global.getPtr(name)) |ptr| {
            ptr.* = value;
            return true;
        }
        return false;
    }

    fn runtimeError(self: *Interpreter, pos: ast.Pos, message: []const u8) Error {
        self.diags.report(.err, pos.line, pos.column, message) catch {};
        return Error.RuntimeError;
    }
};

fn valueEql(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .bulat => a.bulat == b.bulat,
        .desimal => a.desimal == b.desimal,
        .teks => std.mem.eql(u8, a.teks, b.teks),
        .bool => a.bool == b.bool,
        .kosong => true,
        .array => blk: {
            if (a.array.len != b.array.len) break :blk false;
            for (a.array, b.array) |x, y| {
                if (!valueEql(x, y)) break :blk false;
            }
            break :blk true;
        },
    };
}

const Lexer = @import("../lexer/lexer.zig").Lexer;
const parser = @import("../parser/parser.zig");
const sema = @import("../sema/sema.zig");

fn runToString(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var diags = Diagnostics.init(allocator);
    defer diags.deinit();

    var lexer = Lexer.init(source, &diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = try parser.parse(arena.allocator(), tokens, &diags);
    try sema.check(allocator, program, &diags);
    try std.testing.expect(!diags.hasErrors());

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    var interp = Interpreter.init(allocator, &diags, buf.writer().any());
    defer interp.deinit();
    try interp.run(program);

    return buf.toOwnedSlice();
}

fn expectOutput(source: []const u8, expected: []const u8) !void {
    const out = try runToString(std.testing.allocator, source);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(expected, out);
}

test "cetak teks dan angka" {
    try expectOutput("cetak(\"halo\"); cetak(1 + 2);", "halo\n3\n");
}

test "konkatenasi teks" {
    try expectOutput("biar nama = \"Tenun\"; cetak(\"Halo, \" + nama);", "Halo, Tenun\n");
}

test "kalau lain" {
    try expectOutput("biar x: bulat = 3; kalau x > 5 { cetak(\"besar\"); } lain { cetak(\"kecil\"); }", "kecil\n");
}

test "selama loop menghitung" {
    try expectOutput(
        \\biar n: bulat = 3;
        \\selama n > 0 {
        \\    cetak(n);
        \\    n = n - 1;
        \\}
    , "3\n2\n1\n");
}

test "untuk loop iterasi" {
    try expectOutput("untuk i dari 1 sampai 4 { cetak(i); }", "1\n2\n3\n");
}

test "untuk loop akumulasi" {
    try expectOutput(
        \\biar total: bulat = 0;
        \\untuk i dari 1 sampai 5 { total = total + i; }
        \\cetak(total);
    , "10\n");
}

test "larik akses dan panjang" {
    try expectOutput(
        \\biar a: []bulat = [10, 20, 30];
        \\cetak(a[1]);
        \\cetak(panjang(a));
    , "20\n3\n");
}

test "larik dijumlah lewat untuk" {
    try expectOutput(
        \\biar a: []bulat = [1, 2, 3, 4];
        \\biar total: bulat = 0;
        \\untuk i dari 0 sampai panjang(a) { total = total + a[i]; }
        \\cetak(total);
    , "10\n");
}

test "cetak larik" {
    try expectOutput("cetak([1, 2, 3]);", "[1, 2, 3]\n");
}

test "penugasan elemen larik" {
    try expectOutput(
        \\biar a: []bulat = [1, 2, 3];
        \\a[1] = 99;
        \\cetak(a);
    , "[1, 99, 3]\n");
}

test "isi larik lewat untuk" {
    try expectOutput(
        \\biar a: []bulat = [0, 0, 0];
        \\untuk i dari 0 sampai 3 { a[i] = i * i; }
        \\cetak(a);
    , "[0, 1, 4]\n");
}

test "fungsi dan rekursi faktorial" {
    try expectOutput(
        \\fungsi faktorial(n: bulat): bulat {
        \\    kalau n <= 1 { kembali 1; }
        \\    kembali n * faktorial(n - 1);
        \\}
        \\cetak(faktorial(5));
    , "120\n");
}

test "fungsi top-level dipanggil sebelum definisi" {
    try expectOutput(
        \\cetak(kuadrat(4));
        \\fungsi kuadrat(x: bulat): bulat { kembali x * x; }
    , "16\n");
}

test "boolean dan operator logika" {
    try expectOutput("cetak(benar && salah); cetak(benar || salah); cetak(!benar);", "salah\nbenar\nsalah\n");
}

test "scope lokal tidak bocor ke global" {
    try expectOutput(
        \\biar x: bulat = 1;
        \\fungsi ubah(): kosong { biar x: bulat = 99; cetak(x); }
        \\ubah();
        \\cetak(x);
    , "99\n1\n");
}
