const std = @import("std");
const rt = @import("../rt.zig");

fn be32(b: []const u8) u32 {
    return (@as(u32, b[0]) << 24) | (@as(u32, b[1]) << 16) | (@as(u32, b[2]) << 8) | @as(u32, b[3]);
}

fn paeth(a: i32, b: i32, c: i32) i32 {
    const p = a + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

// Dekode PNG 8-bit (grayscale/RGB/RGBA/grayscale+alpha/palette) menjadi
// teks "lebar tinggi g0 g1 ..." dengan nilai grayscale 0-255 (row-major).
pub fn bacaPng(a: std.mem.Allocator, path: []const u8) ![]u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(rt.io, path, a, std.Io.Limit.limited(1 << 30));
    defer a.free(data);

    if (data.len < 8 or data[0] != 0x89 or data[1] != 'P' or data[2] != 'N' or data[3] != 'G')
        return error.BukanPng;

    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: u8 = 0;
    var color_type: u8 = 0;
    var palette: []u8 = &[_]u8{};

    var idat = std.array_list.Managed(u8).init(a);
    defer idat.deinit();

    var pos: usize = 8;
    while (pos + 8 <= data.len) {
        const len = be32(data[pos .. pos + 4]);
        const ctype = data[pos + 4 .. pos + 8];
        const body_start = pos + 8;
        if (body_start + len > data.len) break;
        const body = data[body_start .. body_start + len];

        if (std.mem.eql(u8, ctype, "IHDR")) {
            width = be32(body[0..4]);
            height = be32(body[4..8]);
            bit_depth = body[8];
            color_type = body[9];
        } else if (std.mem.eql(u8, ctype, "PLTE")) {
            palette = try a.dupe(u8, body);
        } else if (std.mem.eql(u8, ctype, "IDAT")) {
            try idat.appendSlice(body);
        } else if (std.mem.eql(u8, ctype, "IEND")) {
            break;
        }
        pos = body_start + len + 4; // +4 CRC
    }

    if (bit_depth != 8) return error.BitDepthTakDidukung;

    const channels: usize = switch (color_type) {
        0 => 1, // grayscale
        2 => 3, // RGB
        3 => 1, // palette index
        4 => 2, // grayscale + alpha
        6 => 4, // RGBA
        else => return error.ColorTypeTakDidukung,
    };

    // inflate IDAT (zlib container) -> byte mentah ber-filter
    var zr: std.Io.Reader = .fixed(idat.items);
    var win: [std.compress.flate.max_window_len]u8 = undefined;
    var decomp = std.compress.flate.Decompress.init(&zr, .zlib, &win);
    const raw_bytes = try decomp.reader.allocRemaining(a, .unlimited);
    defer a.free(raw_bytes);

    const w: usize = width;
    const h: usize = height;
    const stride = w * channels;

    // unfilter -> buffer piksel mentah (channels per piksel)
    const out = try a.alloc(u8, h * stride);
    defer a.free(out);

    var prev: []u8 = &[_]u8{};
    var ri: usize = 0;
    var y: usize = 0;
    while (y < h) : (y += 1) {
        if (ri >= raw_bytes.len) return error.DataKurang;
        const filter = raw_bytes[ri];
        ri += 1;
        const line = raw_bytes[ri .. ri + stride];
        ri += stride;
        const cur = out[y * stride .. y * stride + stride];

        var i: usize = 0;
        while (i < stride) : (i += 1) {
            const x_byte: i32 = line[i];
            const aa: i32 = if (i >= channels) cur[i - channels] else 0;
            const bb: i32 = if (prev.len != 0) prev[i] else 0;
            const cc: i32 = if (prev.len != 0 and i >= channels) prev[i - channels] else 0;
            const val: i32 = switch (filter) {
                0 => x_byte,
                1 => x_byte + aa,
                2 => x_byte + bb,
                3 => x_byte + @divTrunc(aa + bb, 2),
                4 => x_byte + paeth(aa, bb, cc),
                else => x_byte,
            };
            cur[i] = @intCast(@mod(val, 256));
        }
        prev = cur;
    }

    // grayscale + serialisasi "W H v v ..."
    var sb = std.array_list.Managed(u8).init(a);
    errdefer sb.deinit();
    var buf: [16]u8 = undefined;
    try sb.appendSlice(try std.fmt.bufPrint(&buf, "{d} {d}", .{ width, height }));

    var px: usize = 0;
    while (px < w * h) : (px += 1) {
        const base = px * channels;
        var g: u32 = 0;
        switch (color_type) {
            0, 4 => g = out[base], // grayscale (abaikan alpha)
            2, 6 => {
                const r: u32 = out[base];
                const gg: u32 = out[base + 1];
                const b: u32 = out[base + 2];
                g = (r * 299 + gg * 587 + b * 114) / 1000;
            },
            3 => {
                const idx: usize = out[base];
                if (idx * 3 + 2 < palette.len) {
                    const r: u32 = palette[idx * 3];
                    const gg: u32 = palette[idx * 3 + 1];
                    const b: u32 = palette[idx * 3 + 2];
                    g = (r * 299 + gg * 587 + b * 114) / 1000;
                }
            },
            else => {},
        }
        try sb.append(' ');
        try sb.appendSlice(try std.fmt.bufPrint(&buf, "{d}", .{g}));
    }
    if (palette.len != 0) a.free(palette);
    return sb.toOwnedSlice();
}
