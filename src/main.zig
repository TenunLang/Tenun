const std = @import("std");
const driver = @import("driver.zig");
const build_options = @import("build_options");

pub const version = build_options.version;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw);

    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    for (raw[1..]) |a| try args.append(a);

    try dispatch(allocator, args.items);
}

fn dispatch(allocator: std.mem.Allocator, args: []const []const u8) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len < 1) {
        try printUsage(stdout);
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
    } else if (std.mem.eql(u8, cmd, "baru")) {
        if (args.len < 2) {
            try stderr.print("error: 'tenun baru' membutuhkan nama proyek (mis. 'tenun baru blog')\n", .{});
        } else {
            try driver.baru(allocator, args[1]);
        }
    } else if (std.mem.startsWith(u8, cmd, "buat:")) {
        const jenis = cmd["buat:".len..];
        if (args.len < 2) {
            try stderr.print("error: 'tenun buat:{s}' membutuhkan nama (mis. 'tenun buat:{s} home')\n", .{ jenis, jenis });
        } else {
            try driver.buatBerkas(allocator, jenis, args[1]);
        }
    } else if (std.mem.eql(u8, cmd, "run")) {
        var path: ?[]const u8 = null;
        var use_vm = true;
        var prog = std.ArrayList([]const u8).init(allocator);
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
        var tok = std.ArrayList([]const u8).init(allocator);
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
        \\  tenun version          menampilkan versi
        \\  tenun run <file> [arg...]   menjalankan program (argumen lewat builtin argumen())
        \\  tenun run <file> --interp   menjalankan via tree-walking interpreter
        \\  tenun jalan <skrip>    menjalankan skrip dari "skrip" di tenun.json (mirip npm run)
        \\  tenun build <file>     kompilasi ke executable native (<file>.exe)
        \\  tenun build <file> --emit-c   simpan juga sumber C perantara
        \\  tenun fmt <file>       rapikan format kode (tulis ke file)
        \\  tenun fmt <file> --stdout   cetak hasil rapi ke layar
        \\  tenun repl             mode interaktif (REPL)
        \\  tenun add <modul>      pasang modul dari GitHub (TenunLang/modul-<modul>)
        \\  tenun baru <nama>      buat proyek web MVC baru (kerangka Jala)
        \\  tenun buat:controller <nama>   buat controller di app/controllers/
        \\  tenun buat:model <nama>        buat model di app/models/
        \\  tenun buat:view <nama>         buat view di views/
        \\
        \\Dalam kode, pakai modul dengan: impor "<modul>";
        \\
    , .{version});
}

test {
    std.testing.refAllDeclsRecursive(@This());
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
