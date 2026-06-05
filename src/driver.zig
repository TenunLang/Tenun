const std = @import("std");
const Diagnostics = @import("diagnostics/diagnostics.zig").Diagnostics;
const Lexer = @import("lexer/lexer.zig").Lexer;
const parser = @import("parser/parser.zig");
const sema = @import("sema/sema.zig");
const Interpreter = @import("interp/interp.zig").Interpreter;
const vm = @import("vm/vm.zig");
const codegen = @import("codegen/codegen.zig");

pub fn run(allocator: std.mem.Allocator, path: []const u8, use_vm: bool) !void {
    const source = try loadProgram(allocator, path);
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
    const source = try loadProgram(allocator, path);
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

pub fn add(allocator: std.mem.Allocator, arg: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var url: []const u8 = undefined;
    var name: []const u8 = undefined;
    if (std.mem.indexOf(u8, arg, "://") != null) {
        url = arg;
        var base = arg;
        if (std.mem.lastIndexOfScalar(u8, base, '/')) |i| base = base[i + 1 ..];
        if (std.mem.endsWith(u8, base, ".git")) base = base[0 .. base.len - 4];
        name = base;
    } else {
        url = try std.fmt.allocPrint(allocator, "https://github.com/TenunLang/modul-{s}", .{arg});
        name = arg;
    }
    defer if (std.mem.indexOf(u8, arg, "://") == null) allocator.free(url);

    std.fs.cwd().makePath("tenun_modul") catch {};
    const dest = try std.fmt.allocPrint(allocator, "tenun_modul/{s}", .{name});
    defer allocator.free(dest);

    try stdout.print("[tenun] mengambil modul '{s}' dari {s}\n", .{ name, url });
    var child = std.process.Child.init(&.{ "git", "clone", "--depth", "1", url, dest }, allocator);
    const term = child.spawnAndWait() catch |err| {
        try stderr.print("error: gagal menjalankan git: {s}\n", .{@errorName(err)});
        return;
    };
    if (term != .Exited or term.Exited != 0) {
        try stderr.print("error: gagal mengambil modul '{s}'\n", .{name});
        return;
    }
    tambahKeManifest(allocator, name) catch {};
    try stdout.print("[tenun] modul '{s}' terpasang di {s} — pakai dengan: impor \"{s}\";\n", .{ name, dest, name });
}

fn tambahKeManifest(allocator: std.mem.Allocator, name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root: std.json.Value = .{ .object = std.json.ObjectMap.init(a) };
    if (readFile(a, "tenun.json")) |data| {
        if (std.json.parseFromSliceLeaky(std.json.Value, a, data, .{})) |parsed| {
            if (parsed == .object) root = parsed;
        } else |_| {}
    } else |_| {}

    if (root.object.get("nama") == null) try root.object.put("nama", .{ .string = "proyek-tenun" });
    if (root.object.get("versi") == null) try root.object.put("versi", .{ .string = "0.1.0" });

    // versi modul dari manifest modul
    var versi: []const u8 = "0.1.0";
    const mpath = try std.fmt.allocPrint(a, "tenun_modul/{s}/tenun.json", .{name});
    if (readFile(a, mpath)) |md| {
        if (std.json.parseFromSliceLeaky(std.json.Value, a, md, .{})) |mr| {
            if (mr == .object) if (mr.object.get("versi")) |v| if (v == .string) {
                versi = v.string;
            };
        } else |_| {}
    } else |_| {}

    const vstr = try std.fmt.allocPrint(a, "^{s}", .{versi});
    if (root.object.getPtr("butuh")) |bp| {
        if (bp.* == .object) {
            try bp.object.put(name, .{ .string = vstr });
        } else {
            var o = std.json.ObjectMap.init(a);
            try o.put(name, .{ .string = vstr });
            try root.object.put("butuh", .{ .object = o });
        }
    } else {
        var o = std.json.ObjectMap.init(a);
        try o.put(name, .{ .string = vstr });
        try root.object.put("butuh", .{ .object = o });
    }

    var buf = std.ArrayList(u8).init(a);
    try std.json.stringify(root, .{ .whitespace = .indent_2 }, buf.writer());
    try buf.append('\n');
    const f = try std.fs.cwd().createFile("tenun.json", .{});
    defer f.close();
    try f.writeAll(buf.items);
}

fn loadModule(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    // 1) entry dari manifest tenun.json ("berkas")
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const mpath = try std.fmt.allocPrint(a, "tenun_modul/{s}/tenun.json", .{name});
        if (readFile(a, mpath)) |data| {
            if (std.json.parseFromSliceLeaky(std.json.Value, a, data, .{})) |root| {
                if (root == .object) if (root.object.get("berkas")) |b| if (b == .string) {
                    const fp = try std.fmt.allocPrint(a, "tenun_modul/{s}/{s}", .{ name, b.string });
                    if (std.fs.cwd().access(fp, .{})) {
                        return readFile(allocator, fp);
                    } else |_| {}
                };
            } else |_| {}
        } else |_| {}
    }
    // 2) fallback: tenun_modul/<nama>/<nama>.tenun
    const p1 = try std.fmt.allocPrint(allocator, "tenun_modul/{s}/{s}.tenun", .{ name, name });
    defer allocator.free(p1);
    if (std.fs.cwd().access(p1, .{})) {
        return readFile(allocator, p1);
    } else |_| {}
    // 3) fallback: tenun_modul/<nama>.tenun
    const p2 = try std.fmt.allocPrint(allocator, "tenun_modul/{s}.tenun", .{name});
    defer allocator.free(p2);
    return readFile(allocator, p2);
}

fn loadProgram(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const main_src = try readFile(allocator, path);
    defer allocator.free(main_src);

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var lines = std.mem.splitScalar(u8, main_src, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "impor \"")) {
            const rest = t["impor \"".len..];
            const end = std.mem.indexOfScalar(u8, rest, '"') orelse {
                try out.appendSlice(line);
                try out.append('\n');
                continue;
            };
            const name = rest[0..end];
            const mod = loadModule(allocator, name) catch {
                try out.appendSlice("// modul tidak ditemukan: ");
                try out.appendSlice(name);
                try out.append('\n');
                continue;
            };
            defer allocator.free(mod);
            try out.appendSlice(mod);
            try out.append('\n');
        } else {
            try out.appendSlice(line);
            try out.append('\n');
        }
    }
    return out.toOwnedSlice();
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
