const std = @import("std");

pub const Severity = enum { err, warning };

pub const Diagnostic = struct {
    line: usize,
    column: usize,
    severity: Severity,
    message: []const u8,
};

pub const Diagnostics = struct {
    allocator: std.mem.Allocator,
    items: std.array_list.Managed(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{
            .allocator = allocator,
            .items = std.array_list.Managed(Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.items.deinit();
    }

    pub fn report(self: *Diagnostics, severity: Severity, line: usize, column: usize, message: []const u8) !void {
        try self.items.append(.{
            .line = line,
            .column = column,
            .severity = severity,
            .message = message,
        });
    }

    pub fn hasErrors(self: *const Diagnostics) bool {
        for (self.items.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    pub fn print(self: *const Diagnostics, writer: anytype) !void {
        for (self.items.items) |d| {
            const tag = switch (d.severity) {
                .err => "error",
                .warning => "warning",
            };
            try writer.print("{d}:{d}: {s}: {s}\n", .{ d.line, d.column, tag, d.message });
        }
    }
};

test "kumpulin error dan deteksi" {
    var diags = Diagnostics.init(std.testing.allocator);
    defer diags.deinit();

    try std.testing.expect(!diags.hasErrors());
    try diags.report(.warning, 1, 1, "cuma warning");
    try std.testing.expect(!diags.hasErrors());
    try diags.report(.err, 2, 5, "variabel ga dikenal");
    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), diags.items.items.len);
}
