const std = @import("std");
const rt = @import("../rt.zig");

pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    return kirim(allocator, "GET", url, "", "");
}

// HTTP request umum dengan metode/header/body. TLS otomatis (https) via std.http.Client.
// headerRaw: baris "Nama: Nilai" dipisah '\n'. body: kosong = tanpa payload.
// Kembalikan badan respons.
pub fn kirim(allocator: std.mem.Allocator, metode: []const u8, url: []const u8, headerRaw: []const u8, body: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator, .io = rt.io };
    defer client.deinit();

    var headers = std.array_list.Managed(std.http.Header).init(allocator);
    defer headers.deinit();
    var it = std.mem.splitScalar(u8, headerRaw, '\n');
    while (it.next()) |line0| {
        const line = std.mem.trim(u8, line0, " \r");
        if (line.len == 0) continue;
        const ci = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..ci], " ");
        const val = std.mem.trim(u8, line[ci + 1 ..], " ");
        try headers.append(.{ .name = name, .value = val });
    }

    const m: std.http.Method = if (std.ascii.eqlIgnoreCase(metode, "POST"))
        .POST
    else if (std.ascii.eqlIgnoreCase(metode, "PUT"))
        .PUT
    else if (std.ascii.eqlIgnoreCase(metode, "DELETE"))
        .DELETE
    else if (std.ascii.eqlIgnoreCase(metode, "PATCH"))
        .PATCH
    else
        .GET;

    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();

    // Buffer dekompresi supaya respons ber-gzip/deflate bisa dibaca.
    const dbuf = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(dbuf);

    _ = try client.fetch(.{
        .location = .{ .url = url },
        .method = m,
        .extra_headers = headers.items,
        .payload = if (body.len > 0) body else null,
        .response_writer = &aw.writer,
        .decompress_buffer = dbuf,
    });

    return aw.toOwnedSlice();
}
