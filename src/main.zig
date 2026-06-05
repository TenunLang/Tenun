const std = @import("std");
const driver = @import("driver.zig");

pub const version = "0.0.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (args.len < 2) {
        try printUsage(stdout);
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "version")) {
        try stdout.print("tenun {s}\n", .{version});
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) {
            try stderr.print("error: 'tenun add' membutuhkan nama modul (mis. 'tenun add mysql')\n", .{});
        } else {
            try driver.add(allocator, args[2]);
        }
    } else if (std.mem.eql(u8, cmd, "run")) {
        var path: ?[]const u8 = null;
        var use_vm = true;
        for (args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--vm")) {
                use_vm = true;
            } else if (std.mem.eql(u8, arg, "--interp")) {
                use_vm = false;
            } else path = arg;
        }
        if (path) |p| {
            try driver.run(allocator, p, use_vm);
        } else {
            try stderr.print("error: 'tenun run' membutuhkan path file\n", .{});
        }
    } else if (std.mem.eql(u8, cmd, "build")) {
        var path: ?[]const u8 = null;
        var keep_c = false;
        for (args[2..]) |arg| {
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
        \\  tenun run <file>       menjalankan program .tenun (bytecode VM)
        \\  tenun run <file> --interp   menjalankan via tree-walking interpreter
        \\  tenun build <file>     kompilasi ke executable native (<file>.exe)
        \\  tenun build <file> --emit-c   simpan juga sumber C perantara
        \\  tenun add <modul>      pasang modul dari GitHub (TenunLang/modul-<modul>)
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
