# Changelog

All notable changes to tracy are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `tracy` as a package: `b.dependency("tracy", .{ .enable = true })` compiles
  the Tracy C client into the module, and `enable = false` makes every
  function an inline no-op. The client is vendored under `vendor/tracy`, so a
  build needs no download.
- `trace(@src())`, `traceNamed`, and `Ctx`: zones named after their function,
  with `addText`, `setName`, `setColor`, `setValue`, and `end`.
- `tracyAllocator` and `TracyAllocator("name")`: an allocator wrapper that
  reports allocations, frees, and resizes to the memory view. A resize is
  reported as a free and an allocation.
- `log` and `logCopy` at six severities, with `message`, `messageColor`,
  `messageCopy`, and `messageColorCopy` at `info`. `appInfo` writes the info
  view and `setThreadName` labels the calling thread.
- `plotConfig`, `plotInt`, and `plotFloat` for integer and float series, with
  the `number`, `memory`, `percentage`, and `watt` units.
- `frameMark`, `frameMarkNamed`, `namedFrame`, and `Frame`: a point per frame,
  or a block with an `end`.
- The build options `enable-allocation` and `enable-callstack`, both following
  `enable`, plus `enable-on-demand` and `only-localhost` for the client's
  connection behavior.
