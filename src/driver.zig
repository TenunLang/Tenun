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

fn imporLokal(spec: []const u8) bool {
    return std.mem.startsWith(u8, spec, "./") or
        std.mem.startsWith(u8, spec, "../") or
        std.mem.endsWith(u8, spec, ".tenun") or
        std.mem.indexOfScalar(u8, spec, '/') != null;
}

// Path file entry untuk sebuah modul terpasang (baca manifest "berkas").
fn modulEntryPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const mpath = try std.fmt.allocPrint(a, "tenun_modul/{s}/tenun.json", .{name});
        if (readFile(a, mpath)) |data| {
            if (std.json.parseFromSliceLeaky(std.json.Value, a, data, .{})) |root| {
                if (root == .object) if (root.object.get("berkas")) |b| if (b == .string) {
                    return std.fmt.allocPrint(allocator, "tenun_modul/{s}/{s}", .{ name, b.string });
                };
            } else |_| {}
        } else |_| {}
    }
    const p1 = try std.fmt.allocPrint(allocator, "tenun_modul/{s}/{s}.tenun", .{ name, name });
    if (std.fs.cwd().access(p1, .{})) {
        return p1;
    } else |_| {}
    allocator.free(p1);
    return std.fmt.allocPrint(allocator, "tenun_modul/{s}.tenun", .{name});
}

// Resolusi target impor menjadi path file (caller membebaskan).
fn resolveImpor(allocator: std.mem.Allocator, base_dir: []const u8, spec: []const u8) ![]u8 {
    if (imporLokal(spec)) {
        if (std.mem.endsWith(u8, spec, ".tenun")) {
            return std.fs.path.join(allocator, &.{ base_dir, spec });
        }
        const withext = try std.fmt.allocPrint(allocator, "{s}.tenun", .{spec});
        defer allocator.free(withext);
        return std.fs.path.join(allocator, &.{ base_dir, withext });
    }
    return modulEntryPath(allocator, spec);
}

fn expand(allocator: std.mem.Allocator, file_path: []const u8, out: *std.ArrayList(u8), seen: *std.StringHashMap(void)) !void {
    if (seen.contains(file_path)) return;
    try seen.put(try allocator.dupe(u8, file_path), {});

    const src = readFile(allocator, file_path) catch {
        try out.appendSlice("// tidak dapat memuat: ");
        try out.appendSlice(file_path);
        try out.append('\n');
        return;
    };
    defer allocator.free(src);

    const base_dir = std.fs.path.dirname(file_path) orelse ".";

    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "impor \"")) {
            const rest = t["impor \"".len..];
            const end = std.mem.indexOfScalar(u8, rest, '"') orelse {
                try out.appendSlice(line);
                try out.append('\n');
                continue;
            };
            const spec = rest[0..end];
            const target = resolveImpor(allocator, base_dir, spec) catch {
                try out.appendSlice("// impor gagal: ");
                try out.appendSlice(spec);
                try out.append('\n');
                continue;
            };
            defer allocator.free(target);
            try expand(allocator, target, out, seen);
        } else {
            try out.appendSlice(line);
            try out.append('\n');
        }
    }
}

fn loadProgram(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen.deinit();
    }

    try expand(allocator, path, &out, &seen);
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
