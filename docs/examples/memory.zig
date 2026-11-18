const std = @import("std");
const tracy = @import("tracy");

test "a named allocator over an arena" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var tracked = tracy.TracyAllocator("parse").init(arena.allocator());
    const allocator = tracked.allocator();

    const numbers = try allocator.alloc(u32, 1024);
    try std.testing.expectEqual(@as(usize, 1024), numbers.len);

    const grown = try allocator.realloc(numbers, 2048);
    try std.testing.expectEqual(@as(usize, 2048), grown.len);
}
