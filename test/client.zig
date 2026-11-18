//! A program that emits every kind of event through the compiled Tracy
//! client. `just client` builds it with the client on and runs it, so a break
//! in the C wiring fails here rather than in a consumer's build.
//!
//! Nothing connects to it in CI: the client is built with on-demand mode and
//! the loopback listener, so every call is dropped locally.

const std = @import("std");
const tracy = @import("tracy");

pub fn main() !void {
    tracy.setThreadName("main");
    tracy.appInfo("tracy: client smoke test");

    tracy.plotConfig("depth", .number, false, true, 0x00AA00);
    tracy.message("start");
    tracy.messageColor("colored start", 0xFF0000);

    const frame = tracy.namedFrame("frame");
    defer frame.end();

    inline for (0..3) |i| {
        const zone = tracy.traceNamed(@src(), "pass");
        defer zone.end();
        zone.addText("pass");
        zone.setValue(i);
        zone.setColor(0x00AA00);
        tracy.plotInt("depth", i);
        tracy.plotFloat("load", 1.0 / @as(f64, @floatFromInt(i + 1)));
        tracy.messageCopy("pass done");
        tracy.messageColorCopy("colored pass done", 0xFFAA00);
        tracy.frameMark();
    }

    var child = tracy.tracyAllocator(std.heap.page_allocator);
    const bytes = try child.allocator().alloc(u8, 1024);
    defer child.allocator().free(bytes);

    var named = tracy.TracyAllocator("buffer").init(std.heap.page_allocator);
    const scratch = try named.allocator().alloc(u8, 64);
    defer named.allocator().free(scratch);

    const thread = try std.Thread.spawn(.{}, worker, .{});
    thread.join();
}

fn worker() void {
    tracy.setThreadName("worker");
    const zone = tracy.trace(@src());
    defer zone.end();
    tracy.message("worker done");
}
