const std = @import("std");
const rt = @import("rt.zig");
const Diagnostics = @import("diagnostics/diagnostics.zig").Diagnostics;
const Lexer = @import("lexer/lexer.zig").Lexer;
const parser = @import("parser/parser.zig");
const sema = @import("sema/sema.zig");
const Interpreter = @import("interp/interp.zig").Interpreter;
const vm = @import("vm/vm.zig");
const codegen = @import("codegen/codegen.zig");
const fmt = @import("fmt/fmt.zig");
const uji = @import("builtins/uji.zig");
const argv = @import("builtins/argv.zig");
const builtin = @import("builtin");

// Ikon default (Windows) yang ditanam ke binary build.
const default_ico = @embedFile("logo.ico");

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

    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

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
        vm.run(allocator, program, &diags, stdout) catch |err| switch (err) {
            error.RuntimeError => {
                try diags.print(stderr);
                return;
            },
            else => return err,
        };
        return;
    }

    var interp = Interpreter.init(allocator, &diags, stdout);
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

    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

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

    try writeFileAll(c_path, c_source);

    // Ikon aplikasi (Windows): pakai <base>.ico bila ada, selain itu ikon default.
    var res_path: ?[]const u8 = null;
    var tmp_ico: ?[]const u8 = null;
    var rc_path: ?[]const u8 = null;
    defer {
        if (tmp_ico) |p| std.Io.Dir.cwd().deleteFile(rt.io, p) catch {};
        if (rc_path) |p| std.Io.Dir.cwd().deleteFile(rt.io, p) catch {};
        if (res_path) |p| std.Io.Dir.cwd().deleteFile(rt.io, p) catch {};
    }
    if (builtin.os.tag == .windows) {
        res_path = siapkanIkon(allocator, base, &tmp_ico, &rc_path) catch null;
    }

    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    try args.appendSlice(&.{ "zig", "cc", c_path, "-O2", "-o", exe_path });
    if (res_path) |rp| try args.append(rp);

    const term = spawnWait(args.items, false) catch |err| {
        try stderr.print("error: gagal menjalankan 'zig cc': {s}\n", .{@errorName(err)});
        return;
    };
    if (term != .exited or term.exited != 0) {
        try stderr.print("error: kompilasi C gagal\n", .{});
        return;
    }

    if (!keep_c) std.Io.Dir.cwd().deleteFile(rt.io, c_path) catch {};

    try stdout.print("[tenun] build sukses: {s}\n", .{exe_path});
}

// Siapkan resource ikon Windows: pakai <base>.ico bila ada, selain itu ikon
// default bawaan. Hasilkan <base>.rc -> kompilasi `zig rc` -> kembalikan path .res.
fn siapkanIkon(allocator: std.mem.Allocator, base: []const u8, tmp_ico_out: *?[]const u8, rc_out: *?[]const u8) !?[]const u8 {
    const user_ico = try std.fmt.allocPrint(allocator, "{s}.ico", .{base});
    var ico_ref: []const u8 = user_ico;
    if (std.Io.Dir.cwd().access(rt.io, user_ico, .{})) {
        // pakai ikon milik pengguna
    } else |_| {
        const t = try std.fmt.allocPrint(allocator, "{s}.app.ico", .{base});
        writeFileAll(t, default_ico) catch return null;
        tmp_ico_out.* = t;
        ico_ref = t;
    }

    const ico_fwd = try allocator.dupe(u8, ico_ref);
    for (ico_fwd) |*c| if (c.* == '\\') {
        c.* = '/';
    };

    const rc = try std.fmt.allocPrint(allocator, "{s}.rc", .{base});
    {
        const rc_data = std.fmt.allocPrint(allocator, "1 ICON \"{s}\"\n", .{ico_fwd}) catch return null;
        defer allocator.free(rc_data);
        writeFileAll(rc, rc_data) catch return null;
    }
    rc_out.* = rc;

    const res = try std.fmt.allocPrint(allocator, "{s}.res", .{base});
    const term = spawnWait(&.{ "zig", "rc", rc, res }, true) catch return null;
    if (term != .exited or term.exited != 0) return null;
    return res;
}

// Format file .tenun ke bentuk kanonik. write=true menulis kembali ke file,
// selain itu cetak ke stdout. Tidak meng-expand impor (format satu file saja).
pub fn fmtFile(allocator: std.mem.Allocator, path: []const u8, write: bool) !void {
    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

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

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try fmt.format(program, &aw.writer);
    const rapi = aw.written();

    if (write) {
        if (std.mem.eql(u8, rapi, source)) {
            try stdout.print("[tenun fmt] {s} sudah rapi\n", .{path});
            return;
        }
        try writeFileAll(path, rapi);
        try stdout.print("[tenun fmt] {s} dirapikan\n", .{path});
    } else {
        try stdout.writeAll(rapi);
    }
}

// Jalankan seluruh uji unit (berkas `*.uji.tenun`) di bawah `root` (rekursif).
// Gaya Jest/Mocha: tiap berkas dijalankan, builtin tegas*() mencatat lulus/gagal.
// Mengembalikan jumlah uji gagal + berkas bergalat (0 = semua lulus). CI: `tenun check`.
pub fn check(allocator: std.mem.Allocator, root: []const u8) !usize {
    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var files = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit();
    }
    cariUji(allocator, root, &files) catch |err| {
        try stderr.print("error: gagal menelusuri '{s}': {s}\n", .{ root, @errorName(err) });
        return 1;
    };

    if (files.items.len == 0) {
        try stdout.print("[tenun check] tidak ada berkas uji (*.uji.tenun) di '{s}'\n", .{root});
        return 0;
    }

    var total_lulus: usize = 0;
    var total_gagal: usize = 0;
    for (files.items) |f| {
        try stdout.print("\n{s}\n", .{f});
        stdout.flush() catch {};
        uji.reset();
        const ok = jalankanUji(allocator, f);
        total_lulus += uji.lulus();
        total_gagal += uji.gagal();
        if (!ok) {
            total_gagal += 1;
            try stdout.print("  GAGAL berkas tak bisa dijalankan\n", .{});
        }
    }

    try stdout.print("\n[tenun check] {d} lulus, {d} gagal ({d} berkas uji)\n", .{ total_lulus, total_gagal, files.items.len });
    return total_gagal;
}

// Telusuri direktori, kumpulkan berkas berakhiran `.uji.tenun`.
fn cariUji(allocator: std.mem.Allocator, path: []const u8, out: *std.array_list.Managed([]const u8)) !void {
    if (std.mem.endsWith(u8, path, ".uji.tenun")) {
        try out.append(try allocator.dupe(u8, path));
        return;
    }
    var dir = std.Io.Dir.cwd().openDir(rt.io, path, .{ .iterate = true }) catch return;
    defer dir.close(rt.io);

    var it = dir.iterate();
    while (try it.next(rt.io)) |entry| {
        if (lewatiNama(entry.name)) continue;
        const child = try std.fs.path.join(allocator, &.{ path, entry.name });
        switch (entry.kind) {
            .directory => {
                defer allocator.free(child);
                try cariUji(allocator, child, out);
            },
            .file => if (std.mem.endsWith(u8, entry.name, ".uji.tenun")) {
                try out.append(child);
            } else allocator.free(child),
            else => allocator.free(child),
        }
    }
}

// Direktori yang dilewati saat menelusuri (dependensi & artefak build).
fn lewatiNama(name: []const u8) bool {
    const skip = [_][]const u8{ ".git", "tenun_modul", "node_modules", "zig-out", ".zig-cache" };
    for (skip) |s| if (std.mem.eql(u8, name, s)) return true;
    return false;
}

// Jalankan satu berkas uji lewat VM (impor di-inline). Kembalikan false bila
// gagal lex/parse/sema atau galat runtime.
fn jalankanUji(allocator: std.mem.Allocator, path: []const u8) bool {
    const stderr = rt.err();
    const stdout = rt.out();

    const source = loadProgram(allocator, path) catch return false;
    defer allocator.free(source);

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

    vm.run(allocator, program, &diags, stdout) catch {
        diags.print(stderr) catch {};
        return false;
    };
    return true;
}

// REPL: baca baris, jalankan via interpreter, simpan deklarasi antar baris.
pub fn repl(allocator: std.mem.Allocator) !void {
    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var in_buf: [64 * 1024]u8 = undefined;
    var in_file = std.Io.File.stdin().reader(rt.io, &in_buf);
    const stdin = &in_file.interface;

    try stdout.writeAll("Tenun REPL. Ketik kode, baris kosong untuk jalankan, 'keluar' untuk berhenti.\n");

    // akumulasi deklarasi (fungsi + biar) supaya tetap ada antar eval
    var prelude = std.array_list.Managed(u8).init(allocator);
    defer prelude.deinit();

    while (true) {
        try stdout.writeAll("tenun> ");
        try stdout.flush();
        const line_raw = stdin.takeDelimiterExclusive('\n') catch break;
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "keluar") or std.mem.eql(u8, line, "exit")) break;

        // gabung prelude + baris ini, jalankan; kalau deklarasi, simpan ke prelude
        const is_decl = std.mem.startsWith(u8, line, "fungsi ") or
            std.mem.startsWith(u8, line, "biar ") or
            std.mem.startsWith(u8, line, "tetap ");

        const full = try std.fmt.allocPrint(allocator, "{s}{s}\n", .{ prelude.items, line });
        defer allocator.free(full);

        const ok = evalSnippet(allocator, full, stdout, stderr);
        stdout.flush() catch {};
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

    var interp = Interpreter.init(allocator, &diags, stdout);
    defer interp.deinit();
    interp.run(program) catch {
        diags.print(stderr) catch {};
        return false;
    };
    return true;
}

pub fn add(allocator: std.mem.Allocator, arg: []const u8) anyerror!void {
    const stdout = rt.out();
    const stderr = rt.err();
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

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

    std.Io.Dir.cwd().createDirPath(rt.io, "tenun_modul") catch {};
    const dest = try std.fmt.allocPrint(allocator, "tenun_modul/{s}", .{name});
    defer allocator.free(dest);

    try stdout.print("[tenun] mengambil modul '{s}' dari {s}\n", .{ name, url });
    stdout.flush() catch {};
    const term = spawnWait(&.{ "git", "clone", "--depth", "1", url, dest }, false) catch |err| {
        try stderr.print("error: gagal menjalankan git: {s}\n", .{@errorName(err)});
        return;
    };
    if (term != .exited or term.exited != 0) {
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
        if (std.Io.Dir.cwd().access(rt.io, destdep, .{})) {
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

    var root: std.json.Value = .{ .object = std.json.ObjectMap.empty };
    if (readFile(a, "tenun.json")) |data| {
        if (std.json.parseFromSliceLeaky(std.json.Value, a, data, .{})) |parsed| {
            if (parsed == .object) root = parsed;
        } else |_| {}
    } else |_| {}

    if (root.object.get("nama") == null) try root.object.put(a, "nama", .{ .string = "proyek-tenun" });
    if (root.object.get("versi") == null) try root.object.put(a, "versi", .{ .string = "0.1.0" });

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
            try bp.object.put(a, name, .{ .string = vstr });
        } else {
            var o = std.json.ObjectMap.empty;
            try o.put(a, name, .{ .string = vstr });
            try root.object.put(a, "butuh", .{ .object = o });
        }
    } else {
        var o = std.json.ObjectMap.empty;
        try o.put(a, name, .{ .string = vstr });
        try root.object.put(a, "butuh", .{ .object = o });
    }

    var aw = std.Io.Writer.Allocating.init(a);
    defer aw.deinit();
    try std.json.Stringify.value(root, .{ .whitespace = .indent_2 }, &aw.writer);
    try aw.writer.writeByte('\n');
    try writeFileAll("tenun.json", aw.written());
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
    if (std.Io.Dir.cwd().access(rt.io, p1, .{})) {
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

fn expand(allocator: std.mem.Allocator, file_path: []const u8, out: *std.array_list.Managed(u8), seen: *std.StringHashMap(void)) !void {
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
    var out = std.array_list.Managed(u8).init(allocator);
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
    return std.Io.Dir.cwd().readFileAlloc(rt.io, path, allocator, std.Io.Limit.limited(16 * 1024 * 1024));
}

// Tulis seluruh data ke file (buat + tulis + tutup) lewat Io 0.16.
fn writeFileAll(path: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(rt.io, .{ .sub_path = path, .data = data });
}

// Jalankan proses anak lalu tunggu selesai (process.spawn + wait, Io 0.16).
fn spawnWait(args: []const []const u8, quiet: bool) !std.process.Child.Term {
    var child = try std.process.spawn(rt.io, .{
        .argv = args,
        .stdout = if (quiet) .ignore else .inherit,
        .stderr = if (quiet) .ignore else .inherit,
    });
    return child.wait(rt.io);
}

test "driver baca file lalu bebasin" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    rt.io = threaded.io();

    const tmp = "tenu_driver_test.tenun";
    try writeFileAll(tmp, "biar x = 1;");
    defer std.Io.Dir.cwd().deleteFile(rt.io, tmp) catch {};

    const src = try readFile(std.testing.allocator, tmp);
    defer std.testing.allocator.free(src);
    try std.testing.expectEqualStrings("biar x = 1;", src);
}
