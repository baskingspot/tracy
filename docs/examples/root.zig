//! Every example the guide embeds. Each file is compiled and run by
//! `zig build test`, so a guide page cannot show code that does not build.

const std = @import("std");

pub const zone = @import("zone.zig");
pub const memory = @import("memory.zig");
pub const messages = @import("thread.zig");
pub const plots = @import("plots.zig");
pub const frame = @import("frame.zig");

test {
    std.testing.refAllDecls(@This());
}
