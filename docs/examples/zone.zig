const std = @import("std");
const tracy = @import("tracy");

fn checksum(input: []const u8) u64 {
    const zone = tracy.trace(@src());
    defer zone.end();
    zone.addText(input);

    var total: u64 = 0;
    for (input) |byte| {
        const step = tracy.traceNamed(@src(), "add byte");
        defer step.end();
        total +%= byte;
    }

    zone.setValue(total);
    return total;
}

fn record(size: usize) !void {
    const zone = tracy.trace(@src());
    defer zone.end();

    var buffer: [64]u8 = undefined;
    const text = try std.mem.print(&buffer, "size {d}", .{size});
    zone.addText(text);
    zone.setValue(size);
}

test "a zone per function, named where one function opens two" {
    try std.testing.expectEqual(@as(u64, 98 + 97 + 115 + 107), checksum("bask"));
}

test "attach data to a zone" {
    try record(1024);
}
