const std = @import("std");
const tracy = @import("tracy");

test "a plot per series, a message per event" {
    tracy.plotConfig("queue depth", .number, false, true, 0x00AA00);
    tracy.plotInt("queue depth", 12);
    tracy.plotFloat("cpu", 0.75);

    tracy.message("queue drained");
    tracy.messageColor("slow path", 0xFFAA00);

    const reason = "connection reset";
    tracy.messageCopy(reason);
    try std.testing.expect(reason.len > 0);
}
