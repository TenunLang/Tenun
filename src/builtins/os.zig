const std = @import("std");
const builtin = @import("builtin");

fn envGet(a: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(a, name) catch return a.dupe(u8, "");
}

// Info OS berdasarkan kunci. Mengembalikan teks ("" bila tak tersedia).
pub fn info(a: std.mem.Allocator, kunci: []const u8) ![]u8 {
    if (std.mem.eql(u8, kunci, "nama")) return a.dupe(u8, @tagName(builtin.os.tag));
    if (std.mem.eql(u8, kunci, "arch")) return a.dupe(u8, @tagName(builtin.cpu.arch));
    if (std.mem.eql(u8, kunci, "cpu")) {
        const n = std.Thread.getCpuCount() catch 1;
        return std.fmt.allocPrint(a, "{d}", .{n});
    }
    if (std.mem.eql(u8, kunci, "cwd")) {
        return std.process.getCwdAlloc(a) catch a.dupe(u8, "");
    }
    if (std.mem.eql(u8, kunci, "host")) {
        if (builtin.os.tag == .windows) {
            return envGet(a, "COMPUTERNAME");
        } else {
            var buf: [256]u8 = undefined;
            const h = std.posix.gethostname(&buf) catch return envGet(a, "HOSTNAME");
            return a.dupe(u8, h);
        }
    }
    if (std.mem.eql(u8, kunci, "pengguna")) {
        if (builtin.os.tag == .windows) return envGet(a, "USERNAME");
        return envGet(a, "USER");
    }
    if (std.mem.eql(u8, kunci, "temp")) {
        if (builtin.os.tag == .windows) return envGet(a, "TEMP");
        return a.dupe(u8, "/tmp");
    }
    return a.dupe(u8, "");
}

// Nilai variabel lingkungan ("" bila tidak ada).
pub fn lingkungan(a: std.mem.Allocator, name: []const u8) ![]u8 {
    return envGet(a, name);
}
