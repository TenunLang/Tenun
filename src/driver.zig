const std = @import("std");
const Diagnostics = @import("diagnostics/diagnostics.zig").Diagnostics;
const Lexer = @import("lexer/lexer.zig").Lexer;
const parser = @import("parser/parser.zig");
const sema = @import("sema/sema.zig");
const Interpreter = @import("interp/interp.zig").Interpreter;
const vm = @import("vm/vm.zig");
const codegen = @import("codegen/codegen.zig");

pub fn run(allocator: std.mem.Allocator, path: []const u8, use_vm: bool) !void {
    const source = try readFile(allocator, path);
    defer allocator.free(source);

    var diags = Diagnostics.init(allocator);
    defer diags.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var lexer = Lexer.init(source, &diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    if (diags.hasErrors()) {
        try diags.print(stderr);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const program = parser.parse(arena.allocator(), tokens, &diags) catch |err| switch (err) {
        error.ParseError => {
            try diags.print(stderr);
            return;
        },
        else => return err,
    };

    try sema.check(allocator, program, &diags);
    if (diags.hasErrors()) {
        try diags.print(stderr);
        return;
    }

    if (use_vm) {
        vm.run(allocator, program, &diags, stdout.any()) catch |err| switch (err) {
            error.RuntimeError => {
                try diags.print(stderr);
                return;
            },
            else => return err,
        };
        return;
    }

    var interp = Interpreter.init(allocator, &diags, stdout.any());
    defer interp.deinit();
    interp.run(program) catch |err| switch (err) {
        error.RuntimeError => {
            try diags.print(stderr);
            return;
        },
        else => return err,
    };
}

pub fn build(allocator: std.mem.Allocator, path: []const u8, keep_c: bool) !void {
    const source = try readFile(allocator, path);
    defer allocator.free(source);

    var diags = Diagnostics.init(allocator);
    defer diags.deinit();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var lexer = Lexer.init(source, &diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);
    if (diags.hasErrors()) {
        try diags.print(stderr);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = parser.parse(arena.allocator(), tokens, &diags) catch |err| switch (err) {
        error.ParseError => {
            try diags.print(stderr);
            return;
        },
        else => return err,
    };

    try sema.check(allocator, program, &diags);
    if (diags.hasErrors()) {
        try diags.print(stderr);
        return;
    }

    const c_source = codegen.generate(allocator, program, &diags) catch |err| switch (err) {
        error.Unsupported => {
            try diags.print(stderr);
            return;
        },
        else => return err,
    };
    defer allocator.free(c_source);

    const base = if (std.mem.endsWith(u8, path, ".tenun")) path[0 .. path.len - ".tenun".len] else path;
    const c_path = try std.fmt.allocPrint(allocator, "{s}.c", .{base});
    defer allocator.free(c_path);
    const exe_path = try std.fmt.allocPrint(allocator, "{s}.exe", .{base});
    defer allocator.free(exe_path);

    {
        const f = try std.fs.cwd().createFile(c_path, .{});
        defer f.close();
        try f.writeAll(c_source);
    }

    var child = std.process.Child.init(&.{ "zig", "cc", c_path, "-O2", "-o", exe_path }, allocator);
    const term = child.spawnAndWait() catch |err| {
        try stderr.print("error: gagal menjalankan 'zig cc': {s}\n", .{@errorName(err)});
        return;
    };
    if (term != .Exited or term.Exited != 0) {
        try stderr.print("error: kompilasi C gagal\n", .{});
        return;
    }

    if (!keep_c) std.fs.cwd().deleteFile(c_path) catch {};

    try stdout.print("[tenun] build sukses: {s}\n", .{exe_path});
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

test "driver baca file lalu bebasin" {
    const tmp = "tenu_driver_test.tenun";
    {
        const f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        try f.writeAll("biar x = 1;");
    }
    defer std.fs.cwd().deleteFile(tmp) catch {};

    const src = try readFile(std.testing.allocator, tmp);
    defer std.testing.allocator.free(src);
    try std.testing.expectEqualStrings("biar x = 1;", src);
}
