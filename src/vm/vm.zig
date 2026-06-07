const std = @import("std");
const runtime = @import("../rt.zig");
const ast = @import("../parser/ast.zig");
const Diagnostics = @import("../diagnostics/diagnostics.zig").Diagnostics;
const sock = @import("../builtins/sock.zig");
const http = @import("../builtins/http.zig");
const spec = @import("../builtins/spec.zig");
const text = @import("../builtins/text.zig");
const fs = @import("../builtins/fs.zig");
const json = @import("../builtins/json.zig");
const kv = @import("../builtins/kv.zig");
const crypto = @import("../builtins/crypto.zig");
const binmod = @import("../builtins/binary.zig");
const tls = @import("../builtins/tls.zig");
const siar = @import("../builtins/siar.zig");
const argv = @import("../builtins/argv.zig");
const waktu = @import("../builtins/waktu.zig");
const os = @import("../builtins/os.zig");
const proses = @import("../builtins/proses.zig");
const gambar = @import("../builtins/gambar.zig");
const uji = @import("../builtins/uji.zig");

pub const Value = union(enum) {
    bulat: i64,
    desimal: f64,
    teks: []const u8,
    bool: bool,
    kosong,
    array: []Value,
    peta: *std.StringHashMap(Value), // map teks -> nilai apa pun (dinamis)
    fungsi: usize, // indeks ke functions (first-class)
};

pub const OpCode = enum(u8) {
    constant,
    true_,
    false_,
    kosong_,
    neg,
    not,
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
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
    pop,
    define_global,
    get_global,
    set_global,
    get_local,
    set_local,
    jump,
    jump_if_false,
    loop,
    call,
    call_value,
    ret,
    print,
    array_make,
    map_make,
    coba_mulai,
    coba_akhir,
    index_get,
    index_set,
    array_len,
    builtin,
};

const Chunk = struct {
    code: std.array_list.Managed(u8),
    consts: std.array_list.Managed(Value),

    fn init(allocator: std.mem.Allocator) Chunk {
        return .{ .code = std.array_list.Managed(u8).init(allocator), .consts = std.array_list.Managed(Value).init(allocator) };
    }
    fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.consts.deinit();
    }
    fn emit(self: *Chunk, byte: u8) !void {
        try self.code.append(byte);
    }
    fn emitOp(self: *Chunk, op: OpCode) !void {
        try self.code.append(@intFromEnum(op));
    }
    fn emitU16(self: *Chunk, v: u16) !void {
        try self.code.append(@intCast(v >> 8));
        try self.code.append(@intCast(v & 0xff));
    }
    fn addConst(self: *Chunk, v: Value) !u16 {
        try self.consts.append(v);
        return @intCast(self.consts.items.len - 1);
    }
};

const Function = struct {
    name: []const u8,
    arity: usize,
    chunk: Chunk,
};

const Local = struct {
    name: []const u8,
    depth: i32,
};

const FnCompiler = struct {
    chunk: *Chunk,
    locals: [256]Local = undefined,
    local_count: usize = 0,
    scope_depth: i32 = 0,
};

// Konteks loop untuk henti (break) & lanjut (continue).
const LoopCtx = struct {
    base_locals: usize,
    break_jumps: std.array_list.Managed(usize),
    cont_backward: bool, // selama: lanjut lompat mundur ke cond
    cont_target: usize, // dipakai bila cont_backward
    cont_jumps: std.array_list.Managed(usize), // untuk: lanjut lompat maju ke increment
};

const Compiler = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    functions: std.array_list.Managed(Function),
    fn_index: std.StringHashMap(usize),
    global_index: std.StringHashMap(u16),
    loops: std.array_list.Managed(LoopCtx),
    cur: *FnCompiler = undefined,

    fn init(allocator: std.mem.Allocator, diags: *Diagnostics) Compiler {
        return .{
            .allocator = allocator,
            .diags = diags,
            .functions = std.array_list.Managed(Function).init(allocator),
            .fn_index = std.StringHashMap(usize).init(allocator),
            .global_index = std.StringHashMap(u16).init(allocator),
            .loops = std.array_list.Managed(LoopCtx).init(allocator),
        };
    }
    fn deinit(self: *Compiler) void {
        for (self.functions.items) |*f| f.chunk.deinit();
        self.functions.deinit();
        self.fn_index.deinit();
        self.global_index.deinit();
        self.loops.deinit();
    }

    // Slot global untuk sebuah nama (buat baru bila belum ada). Akses global jadi
    // indeks array, bukan lookup hashmap saat runtime.
    fn globalSlot(self: *Compiler, name: []const u8) !u16 {
        if (self.global_index.get(name)) |s| return s;
        const slot: u16 = @intCast(self.global_index.count());
        try self.global_index.put(name, slot);
        return slot;
    }

    fn compileProgram(self: *Compiler, program: ast.Program) !void {
        try self.functions.append(.{ .name = "utama", .arity = 0, .chunk = Chunk.init(self.allocator) });
        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .fungsi_decl) {
                const f = s.data.fungsi_decl;
                const idx = self.functions.items.len;
                try self.functions.append(.{ .name = f.name, .arity = f.params.len, .chunk = Chunk.init(self.allocator) });
                try self.fn_index.put(f.name, idx);
            }
        }

        var main_fc = FnCompiler{ .chunk = &self.functions.items[0].chunk };
        self.cur = &main_fc;
        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) != .fungsi_decl) try self.stmt(s);
        }
        try self.cur.chunk.emitOp(.kosong_);
        try self.cur.chunk.emitOp(.ret);

        for (program.stmts) |s| {
            if (std.meta.activeTag(s.data) == .fungsi_decl) try self.compileFn(s.data.fungsi_decl);
        }
    }

    fn compileFn(self: *Compiler, f: ast.Stmt.FungsiDecl) !void {
        const idx = self.fn_index.get(f.name).?;
        var fc = FnCompiler{ .chunk = &self.functions.items[idx].chunk };
        self.cur = &fc;
        fc.scope_depth = 1;
        for (f.params) |p| _ = self.declareLocal(p.name);
        for (f.body) |s| try self.stmt(s);
        try self.cur.chunk.emitOp(.kosong_);
        try self.cur.chunk.emitOp(.ret);
    }

    fn declareLocal(self: *Compiler, name: []const u8) usize {
        const slot = self.cur.local_count;
        self.cur.locals[slot] = .{ .name = name, .depth = self.cur.scope_depth };
        self.cur.local_count += 1;
        return slot;
    }
    fn resolveLocal(self: *Compiler, name: []const u8) ?usize {
        var i = self.cur.local_count;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.cur.locals[i].name, name)) return i;
        }
        return null;
    }
    fn beginScope(self: *Compiler) void {
        self.cur.scope_depth += 1;
    }
    fn endScope(self: *Compiler) !void {
        self.cur.scope_depth -= 1;
        while (self.cur.local_count > 0 and self.cur.locals[self.cur.local_count - 1].depth > self.cur.scope_depth) {
            try self.cur.chunk.emitOp(.pop);
            self.cur.local_count -= 1;
        }
    }

    fn block(self: *Compiler, stmts: []*ast.Stmt) !void {
        self.beginScope();
        for (stmts) |s| try self.stmt(s);
        try self.endScope();
    }

    fn stmt(self: *Compiler, s: *ast.Stmt) anyerror!void {
        const c = self.cur.chunk;
        switch (s.data) {
            .var_decl => |d| {
                try self.expr(d.value);
                if (self.cur.scope_depth == 0) {
                    const slot = try self.globalSlot(d.name);
                    try c.emitOp(.define_global);
                    try c.emitU16(slot);
                } else {
                    _ = self.declareLocal(d.name);
                }
            },
            .fungsi_decl => {},
            .expr_stmt => |e| {
                try self.expr(e);
                try c.emitOp(.pop);
            },
            .block => |stmts| try self.block(stmts),
            .impor_stmt => {}, // di-inline oleh driver sebelum dikompilasi
            .if_stmt => |d| {
                try self.expr(d.cond);
                const then_jump = try self.emitJump(.jump_if_false);
                try c.emitOp(.pop);
                try self.block(d.then_block);
                const else_jump = try self.emitJump(.jump);
                try self.patchJump(then_jump);
                try c.emitOp(.pop);
                if (d.else_branch) |e| try self.stmt(e);
                try self.patchJump(else_jump);
            },
            .while_stmt => |d| {
                const loop_start = c.code.items.len;
                try self.expr(d.cond);
                const exit_jump = try self.emitJump(.jump_if_false);
                try c.emitOp(.pop);
                try self.loops.append(.{
                    .base_locals = self.cur.local_count,
                    .break_jumps = std.array_list.Managed(usize).init(self.allocator),
                    .cont_backward = true,
                    .cont_target = loop_start,
                    .cont_jumps = std.array_list.Managed(usize).init(self.allocator),
                });
                try self.block(d.body);
                try self.emitLoop(loop_start);
                try self.patchJump(exit_jump);
                try c.emitOp(.pop);
                try self.akhiriLoop();
            },
            .for_stmt => |d| {
                self.beginScope();
                try self.expr(d.start);
                const slot_i = self.declareLocal(d.var_name);
                try self.expr(d.end);
                const slot_end = self.declareLocal("$end");
                const loop_start = c.code.items.len;
                try self.emitGetLocal(slot_i);
                try self.emitGetLocal(slot_end);
                try c.emitOp(.lt);
                const exit_jump = try self.emitJump(.jump_if_false);
                try c.emitOp(.pop);
                try self.loops.append(.{
                    .base_locals = self.cur.local_count,
                    .break_jumps = std.array_list.Managed(usize).init(self.allocator),
                    .cont_backward = false,
                    .cont_target = 0,
                    .cont_jumps = std.array_list.Managed(usize).init(self.allocator),
                });
                try self.block(d.body);
                // Titik 'lanjut' (continue): increment i.
                const incr = c.code.items.len;
                for (self.loops.items[self.loops.items.len - 1].cont_jumps.items) |cj| try self.patchJump(cj);
                _ = incr;
                try self.emitGetLocal(slot_i);
                const one = try c.addConst(.{ .bulat = 1 });
                try c.emitOp(.constant);
                try c.emitU16(one);
                try c.emitOp(.add);
                try c.emitOp(.set_local);
                try c.emit(@intCast(slot_i));
                try c.emitOp(.pop);
                try self.emitLoop(loop_start);
                try self.patchJump(exit_jump);
                try c.emitOp(.pop);
                try self.akhiriLoop();
                try self.endScope();
            },
            .foreach_stmt => |d| {
                self.beginScope();
                try self.expr(d.iter);
                const slot_arr = self.declareLocal("$arr");
                const zero = try c.addConst(.{ .bulat = 0 });
                try c.emitOp(.constant);
                try c.emitU16(zero);
                const slot_idx = self.declareLocal("$idx");
                try c.emitOp(.kosong_);
                const slot_x = self.declareLocal(d.var_name);
                const loop_start = c.code.items.len;
                try self.emitGetLocal(slot_idx);
                try self.emitGetLocal(slot_arr);
                try c.emitOp(.array_len);
                try c.emitOp(.lt);
                const exit_jump = try self.emitJump(.jump_if_false);
                try c.emitOp(.pop);
                // x = arr[idx]
                try self.emitGetLocal(slot_arr);
                try self.emitGetLocal(slot_idx);
                try c.emitOp(.index_get);
                try c.emitOp(.set_local);
                try c.emit(@intCast(slot_x));
                try c.emitOp(.pop);
                try self.loops.append(.{
                    .base_locals = self.cur.local_count,
                    .break_jumps = std.array_list.Managed(usize).init(self.allocator),
                    .cont_backward = false,
                    .cont_target = 0,
                    .cont_jumps = std.array_list.Managed(usize).init(self.allocator),
                });
                try self.block(d.body);
                for (self.loops.items[self.loops.items.len - 1].cont_jumps.items) |cj| try self.patchJump(cj);
                // idx = idx + 1
                try self.emitGetLocal(slot_idx);
                const one2 = try c.addConst(.{ .bulat = 1 });
                try c.emitOp(.constant);
                try c.emitU16(one2);
                try c.emitOp(.add);
                try c.emitOp(.set_local);
                try c.emit(@intCast(slot_idx));
                try c.emitOp(.pop);
                try self.emitLoop(loop_start);
                try self.patchJump(exit_jump);
                try c.emitOp(.pop);
                try self.akhiriLoop();
                try self.endScope();
            },
            .break_stmt => {
                const lc = &self.loops.items[self.loops.items.len - 1];
                var k = self.cur.local_count;
                while (k > lc.base_locals) : (k -= 1) try c.emitOp(.pop);
                const j = try self.emitJump(.jump);
                try lc.break_jumps.append(j);
            },
            .continue_stmt => {
                const lc = &self.loops.items[self.loops.items.len - 1];
                var k = self.cur.local_count;
                while (k > lc.base_locals) : (k -= 1) try c.emitOp(.pop);
                if (lc.cont_backward) {
                    try self.emitLoop(lc.cont_target);
                } else {
                    const j = try self.emitJump(.jump);
                    try lc.cont_jumps.append(j);
                }
            },
            .match_stmt => |d| {
                self.beginScope();
                try self.expr(d.subject);
                const slot = self.declareLocal("$cocok");
                var endJumps = std.array_list.Managed(usize).init(self.allocator);
                defer endJumps.deinit();
                for (d.arms) |arm| {
                    try self.emitGetLocal(slot);
                    try self.expr(arm.value);
                    try c.emitOp(.eq);
                    const nextJ = try self.emitJump(.jump_if_false);
                    try c.emitOp(.pop);
                    try self.block(arm.body);
                    try endJumps.append(try self.emitJump(.jump));
                    try self.patchJump(nextJ);
                    try c.emitOp(.pop);
                }
                if (d.default) |def| try self.block(def);
                for (endJumps.items) |ej| try self.patchJump(ej);
                try self.endScope();
            },
            .try_stmt => |d| {
                try c.emitOp(.coba_mulai);
                const hpos = c.code.items.len;
                try c.emitU16(0); // placeholder offset ke handler
                try self.block(d.body);
                try c.emitOp(.coba_akhir);
                const endj = try self.emitJump(.jump);
                // patch offset coba_mulai -> awal handler
                const handler_start = c.code.items.len;
                const off: u16 = @intCast(handler_start - (hpos + 2));
                c.code.items[hpos] = @intCast(off >> 8);
                c.code.items[hpos + 1] = @intCast(off & 0xff);
                // handler: galat (teks) jadi lokal pertama
                self.beginScope();
                _ = self.declareLocal(d.err_name);
                for (d.handler) |hstmt| try self.stmt(hstmt);
                try self.endScope();
                try self.patchJump(endj);
            },
            .return_stmt => |maybe| {
                if (maybe) |e| try self.expr(e) else try c.emitOp(.kosong_);
                try c.emitOp(.ret);
            },
        }
    }

    fn expr(self: *Compiler, e: *ast.Expr) anyerror!void {
        const c = self.cur.chunk;
        switch (e.data) {
            .number => |s| {
                const v: Value = if (std.mem.indexOfScalar(u8, s, '.') != null)
                    .{ .desimal = std.fmt.parseFloat(f64, s) catch 0 }
                else
                    .{ .bulat = std.fmt.parseInt(i64, s, 0) catch 0 };
                const i = try c.addConst(v);
                try c.emitOp(.constant);
                try c.emitU16(i);
            },
            .string => |s| {
                const i = try c.addConst(.{ .teks = s });
                try c.emitOp(.constant);
                try c.emitU16(i);
            },
            .boolean => |b| try c.emitOp(if (b) .true_ else .false_),
            .nil => try c.emitOp(.kosong_),
            .ident => |name| {
                if (self.resolveLocal(name)) |slot| {
                    try self.emitGetLocal(slot);
                } else if (self.fn_index.get(name)) |fidx| {
                    // Nama fungsi sebagai nilai (first-class).
                    const i = try c.addConst(.{ .fungsi = fidx });
                    try c.emitOp(.constant);
                    try c.emitU16(i);
                } else {
                    const slot = try self.globalSlot(name);
                    try c.emitOp(.get_global);
                    try c.emitU16(slot);
                }
            },
            .unary => |u| {
                try self.expr(u.operand);
                try c.emitOp(if (u.op == .neg) .neg else .not);
            },
            .binary => |b| {
                if (b.op == .@"and") {
                    try self.expr(b.left);
                    const end_jump = try self.emitJump(.jump_if_false);
                    try c.emitOp(.pop);
                    try self.expr(b.right);
                    try self.patchJump(end_jump);
                    return;
                }
                if (b.op == .@"or") {
                    try self.expr(b.left);
                    const else_jump = try self.emitJump(.jump_if_false);
                    const end_jump = try self.emitJump(.jump);
                    try self.patchJump(else_jump);
                    try c.emitOp(.pop);
                    try self.expr(b.right);
                    try self.patchJump(end_jump);
                    return;
                }
                try self.expr(b.left);
                try self.expr(b.right);
                try c.emitOp(switch (b.op) {
                    .add => .add,
                    .sub => .sub,
                    .mul => .mul,
                    .div => .div,
                    .mod => .mod,
                    .eq => .eq,
                    .neq => .neq,
                    .lt => .lt,
                    .gt => .gt,
                    .le => .le,
                    .ge => .ge,
                    .bit_and => .bit_and,
                    .bit_or => .bit_or,
                    .bit_xor => .bit_xor,
                    .shl => .shl,
                    .shr => .shr,
                    else => unreachable,
                });
            },
            .call => |call| {
                if (std.meta.activeTag(call.callee.data) == .ident) {
                    const name = call.callee.data.ident;
                    // Hanya jalur khusus bila nama BUKAN variabel lokal (tak ter-shadow).
                    if (self.resolveLocal(name) == null) {
                        if (std.mem.eql(u8, name, "cetak")) {
                            try self.expr(call.args[0]);
                            try c.emitOp(.print);
                            try c.emitOp(.kosong_);
                            return;
                        }
                        if (std.mem.eql(u8, name, "panjang")) {
                            try self.expr(call.args[0]);
                            try c.emitOp(.array_len);
                            return;
                        }
                        if (spec.indexOf(name)) |id| {
                            for (call.args) |a| try self.expr(a);
                            try c.emitOp(.builtin);
                            try c.emit(@intCast(id));
                            try c.emit(@intCast(call.args.len));
                            return;
                        }
                        if (self.fn_index.get(name)) |idx| {
                            for (call.args) |a| try self.expr(a);
                            try c.emitOp(.call);
                            try c.emitU16(@intCast(idx));
                            try c.emit(@intCast(call.args.len));
                            return;
                        }
                    }
                }
                // Panggilan tak langsung: nilai fungsi dari variabel/indeks/ekspresi.
                for (call.args) |a| try self.expr(a);
                try self.expr(call.callee);
                try c.emitOp(.call_value);
                try c.emit(@intCast(call.args.len));
            },
            .assign => |a| {
                switch (a.target.data) {
                    .ident => |name| {
                        try self.expr(a.value);
                        if (self.resolveLocal(name)) |slot| {
                            try c.emitOp(.set_local);
                            try c.emit(@intCast(slot));
                        } else {
                            const slot = try self.globalSlot(name);
                            try c.emitOp(.set_global);
                            try c.emitU16(slot);
                        }
                    },
                    .index => |ix| {
                        try self.expr(ix.target);
                        try self.expr(ix.idx);
                        try self.expr(a.value);
                        try c.emitOp(.index_set);
                    },
                    else => unreachable,
                }
            },
            .array => |elems| {
                for (elems) |el| try self.expr(el);
                try c.emitOp(.array_make);
                try c.emitU16(@intCast(elems.len));
            },
            .map_lit => |entries| {
                for (entries) |en| {
                    try self.expr(en.key);
                    try self.expr(en.value);
                }
                try c.emitOp(.map_make);
                try c.emitU16(@intCast(entries.len));
            },
            .index => |ix| {
                try self.expr(ix.target);
                try self.expr(ix.idx);
                try c.emitOp(.index_get);
            },
        }
    }

    fn emitGetLocal(self: *Compiler, slot: usize) !void {
        try self.cur.chunk.emitOp(.get_local);
        try self.cur.chunk.emit(@intCast(slot));
    }
    fn emitJump(self: *Compiler, op: OpCode) !usize {
        try self.cur.chunk.emitOp(op);
        try self.cur.chunk.emitU16(0xffff);
        return self.cur.chunk.code.items.len - 2;
    }
    fn patchJump(self: *Compiler, offset: usize) !void {
        const dist = self.cur.chunk.code.items.len - offset - 2;
        self.cur.chunk.code.items[offset] = @intCast(dist >> 8);
        self.cur.chunk.code.items[offset + 1] = @intCast(dist & 0xff);
    }
    fn emitLoop(self: *Compiler, loop_start: usize) !void {
        try self.cur.chunk.emitOp(.loop);
        const dist = self.cur.chunk.code.items.len - loop_start + 2;
        try self.cur.chunk.emitU16(@intCast(dist));
    }

    // Tutup loop: patch semua jump 'henti' ke posisi sekarang, bersihkan ctx.
    fn akhiriLoop(self: *Compiler) !void {
        var lc = self.loops.pop().?;
        for (lc.break_jumps.items) |bj| try self.patchJump(bj);
        lc.break_jumps.deinit();
        lc.cont_jumps.deinit();
    }
};

const Frame = struct {
    func: *Function,
    ip: usize,
    base: usize,
};

// Handler coba/tangkap: titik pemulihan saat runtime error.
const Handler = struct {
    handler_ip: usize,
    frame_len: usize,
    stack_top: usize,
};

const stack_max = 1 << 16;

const VM = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: *std.Io.Writer,
    functions: []Function,
    stack: []Value,
    top: usize,
    frames: std.array_list.Managed(Frame),
    global_slots: []Value,
    vals: std.heap.ArenaAllocator,
    resp_status: u16 = 200,
    resp_headers: [32]std.http.Header = undefined,
    resp_header_count: usize = 0,
    req_headers: [64]std.http.Header = undefined,
    req_header_count: usize = 0,
    conns: std.array_list.Managed(?*sock.Conn),
    handlers: std.array_list.Managed(Handler),
    last_error: []const u8 = "",

    fn init(allocator: std.mem.Allocator, diags: *Diagnostics, out: *std.Io.Writer, functions: []Function, num_globals: usize) !VM {
        const slots = try allocator.alloc(Value, num_globals);
        for (slots) |*g| g.* = .kosong;
        return .{
            .allocator = allocator,
            .diags = diags,
            .out = out,
            .functions = functions,
            .stack = try allocator.alloc(Value, stack_max),
            .top = 0,
            .frames = std.array_list.Managed(Frame).init(allocator),
            .global_slots = slots,
            .vals = std.heap.ArenaAllocator.init(allocator),
            .conns = std.array_list.Managed(?*sock.Conn).init(allocator),
            .handlers = std.array_list.Managed(Handler).init(allocator),
        };
    }
    fn deinit(self: *VM) void {
        self.allocator.free(self.stack);
        self.frames.deinit();
        self.allocator.free(self.global_slots);
        self.vals.deinit();
        for (self.conns.items) |c| if (c) |s| sock.close(self.allocator, s);
        self.conns.deinit();
        self.handlers.deinit();
    }

    inline fn push(self: *VM, v: Value) void {
        self.stack[self.top] = v;
        self.top += 1;
    }
    inline fn pop(self: *VM) Value {
        self.top -= 1;
        return self.stack[self.top];
    }
    inline fn peek(self: *VM) Value {
        return self.stack[self.top - 1];
    }

    fn run(self: *VM) !void {
        try self.frames.append(.{ .func = &self.functions[0], .ip = 0, .base = 0 });
        try self.execLoop(0);
    }

    fn callTenunFn(self: *VM, fidx: usize, args: []const Value) !Value {
        const stop = self.frames.items.len;
        for (args) |a| self.push(a);
        const base = self.top - args.len;
        try self.frames.append(.{ .func = &self.functions[fidx], .ip = 0, .base = base });
        try self.execLoop(stop);
        return self.pop();
    }

    const Alir = enum { lanjut, selesai };

    fn execLoop(self: *VM, stop: usize) !void {
        while (true) {
            const alir = self.execOne(stop) catch |e| {
                if (e == error.RuntimeError and self.handlers.items.len > 0) {
                    const h = self.handlers.pop().?;
                    self.frames.shrinkRetainingCapacity(h.frame_len);
                    self.top = h.stack_top;
                    self.frames.items[self.frames.items.len - 1].ip = h.handler_ip;
                    self.push(.{ .teks = self.last_error });
                    continue;
                }
                return e;
            };
            if (alir == .selesai) return;
        }
    }

    fn execOne(self: *VM, stop: usize) !Alir {
        const frame = &self.frames.items[self.frames.items.len - 1];
        const code = frame.func.chunk.code.items;
        const op: OpCode = @enumFromInt(code[frame.ip]);
        frame.ip += 1;

        switch (op) {
            .constant => {
                const i = readU16(code, &frame.ip);
                self.push(frame.func.chunk.consts.items[i]);
            },
                .true_ => self.push(.{ .bool = true }),
                .false_ => self.push(.{ .bool = false }),
                .kosong_ => self.push(.kosong),
                .neg => {
                    const v = self.pop();
                    self.push(switch (v) {
                        .bulat => .{ .bulat = -v.bulat },
                        .desimal => .{ .desimal = -v.desimal },
                        else => unreachable,
                    });
                },
                .not => {
                    const v = self.pop();
                    self.push(.{ .bool = !v.bool });
                },
                .add, .sub, .mul, .div, .mod, .lt, .gt, .le, .ge, .bit_and, .bit_or, .bit_xor, .shl, .shr => try self.binary(op),
                .eq => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = valueEql(a, b) });
                },
                .neq => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .bool = !valueEql(a, b) });
                },
                .pop => _ = self.pop(),
                .define_global => {
                    const slot = readU16(code, &frame.ip);
                    self.global_slots[slot] = self.pop();
                },
                .get_global => {
                    const slot = readU16(code, &frame.ip);
                    self.push(self.global_slots[slot]);
                },
                .set_global => {
                    const slot = readU16(code, &frame.ip);
                    self.global_slots[slot] = self.peek();
                },
                .get_local => {
                    const slot = code[frame.ip];
                    frame.ip += 1;
                    self.push(self.stack[frame.base + slot]);
                },
                .set_local => {
                    const slot = code[frame.ip];
                    frame.ip += 1;
                    self.stack[frame.base + slot] = self.peek();
                },
                .jump => {
                    const off = readU16(code, &frame.ip);
                    frame.ip += off;
                },
                .jump_if_false => {
                    const off = readU16(code, &frame.ip);
                    if (!self.peek().bool) frame.ip += off;
                },
                .loop => {
                    const off = readU16(code, &frame.ip);
                    frame.ip -= off;
                },
                .print => {
                    try self.printValue(self.pop());
                    try self.out.writeByte('\n');
                },
                .array_make => {
                    const n = readU16(code, &frame.ip);
                    const arr = try self.vals.allocator().alloc(Value, n);
                    var k: usize = n;
                    while (k > 0) {
                        k -= 1;
                        arr[k] = self.pop();
                    }
                    self.push(.{ .array = arr });
                },
                .map_make => {
                    const n = readU16(code, &frame.ip);
                    const a = self.vals.allocator();
                    const m = try a.create(std.StringHashMap(Value));
                    m.* = std.StringHashMap(Value).init(a);
                    // entri di stack: key,value berpasangan; isi mundur lalu tukar
                    var pairs = try a.alloc(Value, n * 2);
                    var k: usize = n * 2;
                    while (k > 0) {
                        k -= 1;
                        pairs[k] = self.pop();
                    }
                    var j: usize = 0;
                    while (j < n) : (j += 1) {
                        try m.put(try a.dupe(u8, pairs[j * 2].teks), pairs[j * 2 + 1]);
                    }
                    self.push(.{ .peta = m });
                },
                .index_get => {
                    const idx = self.pop();
                    const target = self.pop();
                    if (std.meta.activeTag(target) == .peta) {
                        self.push(target.peta.get(idx.teks) orelse .{ .teks = "" });
                    } else {
                        if (idx.bulat < 0 or idx.bulat >= target.array.len) return self.rt("indeks larik di luar batas");
                        self.push(target.array[@intCast(idx.bulat)]);
                    }
                },
                .index_set => {
                    const value = self.pop();
                    const idx = self.pop();
                    const target = self.pop();
                    if (std.meta.activeTag(target) == .peta) {
                        const a = self.vals.allocator();
                        try target.peta.put(try a.dupe(u8, idx.teks), value);
                        self.push(value);
                    } else {
                        if (idx.bulat < 0 or idx.bulat >= target.array.len) return self.rt("indeks larik di luar batas");
                        target.array[@intCast(idx.bulat)] = value;
                        self.push(value);
                    }
                },
                .array_len => {
                    const v = self.pop();
                    self.push(.{ .bulat = @intCast(v.array.len) });
                },
                .builtin => {
                    const id = code[frame.ip];
                    const argc = code[frame.ip + 1];
                    frame.ip += 2;
                    var argbuf: [8]Value = undefined;
                    var k: usize = argc;
                    while (k > 0) {
                        k -= 1;
                        argbuf[k] = self.pop();
                    }
                    const result = try self.callBuiltin(id, argbuf[0..argc]);
                    self.push(result);
                },
                .call => {
                    const fidx = readU16(code, &frame.ip);
                    const argc = code[frame.ip];
                    frame.ip += 1;
                    const base = self.top - argc;
                    try self.frames.append(.{ .func = &self.functions[fidx], .ip = 0, .base = base });
                },
                .call_value => {
                    const argc = code[frame.ip];
                    frame.ip += 1;
                    const callee = self.pop();
                    if (std.meta.activeTag(callee) != .fungsi) return self.rt("nilai ini bukan fungsi");
                    const fidx = callee.fungsi;
                    if (self.functions[fidx].arity != argc) return self.rt("jumlah argumen tidak sesuai");
                    const base = self.top - argc;
                    try self.frames.append(.{ .func = &self.functions[fidx], .ip = 0, .base = base });
                },
                .coba_mulai => {
                    const off = readU16(code, &frame.ip);
                    try self.handlers.append(.{
                        .handler_ip = frame.ip + off,
                        .frame_len = self.frames.items.len,
                        .stack_top = self.top,
                    });
                },
                .coba_akhir => {
                    _ = self.handlers.pop();
                },
                .ret => {
                    const result = self.pop();
                    const done = self.frames.pop().?;
                    self.top = done.base;
                    self.push(result);
                    if (self.frames.items.len == stop) return .selesai;
                    return .lanjut;
                },
            }
        return .lanjut;
    }

    fn binary(self: *VM, op: OpCode) !void {
        const b = self.pop();
        const a = self.pop();
        if (std.meta.activeTag(a) == .teks and op == .add) {
            const joined = try std.fmt.allocPrint(self.vals.allocator(), "{s}{s}", .{ a.teks, b.teks });
            self.push(.{ .teks = joined });
            return;
        }
        if (std.meta.activeTag(a) == .bulat) {
            const x = a.bulat;
            const y = b.bulat;
            self.push(switch (op) {
                .add => .{ .bulat = x + y },
                .sub => .{ .bulat = x - y },
                .mul => .{ .bulat = x * y },
                .div => if (y == 0) return self.rt("pembagian dengan nol") else .{ .bulat = @divTrunc(x, y) },
                .mod => if (y == 0) return self.rt("modulo dengan nol") else .{ .bulat = @rem(x, y) },
                .lt => .{ .bool = x < y },
                .gt => .{ .bool = x > y },
                .le => .{ .bool = x <= y },
                .ge => .{ .bool = x >= y },
                .bit_and => .{ .bulat = x & y },
                .bit_or => .{ .bulat = x | y },
                .bit_xor => .{ .bulat = x ^ y },
                .shl => .{ .bulat = std.math.shl(i64, x, y) },
                .shr => .{ .bulat = std.math.shr(i64, x, y) },
                else => unreachable,
            });
        } else {
            const x = a.desimal;
            const y = b.desimal;
            self.push(switch (op) {
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
            });
        }
    }

    fn callBuiltin(self: *VM, id: usize, args: []const Value) !Value {
        const a = self.vals.allocator();
        return switch (id) {
            0 => .{ .teks = http.get(a, args[0].teks) catch return self.rt("gagal mengambil URL") },
            1 => .{ .desimal = @sqrt(args[0].desimal) },
            2 => .{ .desimal = std.math.pow(f64, args[0].desimal, args[1].desimal) },
            3 => .{ .desimal = @abs(args[0].desimal) },
            4 => .{ .bulat = @intFromFloat(@round(args[0].desimal)) },
            5 => .{ .bulat = @intCast(args[0].teks.len) },
            6 => .{ .teks = text.potong(a, args[0].teks, args[1].bulat, args[2].bulat) catch return self.rt("gagal memotong teks") },
            7 => .{ .teks = fs.baca(a, args[0].teks) catch return self.rt("gagal membaca file") },
            8 => blk: {
                fs.tulis(args[0].teks, args[1].teks) catch return self.rt("gagal menulis file");
                break :blk Value.kosong;
            },
            9 => self.serve(@intCast(args[0].bulat)),
            61 => self.serveSoket(@intCast(args[0].bulat)),
            62 => blk: {
                siar.broadcast(args[0].teks);
                break :blk Value.kosong;
            },
            63 => blk: {
                const arr = a.alloc(Value, argv.list.len) catch return self.rt("kehabisan memori");
                for (argv.list, 0..) |s, i| arr[i] = .{ .teks = s };
                break :blk Value{ .array = arr };
            },
            64 => .{ .bulat = runtime.waktuDetik() },
            65 => blk: {
                const lo = args[0].bulat;
                const hi = args[1].bulat;
                if (hi <= lo) break :blk Value{ .bulat = lo };
                break :blk Value{ .bulat = runtime.acakRentang(lo, hi) };
            },
            66 => .{ .desimal = std.fmt.parseFloat(f64, std.mem.trim(u8, args[0].teks, " \t\r\n")) catch 0 },
            67 => .{ .teks = text.pangkas(a, args[0].teks) catch return self.rt("gagal pangkas") },
            68 => .{ .teks = text.keBesar(a, args[0].teks) catch return self.rt("gagal keBesar") },
            69 => .{ .teks = text.keKecil(a, args[0].teks) catch return self.rt("gagal keKecil") },
            70 => .{ .teks = waktu.tanggal(a, args[0].bulat, args[1].bulat) catch return self.rt("gagal tanggal") },
            71 => .{ .bulat = runtime.waktuMili() },
            72 => .{ .teks = os.info(a, args[0].teks) catch return self.rt("gagal infoOS") },
            73 => .{ .teks = os.lingkungan(a, args[0].teks) catch return self.rt("gagal lingkungan") },
            74 => .{ .teks = proses.jalankan(a, args[0].teks) catch return self.rt("gagal jalankan") },
            75 => blk: {
                const list = fs.daftar(a, args[0].teks) catch return self.rt("gagal daftar berkas");
                const arr = a.alloc(Value, list.len) catch return self.rt("kehabisan memori");
                for (list, 0..) |s, i| arr[i] = .{ .teks = s };
                break :blk Value{ .array = arr };
            },
            76 => blk: {
                fs.buatDir(args[0].teks);
                break :blk Value.kosong;
            },
            77 => blk: {
                fs.hapusBerkas(args[0].teks);
                break :blk Value.kosong;
            },
            78 => blk: {
                fs.hapusDir(args[0].teks);
                break :blk Value.kosong;
            },
            79 => .{ .bulat = fs.ukuran(args[0].teks) },
            80 => .{ .bool = fs.apakahDir(args[0].teks) },
            81 => .{ .desimal = @exp(args[0].desimal) },
            82 => .{ .desimal = @log(args[0].desimal) },
            83 => .{ .desimal = @log10(args[0].desimal) },
            84 => .{ .desimal = @sin(args[0].desimal) },
            85 => .{ .desimal = @cos(args[0].desimal) },
            86 => .{ .desimal = @tan(args[0].desimal) },
            87 => .{ .desimal = std.math.tanh(args[0].desimal) },
            88 => .{ .desimal = @floor(args[0].desimal) },
            89 => .{ .desimal = @ceil(args[0].desimal) },
            90 => .{ .desimal = runtime.acakFloat() },
            91 => .{ .desimal = @floatFromInt(args[0].bulat) },
            92 => .{ .bulat = @intFromFloat(@trunc(args[0].desimal)) },
            93 => .{ .teks = std.fmt.allocPrint(a, "{d}", .{args[0].desimal}) catch return self.rt("kehabisan memori") },
            94 => .{ .teks = gambar.bacaPng(a, args[0].teks) catch return self.rt("gagal baca gambar PNG") },
            10 => blk: {
                self.resp_status = @intCast(args[0].bulat);
                break :blk Value.kosong;
            },
            11 => blk: {
                if (self.resp_header_count < self.resp_headers.len) {
                    self.resp_headers[self.resp_header_count] = .{
                        .name = a.dupe(u8, args[0].teks) catch args[0].teks,
                        .value = a.dupe(u8, args[1].teks) catch args[1].teks,
                    };
                    self.resp_header_count += 1;
                }
                break :blk Value.kosong;
            },
            12 => .{ .bulat = text.cari(args[0].teks, args[1].teks) },
            13 => .{ .teks = text.ganti(a, args[0].teks, args[1].teks, args[2].teks) catch return self.rt("gagal ganti teks") },
            14 => blk: {
                const parts = text.pisah(a, args[0].teks, args[1].teks) catch return self.rt("gagal pisah teks");
                const arr = a.alloc(Value, parts.len) catch return self.rt("kehabisan memori");
                for (parts, 0..) |p, i| arr[i] = .{ .teks = p };
                break :blk Value{ .array = arr };
            },
            15 => blk: {
                const arr = args[0].array;
                var buf = std.array_list.Managed(u8).init(a);
                for (arr, 0..) |el, i| {
                    if (i > 0) buf.appendSlice(args[1].teks) catch {};
                    buf.appendSlice(el.teks) catch {};
                }
                break :blk Value{ .teks = buf.toOwnedSlice() catch return self.rt("kehabisan memori") };
            },
            16 => .{ .bool = text.mulaiDengan(args[0].teks, args[1].teks) },
            17 => .{ .bool = text.akhiriDengan(args[0].teks, args[1].teks) },
            18 => .{ .teks = text.tipeKonten(args[0].teks) },
            19 => .{ .teks = json.teks(a, args[0].teks, args[1].teks) },
            20 => .{ .bulat = json.angka(a, args[0].teks, args[1].teks) },
            21 => .{ .bool = json.boolean(a, args[0].teks, args[1].teks) },
            22 => .{ .bool = fs.ada(args[0].teks) },
            23 => .{ .teks = text.kueri(a, args[0].teks, args[1].teks) catch return self.rt("gagal urai kueri") },
            24 => .{ .teks = text.form(a, args[0].teks, args[1].teks) catch return self.rt("gagal urai form") },
            25 => .{ .teks = self.reqHeader(args[0].teks) },
            26 => .{ .teks = text.cookieAmbil(a, self.reqHeader("cookie"), args[0].teks) catch return self.rt("gagal baca cookie") },
            27 => blk: {
                kv.simpan(a, args[0].teks, args[1].teks) catch return self.rt("gagal simpan data");
                break :blk Value.kosong;
            },
            28 => .{ .teks = kv.muat(a, args[0].teks) },
            29 => blk: {
                kv.hapus(a, args[0].teks) catch return self.rt("gagal hapus data");
                break :blk Value.kosong;
            },
            30 => blk: {
                const conn = sock.connect(self.allocator, args[0].teks, @intCast(args[1].bulat)) catch break :blk Value{ .bulat = -1 };
                self.conns.append(conn) catch return self.rt("kehabisan memori");
                break :blk Value{ .bulat = @intCast(self.conns.items.len - 1) };
            },
            31 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    sock.send(s, args[1].teks) catch return self.rt("gagal mengirim");
                };
                break :blk Value.kosong;
            },
            32 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                const maks: usize = @intCast(args[1].bulat);
                const buf = a.alloc(u8, maks) catch return self.rt("kehabisan memori");
                var n: usize = 0;
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    n = sock.recv(s, buf);
                };
                break :blk Value{ .teks = buf[0..n] };
            },
            33 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    sock.close(self.allocator, s);
                    self.conns.items[sid] = null;
                };
                break :blk Value.kosong;
            },
            34 => .{ .teks = crypto.sha256(a, args[0].teks) catch return self.rt("gagal sha256") },
            35 => .{ .teks = crypto.sha1(a, args[0].teks) catch return self.rt("gagal sha1") },
            36 => .{ .teks = crypto.md5(a, args[0].teks) catch return self.rt("gagal md5") },
            37 => .{ .teks = crypto.hmacSha256(a, args[0].teks, args[1].teks) catch return self.rt("gagal hmac") },
            38 => .{ .teks = crypto.base64Enkode(a, args[0].teks) catch return self.rt("gagal base64") },
            39 => .{ .teks = crypto.base64Dekode(a, args[0].teks) catch return self.rt("base64 tidak valid") },
            40 => .{ .teks = crypto.acak(a, @intCast(args[0].bulat)) catch return self.rt("gagal acak") },
            41 => .{ .teks = binmod.keByte(a, args[0].bulat, args[1].bulat, args[2].bool) catch return self.rt("gagal keByte") },
            42 => .{ .bulat = binmod.bacaInt(args[0].teks, args[1].bulat, args[2].bulat, args[3].bool) },
            43 => .{ .teks = crypto.sha1Raw(a, args[0].teks) catch return self.rt("gagal sha1Raw") },
            44 => .{ .teks = crypto.xorBytes(a, args[0].teks, args[1].teks) catch return self.rt("gagal xor") },
            45 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                const n: usize = @intCast(args[1].bulat);
                const buf = a.alloc(u8, n) catch return self.rt("kehabisan memori");
                var got: usize = 0;
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    got = sock.recvExact(s, buf);
                };
                break :blk Value{ .teks = buf[0..got] };
            },
            46 => .{ .bulat = std.fmt.parseInt(i64, std.mem.trim(u8, args[0].teks, " \t\r\n"), 10) catch 0 },
            47 => .{ .teks = std.fmt.allocPrint(a, "{d}", .{args[0].bulat}) catch return self.rt("kehabisan memori") },
            48 => blk: {
                const src = args[0].array;
                const arr = a.alloc(Value, src.len + 1) catch return self.rt("kehabisan memori");
                for (src, 0..) |v, i| arr[i] = v;
                arr[src.len] = args[1];
                break :blk Value{ .array = arr };
            },
            49 => .{ .teks = crypto.sha256Raw(a, args[0].teks) catch return self.rt("gagal sha256Raw") },
            50 => .{ .teks = crypto.hmacSha256Raw(a, args[0].teks, args[1].teks) catch return self.rt("gagal hmac raw") },
            51 => .{ .teks = crypto.pbkdf2Sha256(a, args[0].teks, args[1].teks, args[2].bulat) catch return self.rt("gagal pbkdf2") },
            52 => .{ .teks = binmod.bacaFloat(a, args[0].teks, args[1].bulat, args[2].bulat) catch return self.rt("gagal bacaFloat") },
            53 => .{ .bool = args[0].peta.contains(args[1].teks) },
            54 => blk: {
                const m = args[0].peta;
                const arr = a.alloc(Value, m.count()) catch return self.rt("kehabisan memori");
                var it = m.keyIterator();
                var i: usize = 0;
                while (it.next()) |k| : (i += 1) arr[i] = .{ .teks = k.* };
                break :blk Value{ .array = arr };
            },
            55 => blk: {
                _ = args[0].peta.remove(args[1].teks);
                break :blk Value.kosong;
            },
            56 => .{ .teks = http.kirim(a, args[0].teks, args[1].teks, args[2].teks, args[3].teks) catch return self.rt("gagal kirim HTTP") },
            57 => .{ .bulat = tls.connect(args[0].teks, @intCast(args[1].bulat)) catch -1 },
            58 => blk: {
                tls.send(args[0].bulat, args[1].teks) catch return self.rt("gagal kirim TLS");
                break :blk Value.kosong;
            },
            59 => .{ .teks = tls.recv(a, args[0].bulat, @intCast(args[1].bulat)) catch return self.rt("gagal terima TLS") },
            60 => blk: {
                tls.close(args[0].bulat);
                break :blk Value.kosong;
            },
            95 => blk: {
                uji.tegas(args[0].bool, args[1].teks);
                break :blk Value.kosong;
            },
            96 => blk: {
                uji.tegasSama(args[0].teks, args[1].teks, args[2].teks);
                break :blk Value.kosong;
            },
            97 => blk: {
                uji.tegasSamaBulat(args[0].bulat, args[1].bulat, args[2].teks);
                break :blk Value.kosong;
            },
            else => unreachable,
        };
    }

    fn reqHeader(self: *VM, name: []const u8) []const u8 {
        for (self.req_headers[0..self.req_header_count]) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return "";
    }

    fn serve(self: *VM, port_arg: u16) !Value {
        const tangani_idx = blk: {
            for (self.functions, 0..) |f, i| {
                if (std.mem.eql(u8, f.name, "tangani")) break :blk i;
            }
            return self.rt("server butuh fungsi 'tangani(metode: teks, jalur: teks, badan: teks): teks'");
        };
        // Port: env TENUN_PORT bila ada (untuk deploy/reverse-proxy), selain itu argumen.
        var port: u16 = port_arg;
        if (runtime.getenv("TENUN_PORT")) |pv| {
            if (std.fmt.parseInt(u16, std.mem.trim(u8, pv, " \t\r\n"), 10)) |p| port = p else |_| {}
        }
        const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", port) catch return self.rt("alamat tidak valid");
        var listener = addr.listen(runtime.io, .{ .reuse_address = true }) catch return self.rt("gagal mendengarkan di port");

        // Jumlah worker: env TENUN_WORKERS bila ada, selain itu jumlah CPU.
        // Set TENUN_WORKERS=1 untuk app yang memakai koneksi soket (DB/Redis) per
        // proses; skalakan dengan menjalankan banyak proses di belakang load balancer.
        var workers = @max(@as(usize, 1), std.Thread.getCpuCount() catch 4);
        if (runtime.getenv("TENUN_WORKERS")) |wv| {
            if (std.fmt.parseInt(usize, std.mem.trim(u8, wv, " \t\r\n"), 10)) |n| {
                if (n >= 1) workers = n;
            } else |_| {}
        }
        runtime.galat("[tenun] server berjalan di http://localhost:{d} ({d} worker)\n", .{ port, workers });

        const ctx = WorkerCtx{
            .allocator = self.allocator,
            .diags = self.diags,
            .out = self.out,
            .functions = self.functions,
            .tangani_idx = tangani_idx,
            .src_globals = self.global_slots,
            .listener = &listener,
        };

        var t: usize = 1;
        while (t < workers) : (t += 1) {
            _ = std.Thread.spawn(.{}, workerLoop, .{ctx}) catch {};
        }
        workerLoop(ctx);
        return .kosong;
    }

    // Server soket mentah: tiap koneksi dapat thread + VM sendiri, lalu memanggil
    // fungsi 'koneksi(soket: bulat)'. Dipakai untuk WebSocket/protokol kustom.
    fn serveSoket(self: *VM, port: u16) !Value {
        const koneksi_idx = blk: {
            for (self.functions, 0..) |f, i| {
                if (std.mem.eql(u8, f.name, "koneksi")) break :blk i;
            }
            return self.rt("server soket butuh fungsi 'koneksi(soket: bulat): kosong'");
        };
        const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", port) catch return self.rt("alamat tidak valid");
        var listener = addr.listen(runtime.io, .{ .reuse_address = true }) catch return self.rt("gagal mendengarkan di port");
        runtime.galat("[tenun] server soket di port {d}\n", .{port});

        while (true) {
            const stream = listener.accept(runtime.io) catch continue;
            const ctx = SoketConnCtx{
                .allocator = self.allocator,
                .diags = self.diags,
                .out = self.out,
                .functions = self.functions,
                .koneksi_idx = koneksi_idx,
                .src_globals = self.global_slots,
                .stream = stream,
            };
            _ = std.Thread.spawn(.{}, soketConnLoop, .{ctx}) catch {
                stream.close(runtime.io);
            };
        }
        return .kosong;
    }

    fn handleConn(self: *VM, stream: std.Io.net.Stream, tangani_idx: usize) void {
        var keep_open = false;
        defer if (!keep_open) stream.close(runtime.io);
        var rbuf: [65536]u8 = undefined;
        var wbuf: [65536]u8 = undefined;
        var sreader = stream.reader(runtime.io, &rbuf);
        var swriter = stream.writer(runtime.io, &wbuf);
        var hs = std.http.Server.init(&sreader.interface, &swriter.interface);
        var req = hs.receiveHead() catch return;
        const a = self.vals.allocator();
        const metode = a.dupe(u8, @tagName(req.head.method)) catch "GET";
        const path = a.dupe(u8, req.head.target) catch "/";

        // Tangkap header request SEBELUM baca badan (readerExpectNone meng-invalidasi Head).
        self.resp_status = 200;
        self.resp_header_count = 0;
        self.req_header_count = 0;
        var hit = req.iterateHeaders();
        while (hit.next()) |h| {
            if (self.req_header_count < self.req_headers.len) {
                self.req_headers[self.req_header_count] = .{
                    .name = a.dupe(u8, h.name) catch h.name,
                    .value = a.dupe(u8, h.value) catch h.value,
                };
                self.req_header_count += 1;
            }
        }
        // Deteksi upgrade WebSocket -> layani di proses & port yang sama.
        var ws_upgrade = false;
        var ws_key: ?[]const u8 = null;
        {
            var i: usize = 0;
            while (i < self.req_header_count) : (i += 1) {
                const hn = self.req_headers[i].name;
                const hv = self.req_headers[i].value;
                if (std.ascii.eqlIgnoreCase(hn, "upgrade") and std.ascii.indexOfIgnoreCase(hv, "websocket") != null) ws_upgrade = true;
                if (std.ascii.eqlIgnoreCase(hn, "sec-websocket-key")) ws_key = hv;
            }
        }
        if (ws_upgrade) {
            if (ws_key) |k| {
                if (wsUpgrade(stream, k)) keep_open = true; // reader thread memiliki stream
                return;
            }
        }

        var bbuf: [65536]u8 = undefined;
        const body_reader = req.readerExpectNone(&bbuf);
        const badan = body_reader.allocRemaining(a, std.Io.Limit.limited(16 * 1024 * 1024)) catch "";

        const res = self.callTenunFn(tangani_idx, &.{ .{ .teks = metode }, .{ .teks = path }, .{ .teks = badan } }) catch Value.kosong;
        const body = if (std.meta.activeTag(res) == .teks) res.teks else "";
        req.respond(body, .{
            .status = @enumFromInt(self.resp_status),
            .extra_headers = self.resp_headers[0..self.resp_header_count],
        }) catch {};
    }

    fn printValue(self: *VM, v: Value) !void {
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
            .peta => |m| {
                try self.out.writeByte('{');
                var it = m.iterator();
                var first = true;
                while (it.next()) |e| {
                    if (!first) try self.out.writeAll(", ");
                    first = false;
                    try self.out.print("\"{s}\": ", .{e.key_ptr.*});
                    try self.printValue(e.value_ptr.*);
                }
                try self.out.writeByte('}');
            },
            .fungsi => |fi| try self.out.print("<fungsi {s}>", .{self.functions[fi].name}),
        }
    }

    fn rt(self: *VM, message: []const u8) anyerror {
        self.last_error = message;
        self.diags.report(.err, 0, 0, message) catch {};
        return error.RuntimeError;
    }
};

// ---- WebSocket di port HTTP yang sama (broadcast lewat registry siar) ----

fn wsReadExact(r: *std.Io.Reader, buf: []u8) bool {
    r.readSliceAll(buf) catch return false;
    return true;
}

// Baca satu frame WS. Kembalikan payload teks/biner, atau null bila tutup/error.
fn wsReadFrame(r: *std.Io.Reader, a: std.mem.Allocator) ?[]u8 {
    var h: [2]u8 = undefined;
    if (!wsReadExact(r, &h)) return null;
    const opcode: u8 = h[0] & 0x0f;
    const masked: bool = (h[1] & 0x80) != 0;
    var len: u64 = @as(u64, h[1] & 0x7f);
    if (len == 126) {
        var e: [2]u8 = undefined;
        if (!wsReadExact(r, &e)) return null;
        len = (@as(u64, e[0]) << 8) | @as(u64, e[1]);
    } else if (len == 127) {
        var e: [8]u8 = undefined;
        if (!wsReadExact(r, &e)) return null;
        len = 0;
        for (e) |b| len = (len << 8) | @as(u64, b);
    }
    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) {
        if (!wsReadExact(r, &mask)) return null;
    }
    if (len > 16 * 1024 * 1024) return null;
    const payload = a.alloc(u8, @intCast(len)) catch return null;
    if (!wsReadExact(r, payload)) return null;
    if (masked) {
        var i: usize = 0;
        while (i < payload.len) : (i += 1) payload[i] ^= mask[i % 4];
    }
    if (opcode == 0x8) return null; // close
    if (opcode == 0x9 or opcode == 0xA) return wsReadFrame(r, a); // ping/pong -> abaikan
    return payload;
}

// Bangun frame teks server->klien (tanpa mask).
fn wsTextFrame(a: std.mem.Allocator, payload: []const u8) ?[]u8 {
    var hdr: [10]u8 = undefined;
    var hlen: usize = 0;
    hdr[0] = 0x81;
    if (payload.len < 126) {
        hdr[1] = @intCast(payload.len);
        hlen = 2;
    } else if (payload.len < 65536) {
        hdr[1] = 126;
        hdr[2] = @intCast((payload.len >> 8) & 0xff);
        hdr[3] = @intCast(payload.len & 0xff);
        hlen = 4;
    } else {
        hdr[1] = 127;
        var i: usize = 0;
        while (i < 8) : (i += 1) hdr[2 + i] = @intCast((payload.len >> @intCast((7 - i) * 8)) & 0xff);
        hlen = 10;
    }
    const out = a.alloc(u8, hlen + payload.len) catch return null;
    @memcpy(out[0..hlen], hdr[0..hlen]);
    @memcpy(out[hlen..], payload);
    return out;
}

const WsCtx = struct { stream: std.Io.net.Stream, id: i64 };

// Loop baca frame WS + broadcast. Jalan di thread sendiri (hanya baca soket
// masuk + kirim broadcast; tak ada koneksi keluar -> aman lintas-thread).
fn wsReaderLoop(ctx: WsCtx) void {
    const a = std.heap.page_allocator;
    defer {
        siar.unregister(ctx.id);
        ctx.stream.close(runtime.io);
    }
    var rbuf: [16 * 1024]u8 = undefined;
    var sr = ctx.stream.reader(runtime.io, &rbuf);
    const r = &sr.interface;
    while (true) {
        const msg = wsReadFrame(r, a) orelse break;
        defer a.free(msg);
        if (wsTextFrame(a, msg)) |frame| {
            defer a.free(frame);
            siar.broadcast(frame);
        }
    }
}

// Handshake WS lalu serahkan koneksi ke thread pembaca. Kembalikan true bila
// stream diambil-alih (worker tak boleh menutupnya). Worker langsung bebas lagi.
fn wsUpgrade(stream: std.Io.net.Stream, key: []const u8) bool {
    var sha = std.crypto.hash.Sha1.init(.{});
    sha.update(key);
    sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [20]u8 = undefined;
    sha.final(&digest);
    var accbuf: [40]u8 = undefined;
    const acc = std.base64.standard.Encoder.encode(&accbuf, &digest);

    var respbuf: [200]u8 = undefined;
    const resp = std.fmt.bufPrint(&respbuf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{acc}) catch return false;
    var wbuf: [256]u8 = undefined;
    var sw = stream.writer(runtime.io, &wbuf);
    sw.interface.writeAll(resp) catch return false;
    sw.interface.flush() catch return false;

    const id = siar.register(stream);
    const ctx = WsCtx{ .stream = stream, .id = id };
    _ = std.Thread.spawn(.{}, wsReaderLoop, .{ctx}) catch {
        siar.unregister(id);
        return false;
    };
    return true;
}

const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: *std.Io.Writer,
    functions: []Function,
    tangani_idx: usize,
    src_globals: []Value,
    listener: *std.Io.net.Server,
};

const SoketConnCtx = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: *std.Io.Writer,
    functions: []Function,
    koneksi_idx: usize,
    src_globals: []Value,
    stream: std.Io.net.Stream,
};

fn soketConnLoop(ctx: SoketConnCtx) void {
    var vm = VM.init(ctx.allocator, ctx.diags, ctx.out, ctx.functions, ctx.src_globals.len) catch {
        ctx.stream.close(runtime.io);
        return;
    };
    defer vm.deinit(); // menutup semua conns termasuk stream ini
    @memcpy(vm.global_slots, ctx.src_globals);
    const conn = sock.wrap(ctx.allocator, ctx.stream) catch {
        ctx.stream.close(runtime.io);
        return;
    };
    vm.conns.append(conn) catch {
        sock.close(ctx.allocator, conn);
        return;
    };
    const bid = siar.register(ctx.stream);
    defer siar.unregister(bid);
    const handle: i64 = @intCast(vm.conns.items.len - 1);
    _ = vm.callTenunFn(ctx.koneksi_idx, &.{.{ .bulat = handle }}) catch {};
}

fn workerLoop(ctx: WorkerCtx) void {
    var vm = VM.init(ctx.allocator, ctx.diags, ctx.out, ctx.functions, ctx.src_globals.len) catch return;
    defer vm.deinit();
    @memcpy(vm.global_slots, ctx.src_globals);
    while (true) {
        const stream = ctx.listener.accept(runtime.io) catch continue;
        vm.handleConn(stream, ctx.tangani_idx);
        _ = vm.vals.reset(.retain_capacity);
    }
}

fn readU16(code: []const u8, ip: *usize) u16 {
    const hi: u16 = code[ip.*];
    const lo: u16 = code[ip.* + 1];
    ip.* += 2;
    return (hi << 8) | lo;
}

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
            for (a.array, b.array) |x, y| if (!valueEql(x, y)) break :blk false;
            break :blk true;
        },
        .peta => a.peta == b.peta,
        .fungsi => a.fungsi == b.fungsi,
    };
}

pub fn run(allocator: std.mem.Allocator, program: ast.Program, diags: *Diagnostics, out: *std.Io.Writer) !void {
    var compiler = Compiler.init(allocator, diags);
    defer compiler.deinit();
    try compiler.compileProgram(program);
    if (diags.hasErrors()) return;

    var vm = try VM.init(allocator, diags, out, compiler.functions.items, compiler.global_index.count());
    defer vm.deinit();
    try vm.run();
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

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    runtime.io = threaded.io();

    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    try run(allocator, program, &diags, &aw.writer);
    return aw.toOwnedSlice();
}

fn expectOutput(source: []const u8, expected: []const u8) !void {
    const out = try runToString(std.testing.allocator, source);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(expected, out);
}

test "vm: cetak teks dan aritmatika" {
    try expectOutput("cetak(\"halo\"); cetak(1 + 2 * 3);", "halo\n7\n");
}
test "vm: konkatenasi" {
    try expectOutput("biar n = \"Tenun\"; cetak(\"Halo, \" + n);", "Halo, Tenun\n");
}
test "vm: kalau lain" {
    try expectOutput("biar x: bulat = 3; kalau x > 5 { cetak(\"besar\"); } lain { cetak(\"kecil\"); }", "kecil\n");
}
test "vm: selama" {
    try expectOutput("biar n: bulat = 3; selama n > 0 { cetak(n); n = n - 1; }", "3\n2\n1\n");
}
test "vm: untuk" {
    try expectOutput("untuk i dari 1 sampai 4 { cetak(i); }", "1\n2\n3\n");
}
test "vm: fungsi rekursi" {
    try expectOutput(
        \\fungsi faktorial(n: bulat): bulat {
        \\  kalau n <= 1 { kembali 1; }
        \\  kembali n * faktorial(n - 1);
        \\}
        \\cetak(faktorial(5));
    , "120\n");
}
test "vm: fungsi panggil sebelum definisi" {
    try expectOutput("cetak(kuadrat(4)); fungsi kuadrat(x: bulat): bulat { kembali x * x; }", "16\n");
}
test "vm: logika short-circuit" {
    try expectOutput("cetak(benar && salah); cetak(benar || salah); cetak(!benar);", "salah\nbenar\nsalah\n");
}
test "vm: larik dan panjang" {
    try expectOutput("biar a: []bulat = [10, 20, 30]; cetak(a[1]); cetak(panjang(a)); cetak(a);", "20\n3\n[10, 20, 30]\n");
}
test "vm: isi larik lewat untuk" {
    try expectOutput(
        \\biar a: []bulat = [0, 0, 0];
        \\untuk i dari 0 sampai 3 { a[i] = i * i; }
        \\cetak(a);
    , "[0, 1, 4]\n");
}
