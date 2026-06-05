const std = @import("std");

pub const Pos = struct {
    line: usize,
    column: usize,
};

pub const Type = union(enum) {
    bulat,
    desimal,
    teks,
    bool,
    kosong,
    peta, // map teks -> teks
    fungsi, // nilai fungsi (first-class)
    dinamis, // tipe apa saja (hasil panggilan tak langsung)
    array: *const Type,

    pub fn eql(a: Type, b: Type) bool {
        // dinamis kompatibel dengan tipe apa pun (escape hatch dinamis).
        if (std.meta.activeTag(a) == .dinamis or std.meta.activeTag(b) == .dinamis) return true;
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .array => a.array.eql(b.array.*),
            else => true,
        };
    }

    pub fn isNumeric(self: Type) bool {
        return switch (self) {
            .bulat, .desimal => true,
            else => false,
        };
    }

    pub fn writeName(self: Type, writer: anytype) anyerror!void {
        switch (self) {
            .bulat => try writer.writeAll("bulat"),
            .desimal => try writer.writeAll("desimal"),
            .teks => try writer.writeAll("teks"),
            .bool => try writer.writeAll("bool"),
            .kosong => try writer.writeAll("kosong"),
            .peta => try writer.writeAll("peta"),
            .fungsi => try writer.writeAll("fungsi"),
            .dinamis => try writer.writeAll("dinamis"),
            .array => |el| {
                try writer.writeAll("[]");
                try el.writeName(writer);
            },
        }
    }
};

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    gt,
    le,
    ge,
    @"and",
    @"or",

    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .eq => "==",
            .neq => "!=",
            .lt => "<",
            .gt => ">",
            .le => "<=",
            .ge => ">=",
            .@"and" => "&&",
            .@"or" => "||",
        };
    }
};

pub const UnaryOp = enum {
    neg,
    not,

    pub fn symbol(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "neg",
            .not => "!",
        };
    }
};

pub const Expr = struct {
    pos: Pos,
    data: Data,

    pub const Data = union(enum) {
        number: []const u8,
        string: []const u8,
        boolean: bool,
        nil,
        ident: []const u8,
        unary: Unary,
        binary: Binary,
        call: Call,
        assign: Assign,
        array: []*Expr,
        index: Index,
        map_lit: []MapEntry,
    };

    pub const Unary = struct { op: UnaryOp, operand: *Expr };
    pub const Binary = struct { op: BinaryOp, left: *Expr, right: *Expr };
    pub const Call = struct { callee: *Expr, args: []*Expr };
    pub const Assign = struct { target: *Expr, value: *Expr };
    pub const Index = struct { target: *Expr, idx: *Expr };
    pub const MapEntry = struct { key: *Expr, value: *Expr };
};

pub const Param = struct {
    name: []const u8,
    type: Type,
};

pub const Stmt = struct {
    pos: Pos,
    data: Data,

    pub const Data = union(enum) {
        var_decl: VarDecl,
        fungsi_decl: FungsiDecl,
        expr_stmt: *Expr,
        if_stmt: If,
        while_stmt: While,
        for_stmt: For,
        foreach_stmt: ForEach,
        return_stmt: ?*Expr,
        break_stmt,
        continue_stmt,
        block: []*Stmt,
    };

    pub const VarDecl = struct {
        is_const: bool,
        name: []const u8,
        type_anno: ?Type,
        value: *Expr,
    };

    pub const FungsiDecl = struct {
        name: []const u8,
        params: []Param,
        return_type: Type,
        body: []*Stmt,
    };

    pub const If = struct {
        cond: *Expr,
        then_block: []*Stmt,
        else_branch: ?*Stmt,
    };

    pub const While = struct {
        cond: *Expr,
        body: []*Stmt,
    };

    pub const For = struct {
        var_name: []const u8,
        start: *Expr,
        end: *Expr,
        body: []*Stmt,
    };

    pub const ForEach = struct {
        var_name: []const u8,
        iter: *Expr,
        body: []*Stmt,
    };
};

pub const Program = struct {
    stmts: []*Stmt,
};

pub fn dumpProgram(program: Program, writer: anytype) anyerror!void {
    for (program.stmts) |s| {
        try dumpStmt(s, writer);
        try writer.writeByte('\n');
    }
}

fn dumpStmts(stmts: []*Stmt, writer: anytype) anyerror!void {
    try writer.writeByte('{');
    for (stmts, 0..) |s, i| {
        if (i > 0) try writer.writeByte(' ');
        try dumpStmt(s, writer);
    }
    try writer.writeByte('}');
}

fn dumpStmt(stmt: *Stmt, writer: anytype) anyerror!void {
    switch (stmt.data) {
        .var_decl => |d| {
            try writer.print("({s} {s}", .{ if (d.is_const) "tetap" else "biar", d.name });
            if (d.type_anno) |t| {
                try writer.writeAll(" :");
                try t.writeName(writer);
            }
            try writer.writeByte(' ');
            try dumpExpr(d.value, writer);
            try writer.writeByte(')');
        },
        .fungsi_decl => |d| {
            try writer.print("(fungsi {s} (", .{d.name});
            for (d.params, 0..) |p, i| {
                if (i > 0) try writer.writeByte(' ');
                try writer.print("({s} ", .{p.name});
                try p.type.writeName(writer);
                try writer.writeByte(')');
            }
            try writer.writeAll(") :");
            try d.return_type.writeName(writer);
            try writer.writeByte(' ');
            try dumpStmts(d.body, writer);
            try writer.writeByte(')');
        },
        .expr_stmt => |e| try dumpExpr(e, writer),
        .if_stmt => |d| {
            try writer.writeAll("(kalau ");
            try dumpExpr(d.cond, writer);
            try writer.writeByte(' ');
            try dumpStmts(d.then_block, writer);
            if (d.else_branch) |e| {
                try writer.writeAll(" lain ");
                try dumpStmt(e, writer);
            }
            try writer.writeByte(')');
        },
        .while_stmt => |d| {
            try writer.writeAll("(selama ");
            try dumpExpr(d.cond, writer);
            try writer.writeByte(' ');
            try dumpStmts(d.body, writer);
            try writer.writeByte(')');
        },
        .for_stmt => |d| {
            try writer.print("(untuk {s} dari ", .{d.var_name});
            try dumpExpr(d.start, writer);
            try writer.writeAll(" sampai ");
            try dumpExpr(d.end, writer);
            try writer.writeByte(' ');
            try dumpStmts(d.body, writer);
            try writer.writeByte(')');
        },
        .foreach_stmt => |d| {
            try writer.print("(untuk-tiap {s} ", .{d.var_name});
            try dumpExpr(d.iter, writer);
            try writer.writeByte(' ');
            try dumpStmts(d.body, writer);
            try writer.writeByte(')');
        },
        .return_stmt => |maybe| {
            try writer.writeAll("(kembali");
            if (maybe) |e| {
                try writer.writeByte(' ');
                try dumpExpr(e, writer);
            }
            try writer.writeByte(')');
        },
        .break_stmt => try writer.writeAll("(henti)"),
        .continue_stmt => try writer.writeAll("(lanjut)"),
        .block => |stmts| try dumpStmts(stmts, writer),
    }
}

fn dumpExpr(expr: *Expr, writer: anytype) anyerror!void {
    switch (expr.data) {
        .number => |s| try writer.writeAll(s),
        .string => |s| {
            try writer.writeByte('"');
            try writer.writeAll(s);
            try writer.writeByte('"');
        },
        .boolean => |b| try writer.writeAll(if (b) "benar" else "salah"),
        .nil => try writer.writeAll("kosong"),
        .ident => |s| try writer.writeAll(s),
        .unary => |u| {
            try writer.print("({s} ", .{u.op.symbol()});
            try dumpExpr(u.operand, writer);
            try writer.writeByte(')');
        },
        .binary => |b| {
            try writer.print("({s} ", .{b.op.symbol()});
            try dumpExpr(b.left, writer);
            try writer.writeByte(' ');
            try dumpExpr(b.right, writer);
            try writer.writeByte(')');
        },
        .call => |c| {
            try writer.writeAll("(panggil ");
            try dumpExpr(c.callee, writer);
            for (c.args) |a| {
                try writer.writeByte(' ');
                try dumpExpr(a, writer);
            }
            try writer.writeByte(')');
        },
        .assign => |a| {
            try writer.writeAll("(= ");
            try dumpExpr(a.target, writer);
            try writer.writeByte(' ');
            try dumpExpr(a.value, writer);
            try writer.writeByte(')');
        },
        .array => |elems| {
            try writer.writeAll("(larik");
            for (elems) |e| {
                try writer.writeByte(' ');
                try dumpExpr(e, writer);
            }
            try writer.writeByte(')');
        },
        .index => |ix| {
            try writer.writeAll("(indeks ");
            try dumpExpr(ix.target, writer);
            try writer.writeByte(' ');
            try dumpExpr(ix.idx, writer);
            try writer.writeByte(')');
        },
        .map_lit => |entries| {
            try writer.writeAll("(peta");
            for (entries) |e| {
                try writer.writeAll(" (");
                try dumpExpr(e.key, writer);
                try writer.writeByte(' ');
                try dumpExpr(e.value, writer);
                try writer.writeByte(')');
            }
            try writer.writeByte(')');
        },
    }
}

test "dump ekspresi sederhana" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    var two = Expr{ .pos = .{ .line = 1, .column = 1 }, .data = .{ .number = "2" } };
    var three = Expr{ .pos = .{ .line = 1, .column = 5 }, .data = .{ .number = "3" } };
    var bin = Expr{ .pos = .{ .line = 1, .column = 1 }, .data = .{ .binary = .{ .op = .add, .left = &two, .right = &three } } };

    try dumpExpr(&bin, buf.writer());
    try std.testing.expectEqualStrings("(+ 2 3)", buf.items);
}
