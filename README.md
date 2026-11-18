<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="tracy" height="48">
  </picture>
</h1>

Tracy profiler bindings for Zig: zones, plots, messages, and an allocator, compiled out when disabled.

The Zig compiler carries its own Tracy bindings, and they are not in the standard library. This is that code with the compiler around it removed: the Zig side of Tracy's C API, and the build wiring that compiles the C client into your module.

The library is one switch. With `enable` false, `Ctx` is an empty struct, every function is an inline no-op, and the client is never fetched, compiled, or linked. Turn it on for a profiling build, and the same calls emit zones, plots, and messages.

```zig
const tracy = @import("tracy");

fn handle(request: *const Request) !void {
    const zone = tracy.trace(@src());
    defer zone.end();
    zone.addText(request.path);

    tracy.plotInt("in flight", in_flight.value);
}
```

## What is in it

- [Zones](https://baskingspot.dev/tracy/#zones): `trace(@src())` and `traceNamed` open one, `Ctx` carries text, a value, and a color, and `end` closes it.
- [Memory](https://baskingspot.dev/tracy/#memory): `tracyAllocator` and `TracyAllocator("name")` report every allocation, free, and resize to the memory view.
- [Messages](https://baskingspot.dev/tracy/#messages): `log` at six severities, `message` for the common case, `appInfo`, and `setThreadName`.
- [Plots](https://baskingspot.dev/tracy/#plots): `plotConfig` declares a series, and `plotInt` and `plotFloat` add points.
- [Frames](https://baskingspot.dev/tracy/#frames): `frameMark` per tick, `frameMarkNamed` for a stream of its own, and `namedFrame` around a block.
- [The build](https://baskingspot.dev/tracy/#the-build): `enable`, `enable_allocation`, `enable_callstack`, `enable_on_demand`, and `only_localhost`, and what each costs.

Not implemented:

- A global hook: only allocations through `TracyAllocator` appear in the memory view.
- GPU zones, frame images, lock tracking, fibers, and the memory discard calls: the C client exposes them and the Zig module does not, so declare the `extern` yourself if you need one.
- Zones by source-location pointer: every zone here carries a full `___tracy_source_location_data`.
- Zone text past 65,535 bytes: the client's wire format caps it.

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

## Documentation

- The [guide](https://baskingspot.dev/tracy/) covers zones, memory, messages, plots, frames, and the build options.
- The [API reference](https://baskingspot.dev/tracy/api/) documents every public symbol in `src/root.zig`.
- [`docs/examples/`](docs/examples/) is the test-verified code shown in the guide: `just test` compiles and runs it alongside the module's own tests.
- [`THIRD_PARTY.md`](THIRD_PARTY.md) records what came from the Zig compiler and what the C client's terms are.
- [`AGENTS.md`](AGENTS.md) has the working notes for the repository.

## Work on it

```sh
just ci
```

`nix develop` provides the toolchain and the site tools. `just` lists the recipes, and `just ci` runs what CI runs: the tests, the client lane, lint, and the site build. `just client` builds a program against the compiled C client and runs it, which is the only way to catch a mistake in the wiring. `just guide` serves the guide with live reload.

## License

MIT. See [`LICENSE`](LICENSE). `src/root.zig` is adapted from the Zig compiler and ZLS; [`LICENSE-ZIG`](LICENSE-ZIG) reproduces their MIT terms and [`THIRD_PARTY.md`](THIRD_PARTY.md) lists what changed. The C client is vendored from [wolfpld/tracy](https://github.com/wolfpld/tracy) under `vendor/tracy`, at the tag `THIRD_PARTY.md` records, with its BSD 3-Clause license beside it. The logo files in `docs/static/` are baskingspot marks and are not covered by the MIT license. See [`docs/static/LICENSE`](docs/static/LICENSE).

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
