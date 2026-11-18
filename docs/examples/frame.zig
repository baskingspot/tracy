const tracy = @import("tracy");

fn update(tick: usize) void {
    const zone = tracy.trace(@src());
    defer zone.end();
    tracy.plotInt("tick", @intCast(tick));
}

test "one frame mark per tick, or a named frame around a block" {
    for (0..3) |tick| {
        const frame = tracy.namedFrame("frame");
        defer frame.end();
        update(tick);
    }

    // A point instead of a block, for a loop that already has a scope.
    tracy.frameMark();
}
