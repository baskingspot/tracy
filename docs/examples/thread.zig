const std = @import("std");
const tracy = @import("tracy");

fn worker() void {
    tracy.setThreadName("worker");
    const zone = tracy.trace(@src());
    defer zone.end();
    tracy.message("worker done");
}

test "name a thread from inside it" {
    const thread = try std.Thread.spawn(.{}, worker, .{});
    thread.join();
}
