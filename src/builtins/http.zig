const std = @import("std");

pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    errdefer body.deinit();

    _ = try client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 64 * 1024 * 1024,
    });

    return body.toOwnedSlice();
}
