const std = @import("std");
const ast = @import("../parser/ast.zig");

// Pretty-printer: AST -> sumber Tenun kanonik (indentasi 4 spasi, kurawal K&R).

pub fn format(program: ast.Program, writer: anytype) anyerror!void {
    for (program.stmts, 0..) |s, i| {
        if (i > 0 and isDecl(s)) try writer.writeByte('\n');
        try stmt(s, writer, 0);
        try writer.writeByte('\n');
    }
}

fn isDecl(s: *ast.Stmt) bool {
    return switch (s.data) {
        .fungsi_decl => true,
        else => false,
    };
}

fn indent(writer: anytype, level: usize) !void {
    var i: usize = 0;
    while (i < level * 4) : (i += 1) try writer.writeByte(' ');
}

fn block(stmts: []*ast.Stmt, writer: anytype, level: usize) !void {
    try writer.writeAll("{\n");
    for (stmts) |s| {
        try indent(writer, level + 1);
        try stmt(s, writer, level + 1);
        try writer.writeByte('\n');
    }
    try indent(writer, level);
    try writer.writeByte('}');
}

fn stmt(s: *ast.Stmt, writer: anytype, level: usize) anyerror!void {
    switch (s.data) {
        .var_decl => |d| {
            try writer.writeAll(if (d.is_const) "tetap " else "biar ");
            try writer.writeAll(d.name);
            if (d.type_anno) |t| {
                try writer.writeAll(": ");
                try t.writeName(writer);
            }
            try writer.writeAll(" = ");
            try expr(d.value, writer, 0);
            try writer.writeByte(';');
        },
        .fungsi_decl => |d| {
            try writer.writeAll("fungsi ");
            try writer.writeAll(d.name);
            try writer.writeByte('(');
            for (d.params, 0..) |p, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(p.name);
                try writer.writeAll(": ");
                try p.type.writeName(writer);
            }
            try writer.writeAll("): ");
            try d.return_type.writeName(writer);
            try writer.writeByte(' ');
            try block(d.body, writer, level);
        },
        .expr_stmt => |e| {
            try expr(e, writer, 0);
            try writer.writeByte(';');
        },
        .if_stmt => |d| {
            try writer.writeAll("kalau ");
            try expr(d.cond, writer, 0);
            try writer.writeByte(' ');
            try block(d.then_block, writer, level);
            if (d.else_branch) |e| {
                try writer.writeAll(" lain ");
                switch (e.data) {
                    .if_stmt => try stmt(e, writer, level),
                    .block => |b| try block(b, writer, level),
                    else => try stmt(e, writer, level),
                }
            }
        },
        .while_stmt => |d| {
            try writer.writeAll("selama ");
            try expr(d.cond, writer, 0);
            try writer.writeByte(' ');
            try block(d.body, writer, level);
        },
        .for_stmt => |d| {
            try writer.writeAll("untuk ");
            try writer.writeAll(d.var_name);
            try writer.writeAll(" dari ");
            try expr(d.start, writer, 0);
            try writer.writeAll(" sampai ");
            try expr(d.end, writer, 0);
            try writer.writeByte(' ');
            try block(d.body, writer, level);
        },
        .foreach_stmt => |d| {
            try writer.writeAll("untuk ");
            try writer.writeAll(d.var_name);
            try writer.writeAll(" dari ");
            try expr(d.iter, writer, 0);
            try writer.writeByte(' ');
            try block(d.body, writer, level);
        },
        .return_stmt => |maybe| {
            try writer.writeAll("kembali");
            if (maybe) |e| {
                try writer.writeByte(' ');
                try expr(e, writer, 0);
            }
            try writer.writeByte(';');
        },
        .break_stmt => try writer.writeAll("henti;"),
        .continue_stmt => try writer.writeAll("lanjut;"),
        .block => |stmts| try block(stmts, writer, level),
    }
}

// Precedence: makin besar makin erat.
fn prec(op: ast.BinaryOp) u8 {
    return switch (op) {
        .@"or" => 1,
        .@"and" => 2,
        .bit_or => 3,
        .bit_xor => 4,
        .bit_and => 5,
        .eq, .neq => 6,
        .lt, .gt, .le, .ge => 7,
        .shl, .shr => 8,
        .add, .sub => 9,
        .mul, .div, .mod => 10,
    };
}

// parent_prec = precedence konteks; bungkus kurung kalau perlu.
fn expr(e: *ast.Expr, writer: anytype, parent_prec: u8) anyerror!void {
    switch (e.data) {
        .number => |s| try writer.writeAll(s),
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\t' => try writer.writeAll("\\t"),
                '\r' => try writer.writeAll("\\r"),
                0 => try writer.writeAll("\\0"),
                else => try writer.writeByte(c),
            };
            try writer.writeByte('"');
        },
        .boolean => |b| try writer.writeAll(if (b) "benar" else "salah"),
        .nil => try writer.writeAll("kosong"),
        .ident => |s| try writer.writeAll(s),
        .unary => |u| {
            try writer.writeAll(if (u.op == .not) "!" else "-");
            try expr(u.operand, writer, 7);
        },
        .binary => |b| {
            const p = prec(b.op);
            const wrap = p < parent_prec;
            if (wrap) try writer.writeByte('(');
            try expr(b.left, writer, p);
            try writer.writeByte(' ');
            try writer.writeAll(b.op.symbol());
            try writer.writeByte(' ');
            try expr(b.right, writer, p + 1);
            if (wrap) try writer.writeByte(')');
        },
        .call => |c| {
            try expr(c.callee, writer, 8);
            try writer.writeByte('(');
            for (c.args, 0..) |a, i| {
                if (i > 0) try writer.writeAll(", ");
                try expr(a, writer, 0);
            }
            try writer.writeByte(')');
        },
        .assign => |a| {
            try expr(a.target, writer, 0);
            try writer.writeAll(" = ");
            try expr(a.value, writer, 0);
        },
        .array => |elems| {
            try writer.writeByte('[');
            for (elems, 0..) |el, i| {
                if (i > 0) try writer.writeAll(", ");
                try expr(el, writer, 0);
            }
            try writer.writeByte(']');
        },
        .index => |ix| {
            try expr(ix.target, writer, 8);
            try writer.writeByte('[');
            try expr(ix.idx, writer, 0);
            try writer.writeByte(']');
        },
        .map_lit => |entries| {
            try writer.writeAll("peta{");
            for (entries, 0..) |en, i| {
                if (i > 0) try writer.writeAll(", ");
                try expr(en.key, writer, 0);
                try writer.writeAll(": ");
                try expr(en.value, writer, 0);
            }
            try writer.writeByte('}');
        },
    }
}
