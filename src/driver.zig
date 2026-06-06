const std = @import("std");
const Diagnostics = @import("diagnostics/diagnostics.zig").Diagnostics;
const Lexer = @import("lexer/lexer.zig").Lexer;
const parser = @import("parser/parser.zig");
const sema = @import("sema/sema.zig");
const Interpreter = @import("interp/interp.zig").Interpreter;
const vm = @import("vm/vm.zig");
const codegen = @import("codegen/codegen.zig");
const fmt = @import("fmt/fmt.zig");
const argv = @import("builtins/argv.zig");

// Baca perintah skrip dari "skrip" di tenun.json (mirip "scripts" npm/bun).
pub fn bacaSkrip(allocator: std.mem.Allocator, nama: []const u8) ![]u8 {
    const data = try readFile(allocator, "tenun.json");
    defer allocator.free(data);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), data, .{}) catch return error.SkripTidakAda;
    if (parsed != .object) return error.SkripTidakAda;
    const skrip = parsed.object.get("skrip") orelse return error.SkripTidakAda;
    if (skrip != .object) return error.SkripTidakAda;
    const v = skrip.object.get(nama) orelse return error.SkripTidakAda;
    if (v != .string) return error.SkripTidakAda;
    return allocator.dupe(u8, v.string);
}

pub fn run(allocator: std.mem.Allocator, path: []const u8, use_vm: bool, prog_args: []const []const u8) !void {
    argv.list = prog_args;
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

// Format file .tenun ke bentuk kanonik. write=true menulis kembali ke file,
// selain itu cetak ke stdout. Tidak meng-expand impor (format satu file saja).
pub fn fmtFile(allocator: std.mem.Allocator, path: []const u8, write: bool) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const source = try readFile(allocator, path);
    defer allocator.free(source);

    var diags = Diagnostics.init(allocator);
    defer diags.deinit();

    var lexer = Lexer.init(source, &diags);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);
    if (diags.hasErrors()) {
        try diags.print(stderr);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = parser.parse(arena.allocator(), tokens, &diags) catch {
        try diags.print(stderr);
        return;
    };

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try fmt.format(program, buf.writer());

    if (write) {
        if (std.mem.eql(u8, buf.items, source)) {
            try stdout.print("[tenun fmt] {s} sudah rapi\n", .{path});
            return;
        }
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(buf.items);
        try stdout.print("[tenun fmt] {s} dirapikan\n", .{path});
    } else {
        try stdout.writeAll(buf.items);
    }
}

// REPL: baca baris, jalankan via interpreter, simpan deklarasi antar baris.
pub fn repl(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.writeAll("Tenun REPL. Ketik kode, baris kosong untuk jalankan, 'keluar' untuk berhenti.\n");

    // akumulasi deklarasi (fungsi + biar) supaya tetap ada antar eval
    var prelude = std.ArrayList(u8).init(allocator);
    defer prelude.deinit();

    var line_buf = std.ArrayList(u8).init(allocator);
    defer line_buf.deinit();

    while (true) {
        try stdout.writeAll("tenun> ");
        line_buf.clearRetainingCapacity();
        stdin.streamUntilDelimiter(line_buf.writer(), '\n', null) catch break;
        const line = std.mem.trim(u8, line_buf.items, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "keluar") or std.mem.eql(u8, line, "exit")) break;

        // gabung prelude + baris ini, jalankan; kalau deklarasi, simpan ke prelude
        const is_decl = std.mem.startsWith(u8, line, "fungsi ") or
            std.mem.startsWith(u8, line, "biar ") or
            std.mem.startsWith(u8, line, "tetap ");

        const full = try std.fmt.allocPrint(allocator, "{s}{s}\n", .{ prelude.items, line });
        defer allocator.free(full);

        const ok = evalSnippet(allocator, full, stdout, stderr);
        if (ok and is_decl) {
            try prelude.appendSlice(line);
            try prelude.append('\n');
        }
    }
    try stdout.writeAll("dadah.\n");
}

fn evalSnippet(allocator: std.mem.Allocator, source: []const u8, stdout: anytype, stderr: anytype) bool {
    var diags = Diagnostics.init(allocator);
    defer diags.deinit();

    var lexer = Lexer.init(source, &diags);
    const tokens = lexer.tokenize(allocator) catch return false;
    defer allocator.free(tokens);
    if (diags.hasErrors()) {
        diags.print(stderr) catch {};
        return false;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const program = parser.parse(arena.allocator(), tokens, &diags) catch {
        diags.print(stderr) catch {};
        return false;
    };

    sema.check(allocator, program, &diags) catch {};
    if (diags.hasErrors()) {
        diags.print(stderr) catch {};
        return false;
    }

    var interp = Interpreter.init(allocator, &diags, stdout.any());
    defer interp.deinit();
    interp.run(program) catch {
        diags.print(stderr) catch {};
        return false;
    };
    return true;
}

pub fn add(allocator: std.mem.Allocator, arg: []const u8) anyerror!void {
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
    pasangDependensi(allocator, name) catch {};
    try stdout.print("[tenun] modul '{s}' terpasang di {s} — pakai dengan: impor \"{s}\";\n", .{ name, dest, name });
}

// Pasang dependensi modul (bidang "butuh" di tenun.json modul) secara rekursif.
fn pasangDependensi(allocator: std.mem.Allocator, name: []const u8) anyerror!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const mpath = try std.fmt.allocPrint(a, "tenun_modul/{s}/tenun.json", .{name});
    const data = readFile(a, mpath) catch return;
    const root = std.json.parseFromSliceLeaky(std.json.Value, a, data, .{}) catch return;
    if (root != .object) return;
    const butuh = root.object.get("butuh") orelse return;
    if (butuh != .object) return;

    var it = butuh.object.iterator();
    while (it.next()) |entry| {
        const dep = entry.key_ptr.*;
        const destdep = try std.fmt.allocPrint(a, "tenun_modul/{s}", .{dep});
        if (std.fs.cwd().access(destdep, .{})) {
            continue; // sudah terpasang
        } else |_| {}
        const dep_owned = try allocator.dupe(u8, dep);
        defer allocator.free(dep_owned);
        add(allocator, dep_owned) catch {};
    }
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
