//! Tracy profiler bindings for Zig: zones, plots, messages, and an allocator, compiled out when disabled.
//!
//! When `enable` is false, every function here is an inline no-op and the Tracy
//! client is never fetched, compiled, or linked. When it is true, the module
//! compiles `public/TracyClient.cpp` from wolfpld/tracy, and each call emits an
//! event to the profiler on the other end of the connection.
//!
//! Adapted from the Zig compiler and ZLS. `LICENSE-ZIG` carries the MIT notice,
//! and `THIRD_PARTY.md` records what changed.

const std = @import("std");
const builtin = @import("builtin");
const options = @import("tracy_options");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

/// True when events are emitted. Tests force it false, so the suite runs on
/// the no-op path even in a build with `-Denable=true`.
pub const enable = if (builtin.is_test) false else options.enable;

/// True when `TracyAllocator` reports to the profiler.
pub const enable_allocation = enable and options.enable_allocation;

/// True when every zone, message, and allocation carries a callstack.
pub const enable_callstack = enable and options.enable_callstack;

const callstack_depth = 10;

// The zone context carries a connection id only when the client is built with
// TRACY_ON_DEMAND, so the layout follows the same option.
const ___tracy_c_zone_context = if (options.enable_on_demand) extern struct {
    id: u32,
    active: c_int,
    connection_id: u64,

    pub inline fn end(self: ___tracy_c_zone_context) void {
        ___tracy_emit_zone_end(self);
    }

    pub inline fn addText(self: ___tracy_c_zone_context, text: []const u8) void {
        ___tracy_emit_zone_text(self, text.ptr, text.len);
    }

    pub inline fn setName(self: ___tracy_c_zone_context, name: []const u8) void {
        ___tracy_emit_zone_name(self, name.ptr, name.len);
    }

    pub inline fn setColor(self: ___tracy_c_zone_context, color: u32) void {
        ___tracy_emit_zone_color(self, color);
    }

    pub inline fn setValue(self: ___tracy_c_zone_context, value: u64) void {
        ___tracy_emit_zone_value(self, value);
    }
} else extern struct {
    id: u32,
    active: c_int,

    pub inline fn end(self: ___tracy_c_zone_context) void {
        ___tracy_emit_zone_end(self);
    }

    pub inline fn addText(self: ___tracy_c_zone_context, text: []const u8) void {
        ___tracy_emit_zone_text(self, text.ptr, text.len);
    }

    pub inline fn setName(self: ___tracy_c_zone_context, name: []const u8) void {
        ___tracy_emit_zone_name(self, name.ptr, name.len);
    }

    pub inline fn setColor(self: ___tracy_c_zone_context, color: u32) void {
        ___tracy_emit_zone_color(self, color);
    }

    pub inline fn setValue(self: ___tracy_c_zone_context, value: u64) void {
        ___tracy_emit_zone_value(self, value);
    }
};

/// A zone that is open. `end` closes it; the other methods attach data to it
/// until then. When disabled, this is an empty struct and every method is a
/// no-op, so the same code compiles both ways.
pub const Ctx = if (enable) ___tracy_c_zone_context else struct {
    const Self = @This();

    pub inline fn end(self: Self) void {
        _ = self;
    }

    pub inline fn addText(self: Self, text: []const u8) void {
        _ = self;
        _ = text;
    }

    pub inline fn setName(self: Self, name: []const u8) void {
        _ = self;
        _ = name;
    }

    pub inline fn setColor(self: Self, color: u32) void {
        _ = self;
        _ = color;
    }

    pub inline fn setValue(self: Self, value: u64) void {
        _ = self;
        _ = value;
    }
};

/// Opens a zone named after the calling function, with the file and line
/// `@src()` carries. Pass it as `trace(@src())`.
pub inline fn trace(comptime src: std.builtin.SourceLocation) Ctx {
    if (!enable) return .{};

    const global = struct {
        const loc: ___tracy_source_location_data = .{
            .name = null,
            .function = src.fn_name.ptr,
            .file = src.file.ptr,
            .line = src.line,
            .color = 0,
        };
    };

    if (enable_callstack) {
        return ___tracy_emit_zone_begin_callstack(&global.loc, callstack_depth, 1);
    } else {
        return ___tracy_emit_zone_begin(&global.loc, 1);
    }
}

/// Like `trace`, with a name that is already a sentinel-terminated string.
/// Use it to tell two zones in one function apart.
pub inline fn traceNamed(comptime src: std.builtin.SourceLocation, comptime name: [:0]const u8) Ctx {
    if (!enable) return .{};

    const global = struct {
        const loc: ___tracy_source_location_data = .{
            .name = name.ptr,
            .function = src.fn_name.ptr,
            .file = src.file.ptr,
            .line = src.line,
            .color = 0,
        };
    };

    if (enable_callstack) {
        return ___tracy_emit_zone_begin_callstack(&global.loc, callstack_depth, 1);
    } else {
        return ___tracy_emit_zone_begin(&global.loc, 1);
    }
}

/// Wraps `allocator` so every allocation, free, and resize appears in the
/// profiler's memory view. The child keeps no state beyond the parent.
pub fn tracyAllocator(allocator: Allocator) TracyAllocator(null) {
    return TracyAllocator(null).init(allocator);
}

/// `tracyAllocator` with a name, which the memory view uses to group the
/// allocations apart from the unnamed ones.
pub fn TracyAllocator(comptime name: ?[:0]const u8) type {
    return struct {
        parent_allocator: Allocator,

        const Self = @This();

        pub fn init(parent_allocator: Allocator) Self {
            return .{
                .parent_allocator = parent_allocator,
            };
        }

        pub fn allocator(self: *Self) Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = allocFn,
                    .resize = resizeFn,
                    .remap = remapFn,
                    .free = freeFn,
                },
            };
        }

        fn allocFn(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            assert(len > 0);
            const self: *Self = @ptrCast(@alignCast(ptr));
            const new_memory = self.parent_allocator.rawAlloc(len, alignment, ret_addr) orelse {
                messageColor("allocation failed", 0xFF0000);
                return null;
            };
            if (name) |n| {
                allocNamed(n, new_memory, len);
            } else {
                alloc(new_memory, len);
            }
            return new_memory;
        }

        fn resizeFn(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            assert(memory.len > 0 and new_len > 0);
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (!self.parent_allocator.rawResize(memory, alignment, new_len, ret_addr)) return false;
            if (name) |n| {
                freeNamed(n, memory.ptr);
                allocNamed(n, memory.ptr, new_len);
            } else {
                free(memory.ptr);
                alloc(memory.ptr, new_len);
            }
            return true;
        }

        // ziglint-ignore: Z024
        fn remapFn(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            assert(memory.len > 0 and new_len > 0);
            const self: *Self = @ptrCast(@alignCast(ptr));
            const new_memory = self.parent_allocator.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
            if (name) |n| {
                freeNamed(n, memory.ptr);
                allocNamed(n, new_memory, new_len);
            } else {
                free(memory.ptr);
                alloc(new_memory, new_len);
            }
            return new_memory;
        }

        fn freeFn(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
            assert(memory.len > 0);
            if (name) |n| {
                freeNamed(n, memory.ptr);
            } else {
                free(memory.ptr);
            }
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.parent_allocator.rawFree(memory, alignment, ret_addr);
        }
    };
}

/// The severity the profiler's log view groups a message under.
pub const Severity = enum(i8) {
    trace = 0,
    debug = 1,
    info = 2,
    warning = 3,
    err = 4,
    fatal = 5,
};

/// Writes `msg` to the profiler's log at `severity`, in `color` as `0xRRGGBB`.
/// The string lives in the binary, so the call costs a pointer. Use `logCopy`
/// for a string that is not known at comptime.
pub inline fn log(comptime severity: Severity, comptime msg: [:0]const u8, color: u32) void {
    if (!enable) return;
    const depth = if (enable_callstack) callstack_depth else 0;
    ___tracy_emit_logStringL(@backingInt(severity), @intCast(color), depth, msg.ptr);
}

/// `log` for a string the caller builds at run time. The profiler copies the
/// bytes, so the caller may free them after the call.
pub inline fn logCopy(comptime severity: Severity, msg: []const u8, color: u32) void {
    if (!enable) return;
    const depth = if (enable_callstack) callstack_depth else 0;
    ___tracy_emit_logString(@backingInt(severity), @intCast(color), depth, msg.len, msg.ptr);
}

/// Writes `msg` to the profiler's log at `info` severity.
pub inline fn message(comptime msg: [:0]const u8) void {
    log(.info, msg, 0);
}

/// `message` in a color, as `0xRRGGBB`.
pub inline fn messageColor(comptime msg: [:0]const u8, color: u32) void {
    log(.info, msg, color);
}

/// `message` for a string the caller builds at run time.
pub inline fn messageCopy(msg: []const u8) void {
    logCopy(.info, msg, 0);
}

/// `messageCopy` in a color, as `0xRRGGBB`.
pub inline fn messageColorCopy(msg: [:0]const u8, color: u32) void {
    logCopy(.info, msg, color);
}

/// Names the calling thread. The profiler copies the bytes.
pub inline fn setThreadName(name: [*:0]const u8) void {
    if (!enable) return;
    ___tracy_set_thread_name(name);
}

pub const PlotType = enum(c_int) {
    number = 0,
    memory = 1,
    percentage = 2,
    watt = 3,
};

/// Declares a plot's label, unit, and colors. Call it once for a name, before
/// the first `plotInt` or `plotFloat` that uses it.
pub inline fn plotConfig(comptime name: [:0]const u8, plot_type: PlotType, step: bool, fill: bool, color: u32) void {
    if (!enable) return;
    ___tracy_emit_plot_config(name.ptr, @backingInt(plot_type), @intFromBool(step), @intFromBool(fill), color);
}

/// Adds one point to the integer plot `name`.
pub inline fn plotInt(comptime name: [:0]const u8, value: i64) void {
    if (!enable) return;
    ___tracy_emit_plot_int(name.ptr, value);
}

/// Adds one point to the float plot `name`.
pub inline fn plotFloat(comptime name: [:0]const u8, value: f64) void {
    if (!enable) return;
    ___tracy_emit_plot(name.ptr, value);
}

/// Adds a line to the profiler's info view. The profiler copies the bytes.
pub inline fn appInfo(text: []const u8) void {
    if (!enable) return;
    ___tracy_emit_message_appinfo(text.ptr, text.len);
}

/// Closes the current frame. Call it once per tick or per rendered frame, from
/// one thread, or use `frameMarkNamed` when threads produce separate streams.
pub inline fn frameMark() void {
    if (!enable) return;
    ___tracy_emit_frame_mark(null);
}

/// `frameMark` on the named stream.
pub inline fn frameMarkNamed(comptime name: [:0]const u8) void {
    if (!enable) return;
    ___tracy_emit_frame_mark(name.ptr);
}

/// Opens the named frame and returns a handle whose `end` closes it, for a
/// frame that spans a block rather than a point:
///
/// ```
/// const frame = tracy.namedFrame("update");
/// defer frame.end();
/// ```
pub inline fn namedFrame(comptime name: [:0]const u8) Frame(name) {
    frameMarkStart(name);
    return .{};
}

pub fn Frame(comptime name: [:0]const u8) type {
    return struct {
        const Self = @This();

        pub fn end(_: Self) void {
            frameMarkEnd(name);
        }
    };
}

inline fn frameMarkStart(comptime name: [:0]const u8) void {
    if (!enable) return;
    ___tracy_emit_frame_mark_start(name.ptr);
}

inline fn frameMarkEnd(comptime name: [:0]const u8) void {
    if (!enable) return;
    ___tracy_emit_frame_mark_end(name.ptr);
}

extern fn ___tracy_emit_frame_mark_start(name: [*:0]const u8) void;
extern fn ___tracy_emit_frame_mark_end(name: [*:0]const u8) void;
extern fn ___tracy_emit_plot(name: [*:0]const u8, val: f64) void;
extern fn ___tracy_emit_plot_int(name: [*:0]const u8, val: i64) void;
extern fn ___tracy_emit_plot_config(name: [*:0]const u8, plot_type: c_int, step: c_int, fill: c_int, color: u32) void;
extern fn ___tracy_emit_message_appinfo(txt: [*]const u8, size: usize) void;

inline fn alloc(ptr: [*]u8, len: usize) void {
    if (!enable) return;

    if (enable_callstack) {
        ___tracy_emit_memory_alloc_callstack(ptr, len, callstack_depth);
    } else {
        ___tracy_emit_memory_alloc(ptr, len);
    }
}

inline fn allocNamed(comptime name: [:0]const u8, ptr: [*]u8, len: usize) void {
    if (!enable) return;

    if (enable_callstack) {
        ___tracy_emit_memory_alloc_callstack_named(ptr, len, callstack_depth, name.ptr);
    } else {
        ___tracy_emit_memory_alloc_named(ptr, len, name.ptr);
    }
}

inline fn free(ptr: [*]u8) void {
    if (!enable) return;

    if (enable_callstack) {
        ___tracy_emit_memory_free_callstack(ptr, callstack_depth);
    } else {
        ___tracy_emit_memory_free(ptr);
    }
}

inline fn freeNamed(comptime name: [:0]const u8, ptr: [*]u8) void {
    if (!enable) return;

    if (enable_callstack) {
        ___tracy_emit_memory_free_callstack_named(ptr, callstack_depth, name.ptr);
    } else {
        ___tracy_emit_memory_free_named(ptr, name.ptr);
    }
}

extern fn ___tracy_emit_zone_begin(
    srcloc: *const ___tracy_source_location_data,
    active: c_int,
) ___tracy_c_zone_context;
extern fn ___tracy_emit_zone_begin_callstack(
    srcloc: *const ___tracy_source_location_data,
    depth: c_int,
    active: c_int,
) ___tracy_c_zone_context;
extern fn ___tracy_emit_zone_text(ctx: ___tracy_c_zone_context, txt: [*]const u8, size: usize) void;
extern fn ___tracy_emit_zone_name(ctx: ___tracy_c_zone_context, txt: [*]const u8, size: usize) void;
extern fn ___tracy_emit_zone_color(ctx: ___tracy_c_zone_context, color: u32) void;
extern fn ___tracy_emit_zone_value(ctx: ___tracy_c_zone_context, value: u64) void;
extern fn ___tracy_emit_zone_end(ctx: ___tracy_c_zone_context) void;
extern fn ___tracy_emit_memory_alloc(ptr: *const anyopaque, size: usize) void;
extern fn ___tracy_emit_memory_alloc_callstack(ptr: *const anyopaque, size: usize, depth: c_int) void;
extern fn ___tracy_emit_memory_free(ptr: *const anyopaque) void;
extern fn ___tracy_emit_memory_free_callstack(ptr: *const anyopaque, depth: c_int) void;
extern fn ___tracy_emit_memory_alloc_named(ptr: *const anyopaque, size: usize, name: [*:0]const u8) void;
// ziglint-ignore: Z024
extern fn ___tracy_emit_memory_alloc_callstack_named(ptr: *const anyopaque, size: usize, depth: c_int, name: [*:0]const u8) void;
extern fn ___tracy_emit_memory_free_named(ptr: *const anyopaque, name: [*:0]const u8) void;
// ziglint-ignore: Z024
extern fn ___tracy_emit_memory_free_callstack_named(ptr: *const anyopaque, depth: c_int, name: [*:0]const u8) void;
extern fn ___tracy_emit_logString(severity: i8, color: i32, callstack: i32, size: usize, txt: [*]const u8) void;
extern fn ___tracy_emit_logStringL(severity: i8, color: i32, callstack: i32, txt: [*:0]const u8) void;
extern fn ___tracy_emit_frame_mark(name: ?[*:0]const u8) void;
extern fn ___tracy_set_thread_name(name: [*:0]const u8) void;

const ___tracy_source_location_data = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32,
};

test "the disabled path is a no-op" {
    try testing.expect(!enable);

    const zone = trace(@src());
    zone.addText("text");
    zone.setName("name");
    zone.setColor(0xFF0000);
    zone.setValue(42);
    zone.end();

    const named = traceNamed(@src(), "named");
    named.end();

    message("message");
    messageColor("colored", 0xFF0000);
    messageCopy("copy");
    messageColorCopy("colored copy", 0xFF0000);
    setThreadName("thread");
    appInfo("info");

    plotConfig("plot", .number, false, false, 0);
    plotInt("plot", 1);
    plotFloat("plot", 1.5);

    frameMark();
    frameMarkNamed("frame");
    namedFrame("frame").end();

    var child = tracyAllocator(testing.allocator);
    const bytes = try child.allocator().alloc(u8, 16);
    defer child.allocator().free(bytes);
    try testing.expectEqual(@as(usize, 16), bytes.len);
}
