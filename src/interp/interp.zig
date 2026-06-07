const std = @import("std");
const rt = @import("../rt.zig");
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
const binary = @import("../builtins/binary.zig");
const tls = @import("../builtins/tls.zig");
const siar = @import("../builtins/siar.zig");
const argv = @import("../builtins/argv.zig");
const waktu = @import("../builtins/waktu.zig");
const os = @import("../builtins/os.zig");
const proses = @import("../builtins/proses.zig");
const gambar = @import("../builtins/gambar.zig");

pub const Value = union(enum) {
    bulat: i64,
    desimal: f64,
    teks: []const u8,
    bool: bool,
    kosong,
    array: []Value,
    peta: *std.StringHashMap(Value), // map teks -> nilai apa pun (dinamis)
    fungsi: *ast.Stmt, // deklarasi fungsi (first-class)
};

const Scope = std.StringHashMap(Value);

pub const Error = anyerror;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    diags: *Diagnostics,
    out: *std.Io.Writer,
    functions: std.StringHashMap(*ast.Stmt),
    global: Scope,
    locals: std.array_list.Managed(Scope),
    vals: std.heap.ArenaAllocator,
    returning: bool = false,
    breaking: bool = false,
    continuing: bool = false,
    last_error: []const u8 = "",
    ret_value: Value = .kosong,
    resp_status: u16 = 200,
    resp_headers: [32]std.http.Header = undefined,
    resp_header_count: usize = 0,
    req_headers: [64]std.http.Header = undefined,
    req_header_count: usize = 0,
    conns: std.array_list.Managed(?*sock.Conn),

    pub fn init(allocator: std.mem.Allocator, diags: *Diagnostics, out: *std.Io.Writer) Interpreter {
        return .{
            .allocator = allocator,
            .diags = diags,
            .out = out,
            .functions = std.StringHashMap(*ast.Stmt).init(allocator),
            .global = Scope.init(allocator),
            .locals = std.array_list.Managed(Scope).init(allocator),
            .vals = std.heap.ArenaAllocator.init(allocator),
            .conns = std.array_list.Managed(?*sock.Conn).init(allocator),
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.functions.deinit();
        self.global.deinit();
        for (self.locals.items) |*sc| sc.deinit();
        self.locals.deinit();
        self.vals.deinit();
        for (self.conns.items) |c| if (c) |s| sock.close(self.allocator, s);
        self.conns.deinit();
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
                    if (self.breaking) {
                        self.breaking = false;
                        break;
                    }
                    if (self.continuing) self.continuing = false;
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
                    if (self.breaking) {
                        self.breaking = false;
                        break;
                    }
                    if (self.continuing) self.continuing = false;
                }
            },
            .foreach_stmt => |d| {
                const arr = try self.eval(d.iter);
                try self.locals.append(Scope.init(self.allocator));
                defer {
                    var sc = self.locals.pop().?;
                    sc.deinit();
                }
                const loop_idx = self.locals.items.len - 1;
                for (arr.array) |el| {
                    try self.locals.items[loop_idx].put(d.var_name, el);
                    try self.execBlock(d.body);
                    if (self.returning) break;
                    if (self.breaking) {
                        self.breaking = false;
                        break;
                    }
                    if (self.continuing) self.continuing = false;
                }
            },
            .return_stmt => |maybe| {
                self.ret_value = if (maybe) |e| try self.eval(e) else .kosong;
                self.returning = true;
            },
            .break_stmt => self.breaking = true,
            .continue_stmt => self.continuing = true,
            .match_stmt => |d| {
                const subj = try self.eval(d.subject);
                var matched = false;
                for (d.arms) |arm| {
                    const v = try self.eval(arm.value);
                    if (valueEql(subj, v)) {
                        try self.execBlock(arm.body);
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    if (d.default) |def| try self.execBlock(def);
                }
            },
            .try_stmt => |d| {
                self.execBlock(d.body) catch |e| {
                    if (e == error.RuntimeError) {
                        try self.locals.append(Scope.init(self.allocator));
                        defer {
                            var sc = self.locals.pop().?;
                            sc.deinit();
                        }
                        try self.locals.items[self.locals.items.len - 1].put(d.err_name, .{ .teks = self.last_error });
                        try self.execBlock(d.handler);
                    } else return e;
                };
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
            if (self.returning or self.breaking or self.continuing) break;
        }
    }

    fn eval(self: *Interpreter, expr: *ast.Expr) Error!Value {
        switch (expr.data) {
            .number => |s| {
                if (std.mem.indexOfScalar(u8, s, '.') != null) {
                    return .{ .desimal = std.fmt.parseFloat(f64, s) catch 0 };
                }
                return .{ .bulat = std.fmt.parseInt(i64, s, 0) catch 0 };
            },
            .string => |s| return .{ .teks = s },
            .boolean => |b| return .{ .bool = b },
            .nil => return .kosong,
            .ident => |name| {
                if (self.get(name)) |v| return v;
                if (self.functions.get(name)) |stmt| return .{ .fungsi = stmt };
                return self.runtimeError(expr.pos, "nama tidak dikenal");
            },
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
                        const tgt = try self.eval(ix.target);
                        const idx = try self.eval(ix.idx);
                        if (std.meta.activeTag(tgt) == .peta) {
                            const al = self.vals.allocator();
                            try tgt.peta.put(try al.dupe(u8, idx.teks), v);
                        } else {
                            if (idx.bulat < 0 or idx.bulat >= tgt.array.len) {
                                return self.runtimeError(ix.target.pos, "indeks larik di luar batas");
                            }
                            tgt.array[@intCast(idx.bulat)] = v;
                        }
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
            .map_lit => |entries| {
                const a = self.vals.allocator();
                const m = try a.create(std.StringHashMap(Value));
                m.* = std.StringHashMap(Value).init(a);
                for (entries) |e| {
                    const k = try self.eval(e.key);
                    const val = try self.eval(e.value);
                    try m.put(try a.dupe(u8, k.teks), val);
                }
                return .{ .peta = m };
            },
            .index => |ix| {
                const target = try self.eval(ix.target);
                const idx = try self.eval(ix.idx);
                if (std.meta.activeTag(target) == .peta) {
                    return target.peta.get(idx.teks) orelse .{ .teks = "" };
                }
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
                .bit_and => .{ .bulat = x & y },
                .bit_or => .{ .bulat = x | y },
                .bit_xor => .{ .bulat = x ^ y },
                .shl => .{ .bulat = std.math.shl(i64, x, y) },
                .shr => .{ .bulat = std.math.shr(i64, x, y) },
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
        if (std.meta.activeTag(c.callee.data) == .ident) {
            const name = c.callee.data.ident;
            // Jalur khusus hanya bila nama bukan variabel (tak ter-shadow).
            if (self.get(name) == null) {
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
                if (spec.indexOf(name)) |id| {
                    var argbuf: [8]Value = undefined;
                    for (c.args, 0..) |a, i| argbuf[i] = try self.eval(a);
                    return self.callBuiltin(id, argbuf[0..c.args.len], c.callee.pos);
                }
                if (self.functions.get(name)) |fn_stmt| {
                    var av = try self.allocator.alloc(Value, c.args.len);
                    defer self.allocator.free(av);
                    for (c.args, 0..) |arg, i| av[i] = try self.eval(arg);
                    return self.invokeUser(fn_stmt, av);
                }
            }
        }
        // Panggilan tak langsung: evaluasi callee jadi nilai fungsi.
        const callee = try self.eval(c.callee);
        if (std.meta.activeTag(callee) != .fungsi) return self.runtimeError(c.callee.pos, "nilai ini bukan fungsi");
        var arg_values = try self.allocator.alloc(Value, c.args.len);
        defer self.allocator.free(arg_values);
        for (c.args, 0..) |arg, i| arg_values[i] = try self.eval(arg);
        return self.invokeUser(callee.fungsi, arg_values);
    }

    fn invokeUser(self: *Interpreter, fn_stmt: *ast.Stmt, arg_values: []const Value) Error!Value {
        const f = fn_stmt.data.fungsi_decl;
        const saved = self.locals;
        self.locals = std.array_list.Managed(Scope).init(self.allocator);
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

    fn reqHeader(self: *Interpreter, name: []const u8) []const u8 {
        for (self.req_headers[0..self.req_header_count]) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return "";
    }

    // Server soket mentah (single-thread): tiap koneksi panggil 'koneksi(soket)'.
    fn serveSoket(self: *Interpreter, port: u16) Error!Value {
        const z = ast.Pos{ .line = 0, .column = 0 };
        const fn_stmt = self.functions.get("koneksi") orelse return self.runtimeError(z, "server soket butuh fungsi 'koneksi(soket: bulat): kosong'");
        const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", port) catch return self.runtimeError(z, "alamat tidak valid");
        var net_server = addr.listen(rt.io, .{ .reuse_address = true }) catch return self.runtimeError(z, "gagal mendengarkan di port");
        rt.galat("[tenun] server soket di port {d}\n", .{port});
        while (true) {
            const stream = net_server.accept(rt.io) catch continue;
            const conn = sock.wrap(self.allocator, stream) catch {
                stream.close(rt.io);
                continue;
            };
            self.conns.append(conn) catch {
                sock.close(self.allocator, conn);
                continue;
            };
            const handle: i64 = @intCast(self.conns.items.len - 1);
            const bid = siar.register(stream);
            _ = self.invokeUser(fn_stmt, &.{.{ .bulat = handle }}) catch {};
            siar.unregister(bid);
            const idx: usize = @intCast(handle);
            if (self.conns.items[idx]) |s| {
                sock.close(self.allocator, s);
                self.conns.items[idx] = null;
            }
        }
        return .kosong;
    }

    fn serve(self: *Interpreter, port: u16) Error!Value {
        const z = ast.Pos{ .line = 0, .column = 0 };
        const fn_stmt = self.functions.get("tangani") orelse return self.runtimeError(z, "server butuh fungsi 'tangani(metode: teks, jalur: teks, badan: teks): teks'");
        const addr = std.Io.net.IpAddress.parseIp4("0.0.0.0", port) catch return self.runtimeError(z, "alamat tidak valid");
        var net_server = addr.listen(rt.io, .{ .reuse_address = true }) catch return self.runtimeError(z, "gagal mendengarkan di port");
        rt.galat("[tenun] server berjalan di http://localhost:{d}\n", .{port});
        while (true) {
            const stream = net_server.accept(rt.io) catch continue;
            defer stream.close(rt.io);
            var rbuf: [65536]u8 = undefined;
            var wbuf: [65536]u8 = undefined;
            var sreader = stream.reader(rt.io, &rbuf);
            var swriter = stream.writer(rt.io, &wbuf);
            var hs = std.http.Server.init(&sreader.interface, &swriter.interface);
            var req = hs.receiveHead() catch continue;

            const a = self.vals.allocator();
            const metode = a.dupe(u8, @tagName(req.head.method)) catch "GET";
            const path = a.dupe(u8, req.head.target) catch "/";

            // Tangkap header request SEBELUM baca badan: readerExpectNone
            // meng-invalidasi string di Head.
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

            var bbuf: [65536]u8 = undefined;
            var badan: []const u8 = "";
            const body_reader = req.readerExpectNone(&bbuf);
            badan = body_reader.allocRemaining(a, std.Io.Limit.limited(16 * 1024 * 1024)) catch "";

            const res = self.invokeUser(fn_stmt, &.{ .{ .teks = metode }, .{ .teks = path }, .{ .teks = badan } }) catch Value.kosong;
            const body = if (std.meta.activeTag(res) == .teks) res.teks else "";
            req.respond(body, .{
                .status = @enumFromInt(self.resp_status),
                .extra_headers = self.resp_headers[0..self.resp_header_count],
            }) catch {};
        }
    }

    fn callBuiltin(self: *Interpreter, id: usize, args: []const Value, pos: ast.Pos) Error!Value {
        const a = self.vals.allocator();
        return switch (id) {
            0 => .{ .teks = http.get(a, args[0].teks) catch return self.runtimeError(pos, "gagal mengambil URL") },
            1 => .{ .desimal = @sqrt(args[0].desimal) },
            2 => .{ .desimal = std.math.pow(f64, args[0].desimal, args[1].desimal) },
            3 => .{ .desimal = @abs(args[0].desimal) },
            4 => .{ .bulat = @intFromFloat(@round(args[0].desimal)) },
            5 => .{ .bulat = @intCast(args[0].teks.len) },
            6 => .{ .teks = text.potong(a, args[0].teks, args[1].bulat, args[2].bulat) catch return self.runtimeError(pos, "gagal memotong teks") },
            7 => .{ .teks = fs.baca(a, args[0].teks) catch return self.runtimeError(pos, "gagal membaca file") },
            8 => blk: {
                fs.tulis(args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal menulis file");
                break :blk .kosong;
            },
            9 => self.serve(@intCast(args[0].bulat)),
            61 => self.serveSoket(@intCast(args[0].bulat)),
            62 => blk: {
                siar.broadcast(args[0].teks);
                break :blk Value.kosong;
            },
            63 => blk: {
                const arr = a.alloc(Value, argv.list.len) catch return self.runtimeError(pos, "kehabisan memori");
                for (argv.list, 0..) |s, i| arr[i] = .{ .teks = s };
                break :blk .{ .array = arr };
            },
            64 => .{ .bulat = rt.waktuDetik() },
            65 => blk: {
                const lo = args[0].bulat;
                const hi = args[1].bulat;
                if (hi <= lo) break :blk .{ .bulat = lo };
                break :blk .{ .bulat = rt.acakRentang(lo, hi) };
            },
            66 => .{ .desimal = std.fmt.parseFloat(f64, std.mem.trim(u8, args[0].teks, " \t\r\n")) catch 0 },
            67 => .{ .teks = text.pangkas(a, args[0].teks) catch return self.runtimeError(pos, "gagal pangkas") },
            68 => .{ .teks = text.keBesar(a, args[0].teks) catch return self.runtimeError(pos, "gagal keBesar") },
            69 => .{ .teks = text.keKecil(a, args[0].teks) catch return self.runtimeError(pos, "gagal keKecil") },
            70 => .{ .teks = waktu.tanggal(a, args[0].bulat, args[1].bulat) catch return self.runtimeError(pos, "gagal tanggal") },
            71 => .{ .bulat = rt.waktuMili() },
            72 => .{ .teks = os.info(a, args[0].teks) catch return self.runtimeError(pos, "gagal infoOS") },
            73 => .{ .teks = os.lingkungan(a, args[0].teks) catch return self.runtimeError(pos, "gagal lingkungan") },
            74 => .{ .teks = proses.jalankan(a, args[0].teks) catch return self.runtimeError(pos, "gagal jalankan") },
            75 => blk: {
                const list = fs.daftar(a, args[0].teks) catch return self.runtimeError(pos, "gagal daftar berkas");
                const arr = a.alloc(Value, list.len) catch return self.runtimeError(pos, "kehabisan memori");
                for (list, 0..) |s, i| arr[i] = .{ .teks = s };
                break :blk .{ .array = arr };
            },
            76 => blk: {
                fs.buatDir(args[0].teks);
                break :blk .kosong;
            },
            77 => blk: {
                fs.hapusBerkas(args[0].teks);
                break :blk .kosong;
            },
            78 => blk: {
                fs.hapusDir(args[0].teks);
                break :blk .kosong;
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
            90 => .{ .desimal = rt.acakFloat() },
            91 => .{ .desimal = @floatFromInt(args[0].bulat) },
            92 => .{ .bulat = @intFromFloat(@trunc(args[0].desimal)) },
            93 => .{ .teks = std.fmt.allocPrint(a, "{d}", .{args[0].desimal}) catch return self.runtimeError(pos, "kehabisan memori") },
            94 => .{ .teks = gambar.bacaPng(a, args[0].teks) catch return self.runtimeError(pos, "gagal baca gambar PNG") },
            10 => blk: {
                self.resp_status = @intCast(args[0].bulat);
                break :blk .kosong;
            },
            11 => blk: {
                if (self.resp_header_count < self.resp_headers.len) {
                    self.resp_headers[self.resp_header_count] = .{
                        .name = a.dupe(u8, args[0].teks) catch args[0].teks,
                        .value = a.dupe(u8, args[1].teks) catch args[1].teks,
                    };
                    self.resp_header_count += 1;
                }
                break :blk .kosong;
            },
            12 => .{ .bulat = text.cari(args[0].teks, args[1].teks) },
            13 => .{ .teks = text.ganti(a, args[0].teks, args[1].teks, args[2].teks) catch return self.runtimeError(pos, "gagal ganti teks") },
            14 => blk: {
                const parts = text.pisah(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal pisah teks");
                const arr = a.alloc(Value, parts.len) catch return self.runtimeError(pos, "kehabisan memori");
                for (parts, 0..) |p, i| arr[i] = .{ .teks = p };
                break :blk .{ .array = arr };
            },
            15 => blk: {
                const arr = args[0].array;
                var buf = std.array_list.Managed(u8).init(a);
                for (arr, 0..) |el, i| {
                    if (i > 0) buf.appendSlice(args[1].teks) catch {};
                    buf.appendSlice(el.teks) catch {};
                }
                break :blk .{ .teks = buf.toOwnedSlice() catch return self.runtimeError(pos, "kehabisan memori") };
            },
            16 => .{ .bool = text.mulaiDengan(args[0].teks, args[1].teks) },
            17 => .{ .bool = text.akhiriDengan(args[0].teks, args[1].teks) },
            18 => .{ .teks = text.tipeKonten(args[0].teks) },
            19 => .{ .teks = json.teks(a, args[0].teks, args[1].teks) },
            20 => .{ .bulat = json.angka(a, args[0].teks, args[1].teks) },
            21 => .{ .bool = json.boolean(a, args[0].teks, args[1].teks) },
            22 => .{ .bool = fs.ada(args[0].teks) },
            23 => .{ .teks = text.kueri(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal urai kueri") },
            24 => .{ .teks = text.form(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal urai form") },
            25 => .{ .teks = self.reqHeader(args[0].teks) },
            26 => .{ .teks = text.cookieAmbil(a, self.reqHeader("cookie"), args[0].teks) catch return self.runtimeError(pos, "gagal baca cookie") },
            27 => blk: {
                kv.simpan(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal simpan data");
                break :blk .kosong;
            },
            28 => .{ .teks = kv.muat(a, args[0].teks) },
            29 => blk: {
                kv.hapus(a, args[0].teks) catch return self.runtimeError(pos, "gagal hapus data");
                break :blk .kosong;
            },
            30 => blk: {
                const conn = sock.connect(self.allocator, args[0].teks, @intCast(args[1].bulat)) catch break :blk .{ .bulat = -1 };
                self.conns.append(conn) catch return self.runtimeError(pos, "kehabisan memori");
                break :blk .{ .bulat = @intCast(self.conns.items.len - 1) };
            },
            31 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    sock.send(s, args[1].teks) catch return self.runtimeError(pos, "gagal mengirim");
                };
                break :blk .kosong;
            },
            32 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                const maks: usize = @intCast(args[1].bulat);
                const buf = a.alloc(u8, maks) catch return self.runtimeError(pos, "kehabisan memori");
                var n: usize = 0;
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    n = sock.recv(s, buf);
                };
                break :blk .{ .teks = buf[0..n] };
            },
            33 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    sock.close(self.allocator, s);
                    self.conns.items[sid] = null;
                };
                break :blk .kosong;
            },
            34 => .{ .teks = crypto.sha256(a, args[0].teks) catch return self.runtimeError(pos, "gagal sha256") },
            35 => .{ .teks = crypto.sha1(a, args[0].teks) catch return self.runtimeError(pos, "gagal sha1") },
            36 => .{ .teks = crypto.md5(a, args[0].teks) catch return self.runtimeError(pos, "gagal md5") },
            37 => .{ .teks = crypto.hmacSha256(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal hmac") },
            38 => .{ .teks = crypto.base64Enkode(a, args[0].teks) catch return self.runtimeError(pos, "gagal base64") },
            39 => .{ .teks = crypto.base64Dekode(a, args[0].teks) catch return self.runtimeError(pos, "base64 tidak valid") },
            40 => .{ .teks = crypto.acak(a, @intCast(args[0].bulat)) catch return self.runtimeError(pos, "gagal acak") },
            41 => .{ .teks = binary.keByte(a, args[0].bulat, args[1].bulat, args[2].bool) catch return self.runtimeError(pos, "gagal keByte") },
            42 => .{ .bulat = binary.bacaInt(args[0].teks, args[1].bulat, args[2].bulat, args[3].bool) },
            43 => .{ .teks = crypto.sha1Raw(a, args[0].teks) catch return self.runtimeError(pos, "gagal sha1Raw") },
            44 => .{ .teks = crypto.xorBytes(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal xor") },
            45 => blk: {
                const sid: usize = @intCast(args[0].bulat);
                const n: usize = @intCast(args[1].bulat);
                const buf = a.alloc(u8, n) catch return self.runtimeError(pos, "kehabisan memori");
                var got: usize = 0;
                if (sid < self.conns.items.len) if (self.conns.items[sid]) |s| {
                    got = sock.recvExact(s, buf);
                };
                break :blk .{ .teks = buf[0..got] };
            },
            46 => .{ .bulat = std.fmt.parseInt(i64, std.mem.trim(u8, args[0].teks, " \t\r\n"), 10) catch 0 },
            47 => .{ .teks = std.fmt.allocPrint(a, "{d}", .{args[0].bulat}) catch return self.runtimeError(pos, "kehabisan memori") },
            48 => blk: {
                const src = args[0].array;
                const arr = a.alloc(Value, src.len + 1) catch return self.runtimeError(pos, "kehabisan memori");
                for (src, 0..) |v, i| arr[i] = v;
                arr[src.len] = args[1];
                break :blk .{ .array = arr };
            },
            49 => .{ .teks = crypto.sha256Raw(a, args[0].teks) catch return self.runtimeError(pos, "gagal sha256Raw") },
            50 => .{ .teks = crypto.hmacSha256Raw(a, args[0].teks, args[1].teks) catch return self.runtimeError(pos, "gagal hmac raw") },
            51 => .{ .teks = crypto.pbkdf2Sha256(a, args[0].teks, args[1].teks, args[2].bulat) catch return self.runtimeError(pos, "gagal pbkdf2") },
            52 => .{ .teks = binary.bacaFloat(a, args[0].teks, args[1].bulat, args[2].bulat) catch return self.runtimeError(pos, "gagal bacaFloat") },
            53 => .{ .bool = args[0].peta.contains(args[1].teks) },
            54 => blk: {
                const m = args[0].peta;
                const arr = a.alloc(Value, m.count()) catch return self.runtimeError(pos, "kehabisan memori");
                var it = m.keyIterator();
                var i: usize = 0;
                while (it.next()) |k| : (i += 1) arr[i] = .{ .teks = k.* };
                break :blk .{ .array = arr };
            },
            55 => blk: {
                _ = args[0].peta.remove(args[1].teks);
                break :blk .kosong;
            },
            56 => .{ .teks = http.kirim(a, args[0].teks, args[1].teks, args[2].teks, args[3].teks) catch return self.runtimeError(pos, "gagal kirim HTTP") },
            57 => .{ .bulat = tls.connect(args[0].teks, @intCast(args[1].bulat)) catch -1 },
            58 => blk: {
                tls.send(args[0].bulat, args[1].teks) catch return self.runtimeError(pos, "gagal kirim TLS");
                break :blk .kosong;
            },
            59 => .{ .teks = tls.recv(a, args[0].bulat, @intCast(args[1].bulat)) catch return self.runtimeError(pos, "gagal terima TLS") },
            60 => blk: {
                tls.close(args[0].bulat);
                break :blk .kosong;
            },
            else => unreachable,
        };
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
            .fungsi => |stmt| try self.out.print("<fungsi {s}>", .{stmt.data.fungsi_decl.name}),
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
        self.last_error = message;
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
        .peta => a.peta == b.peta,
        .fungsi => a.fungsi == b.fungsi,
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

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    rt.io = threaded.io();

    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();

    var interp = Interpreter.init(allocator, &diags, &aw.writer);
    defer interp.deinit();
    try interp.run(program);

    return aw.toOwnedSlice();
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
