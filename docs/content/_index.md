+++
title = "tracy"
+++

Tracy profiler bindings for Zig: zones, plots, messages, and an allocator, compiled out when disabled.

The Zig compiler carries its own Tracy bindings, and they are not in the
standard library. This is that code with the compiler taken out: the Zig side of
Tracy's C API, and the build wiring that compiles the C client into your module.

The switch is one build option. With `enable` false, `Ctx` is an empty struct,
every function is an inline no-op, and the client is never fetched, compiled, or
linked. The calls stay in the source, so the profiling build is a flag on the
same tree a release build comes from.

- [Zones](#zones): `trace(@src())` and `traceNamed` open one, `Ctx` carries text, a value, and a color, and `end` closes it.
- [Memory](#memory): `tracyAllocator` and `TracyAllocator("name")` report every allocation, free, and resize.
- [Messages](#messages): `log` at six severities, `message` for the common case, `appInfo`, and `setThreadName`.
- [Plots](#plots): `plotConfig` declares a series, `plotInt` and `plotFloat` add points.
- [Frames](#frames): `frameMark` per tick, `frameMarkNamed` for a stream of its own, and `namedFrame` around a block.
- [The build](#the-build): the five options, what each costs, and the client the package pins.
- [Limits](#limits): what is not here.

The [API reference](api/) documents every symbol.

# Getting started

## Install

```sh
zig fetch --save https://baskingspot.dev/tracy/v0.1.0.tar.gz
```

Add the module in `build.zig`:

```zig
const tracy = b.dependency("tracy", .{
    .target = target,
    .optimize = optimize,
    .enable = true,
});
exe.root_module.addImport("tracy", tracy.module("tracy"));
```

`tracy` builds with Zig 0.17.

## Import it

```zig
const tracy = @import("tracy");
```

The import name is `tracy`, which is not in `std`, so nothing needs an alias.
There is no second module and nothing to initialize.

## Turn it on

`enable` is the switch, and it reaches both halves of the build: the options
module the Zig code reads, and the C macros the client compiles with. They
cannot disagree.

Pass it in `b.dependency`, as above, or from the command line for a whole build:

```sh
zig build -Denable=true
```

`enable_allocation` and `enable_callstack` follow `enable`.
`enable_on_demand` and `only_localhost` default to false. [The build](#the-build)
has the table. Tests always run with the no-op path: `enable` is forced false under
`zig build test`, so a profiling build still has a test suite that verifies what
the release build does.

## Read the examples

Every example is a file under `docs/examples/`, embedded here and compiled by
`just test`. If a page shows it, the build ran it.

# Zones

A zone is a span of time with a name. `trace` opens one and returns a `Ctx`;
`zone.end()` closes it, and the profiler nests it inside the zone that is open
on the same thread.

```zig
{{ load_data(path="examples/zone.zig", format="plain") | trim_end }}
```

`trace(@src())` takes the calling function's name, file, and line, so the label
never drifts from the function it wraps. `traceNamed` keeps the location and
adds a name of its own, which is what you want when one function has two phases
worth separating.

`defer zone.end()` is the usual shape. The close runs after the function's other
defers, so the zone covers the cleanup too. A zone must be closed on the thread
that opened it.

## Attach data to a zone

A `Ctx` carries four things the timeline can show. `addText` sets the zone's
text, `setName` overrides the name it opened with, `setColor` sets its color as
`0xRRGGBB`, and `setValue` sets a number the profiler plots against the zone.

The client copies the text and the name at the call, so a string built on the
stack is fine. `record` in the example above does that: it formats a size into a
stack buffer, then hands the slice to `addText` and the number to `setValue`.

## The cost of a zone

With `enable` false, the `Ctx` that `trace` returns is an empty struct and every
method on it does nothing. The compiler inlines all of it away, including the
call, so a release build carries no zone code.

With `enable` true, one zone is a timestamp, a queue write, and a source
location the compiler stores once per call site. `enable_callstack` adds a stack
walk per event, which is why it is worth turning off for steady-state profiling.

# Memory

`tracyAllocator` wraps an allocator and reports every allocation, free, and
resize to the memory view. It changes nothing about the allocator's behavior:
the child forwards to the parent and adds a call.

```zig
{{ load_data(path="examples/memory.zig", format="plain") | trim_end }}
```

A resize is reported as a free and an allocation, because the memory view has no
resize event. A failed allocation is reported as a red message in the log before
the null comes back, so the failure shows at the moment it happened.

## Name the allocations

`TracyAllocator("name")` is the same wrapper with a label. The memory view
groups allocations by that name, which is what keeps a long-lived arena separate
from short-lived request buffers in the same plot.

Only allocations that pass through the wrapper are visible. Nothing here hooks
the global allocator, and nothing replaces an allocator you already have: the
wrapper goes around the one the code is already using.

# Messages

The log view holds lines. `log` writes one at a severity and a color, and the
four `message` functions are `log` with `info` filled in.

```zig
tracy.log(.warning, "pool is empty", 0xFFAA00);
tracy.message("connected");
tracy.messageColor("retrying", 0xFF0000);
```

`log` and `message` take a sentinel-terminated comptime string, which costs a
pointer and no copy. `logCopy` and `messageCopy` take a slice of any length the
caller built; the client copies the bytes before the call returns.

`appInfo` adds a line to the profiler's info view, the place for the version
string and the build options that describe the run.

## Name the thread

`setThreadName` labels the calling thread. Call it from the thread itself, at
its start, so every zone the thread opens shows up under that name.

```zig
{{ load_data(path="examples/thread.zig", format="plain") | trim_end }}
```

# Plots

A plot is a series of numbers with a name. `plotConfig` declares the name, the
unit, and how the timeline draws it; `plotInt` and `plotFloat` add one point per
call.

```zig
{{ load_data(path="examples/plots.zig", format="plain") | trim_end }}
```

`PlotType` is `number`, `memory`, `percentage`, or `watt`, which sets the unit
the profiler shows. `step` draws the series as a step function, which suits a
queue depth that holds a value, and `fill` fills the area under the line.

Call `plotConfig` once for a name, before the first point. A point for a name
with no config is still recorded; the view just has no unit for it.

# Frames

A frame mark closes a frame. The profiler computes frame time as the gap between
one mark and the next, so the mark belongs at the end of the work, not the start.

```zig
{{ load_data(path="examples/frame.zig", format="plain") | trim_end }}
```

`frameMark` marks the default stream. `frameMarkNamed` gives a thread or a stage
a stream of its own, and `namedFrame` opens a named frame whose `end` closes it,
for a frame that spans a block rather than a point.

One thread marks one frame at a time. Two threads marking the same stream
interleave and the frame times mean nothing.

# The build

| Option              | Default  | What it does                                                           |
| ------------------- | -------- | ---------------------------------------------------------------------- |
| `enable`            | `false`  | Compiles the client in. With it false, every call is a no-op.          |
| `enable_allocation` | `enable` | Reports through `TracyAllocator`.                                      |
| `enable_callstack`  | `enable` | Collects a callstack with every zone, message, and allocation.         |
| `enable_on_demand`  | `false`  | Emits only while a profiler is connected.                              |
| `only_localhost`    | `false`  | Binds the listener to loopback and stops announcing it on the network. |

Set them in `b.dependency`, or on the command line as `-Denable_allocation=true`.
The field name is the option name in both places. A value
given to `b.dependency` wins for that module, so two modules in one build can
disagree, which is the point of building the profiler into one of them.

`enable_on_demand` also changes the client's C API: the zone context carries a
connection id when the client is built that way. The module reads the same
option, so the Zig struct and the C struct match. Do not set `TRACY_ON_DEMAND`
yourself.

`only_localhost` sets `TRACY_ONLY_LOCALHOST` and `TRACY_NO_BROADCAST`. Use it
for a program on a server, where the profiler reaches it through a port forward
and nothing should be listening on the network.

## The client

The C client is vendored in `vendor/tracy`, copied from wolfpld/tracy v0.15.0,
with its license. A build with `enable` false never compiles it, and no build
downloads it. The profiler on your machine must be the same version family as
the client, so install the Tracy GUI that matches.

`just client` builds a program against the client with the client on, and runs
it. CI runs it too, so a change to the client wiring fails here and not in a
user's build.

# Limits

- Zone text is capped at 65,535 bytes by the client's wire format. A longer
  string trips the client's assertion in a build with assertions on.
- There is no global hook. Only allocations through `TracyAllocator` appear in
  the memory view.
- GPU zones, frame images, lock tracking, fibers, and the memory discard calls
  are in the C client and not in this module. Wrap the C function with an
  `extern` declaration if you need one.
- There is no support for the source-location-by-pointer zone calls
  (`___tracy_emit_zone_begin_alloc`). Zones here carry a full
  `___tracy_source_location_data`.
