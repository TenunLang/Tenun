const std = @import("std");
const driver = @import("driver.zig");
const rt = @import("rt.zig");
const build_options = @import("build_options");

pub const version = build_options.version;

pub fn main(init: std.process.Init) !void {
    rt.io = init.io;
    rt.env_map = init.environ_map;
    const allocator = std.heap.c_allocator;

    const arena = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(arena);

    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    for (raw[1..]) |a| try args.append(a);

    try dispatch(allocator, args.items);
}

fn dispatch(allocator: std.mem.Allocator, args: []const []const u8) anyerror!void {
    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    // Tanpa argumen: jalankan index.tenun bila ada, selain itu tampilkan bantuan.
    if (args.len < 1) {
        if (std.Io.Dir.cwd().access(rt.io, "index.tenun", .{})) {
            try driver.run(allocator, "index.tenun", true, &.{});
        } else |_| {
            try printUsage(stdout);
        }
        return;
    }

    const cmd = args[0];
    if (std.mem.eql(u8, cmd, "version")) {
        try stdout.print("tenun {s}\n", .{version});
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 2) {
            try stderr.print("error: 'tenun add' membutuhkan nama modul (mis. 'tenun add mysql')\n", .{});
        } else {
            try driver.add(allocator, args[1]);
        }
    } else if (std.mem.eql(u8, cmd, "run")) {
        var path: ?[]const u8 = null;
        var use_vm = true;
        var prog = std.array_list.Managed([]const u8).init(allocator);
        defer prog.deinit();
        for (args[1..]) |arg| {
            if (path == null) {
                if (std.mem.eql(u8, arg, "--vm")) {
                    use_vm = true;
                } else if (std.mem.eql(u8, arg, "--interp")) {
                    use_vm = false;
                } else path = arg;
            } else try prog.append(arg);
        }
        if (path) |p| {
            try driver.run(allocator, p, use_vm, prog.items);
        } else {
            try stderr.print("error: 'tenun run' membutuhkan path file\n", .{});
        }
    } else if (std.mem.eql(u8, cmd, "jalan")) {
        if (args.len < 2) {
            try stderr.print("error: 'tenun jalan' membutuhkan nama skrip (lihat \"skrip\" di tenun.json)\n", .{});
            return;
        }
        const baris = driver.bacaSkrip(allocator, args[1]) catch {
            try stderr.print("error: skrip '{s}' tidak ada di tenun.json\n", .{args[1]});
            return;
        };
        defer allocator.free(baris);
        // Pecah skrip jadi token + tambah argumen ekstra, lalu jalankan ulang.
        var tok = std.array_list.Managed([]const u8).init(allocator);
        defer tok.deinit();
        var it = std.mem.tokenizeScalar(u8, baris, ' ');
        while (it.next()) |t| try tok.append(t);
        for (args[2..]) |extra| try tok.append(extra);
        try dispatch(allocator, tok.items);
    } else if (std.mem.eql(u8, cmd, "fmt")) {
        var path: ?[]const u8 = null;
        var write = true;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--cek") or std.mem.eql(u8, arg, "--stdout")) write = false else path = arg;
        }
        if (path) |p| {
            try driver.fmtFile(allocator, p, write);
        } else {
            try stderr.print("error: 'tenun fmt' membutuhkan path file\n", .{});
        }
    } else if (std.mem.eql(u8, cmd, "check")) {
        const path: []const u8 = if (args.len >= 2) args[1] else ".";
        const bad = try driver.check(allocator, path);
        stdout.flush() catch {};
        stderr.flush() catch {};
        if (bad > 0) std.process.exit(1);
    } else if (std.mem.eql(u8, cmd, "repl")) {
        try driver.repl(allocator);
    } else if (std.mem.eql(u8, cmd, "build")) {
        var path: ?[]const u8 = null;
        var keep_c = false;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--emit-c")) keep_c = true else path = arg;
        }
        if (path) |p| {
            try driver.build(allocator, p, keep_c);
        } else {
            try stderr.print("error: 'tenun build' membutuhkan path file\n", .{});
        }
    } else if (std.mem.endsWith(u8, cmd, ".tenun")) {
        // `tenun <file.tenun> [arg...]` — jalankan berkas langsung (tanpa "run").
        var prog = std.array_list.Managed([]const u8).init(allocator);
        defer prog.deinit();
        for (args[1..]) |a| try prog.append(a);
        try driver.run(allocator, cmd, true, prog.items);
    } else {
        try stderr.print("error: perintah tidak dikenal: {s}\n", .{cmd});
        try printUsage(stdout);
    }
}

fn printUsage(writer: anytype) !void {
    try writer.print(
        \\tenun {s}
        \\
        \\Penggunaan:
        \\  tenun <file.tenun> [arg...] menjalankan program (argumen lewat builtin argumen())
        \\  tenun                       menjalankan index.tenun (bila ada)
        \\  tenun version          menampilkan versi
        \\  tenun run <file> [arg...]   sama dengan di atas (bentuk lama)
        \\  tenun run <file> --interp   menjalankan via tree-walking interpreter
        \\  tenun jalan <skrip>    menjalankan skrip dari "skrip" di tenun.json (mirip npm run)
        \\  tenun build <file>     kompilasi ke executable native (<file>.exe)
        \\  tenun build <file> --emit-c   simpan juga sumber C perantara
        \\  tenun fmt <file>       rapikan format kode (tulis ke file)
        \\  tenun fmt <file> --stdout   cetak hasil rapi ke layar
        \\  tenun check [path]     jalankan uji unit (berkas *.uji.tenun, default ".")
        \\  tenun repl             mode interaktif (REPL)
        \\  tenun add <modul>      pasang modul dari GitHub (TenunLang/modul-<modul>)
        \\
        \\Dalam kode, pakai modul dengan: impor "<modul>";
        \\
    , .{version});
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("driver.zig");
    _ = @import("diagnostics/diagnostics.zig");
    _ = @import("lexer/token.zig");
    _ = @import("lexer/lexer.zig");
    _ = @import("parser/ast.zig");
    _ = @import("parser/parser.zig");
    _ = @import("sema/sema.zig");
    _ = @import("interp/interp.zig");
    _ = @import("vm/vm.zig");
    _ = @import("codegen/codegen.zig");
}
