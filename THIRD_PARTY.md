# Third-party code and terms

tracy is MIT (`LICENSE`). This file lists every piece that comes from another
project, so those terms travel with the package.

## The Zig compiler and ZLS

- Upstream: the Zig compiler's `src/tracy.zig`, and Zig's fork of ZLS, which
  carries the same file.
- License: MIT, Copyright (c) Zig contributors. The full text is in
  `LICENSE-ZIG`, per its terms.

`src/root.zig` is adapted from that file. It keeps the option-gated
`Ctx`/no-op pair, `trace` and `traceNamed`, the plot, message, thread, frame,
and memory bindings, the `extern` declarations, and the source-location struct.
The changes:

- The module doc and a `///` comment on every public declaration.
- `tracy_options` replaces the compiler's `build_options` module.
- `callstack_depth` is a constant 10. The compiler makes it an option.
- The message functions follow the C client's v0.15.0 API: `Severity`, `log`,
  and `logCopy` call `___tracy_emit_logString` and
  `___tracy_emit_logStringL`. `message`, `messageColor`, `messageCopy`, and
  `messageColorCopy` are those at `info` severity, which is what the compiler's
  functions emit. The v0.13 message symbols are gone from the client.
- The memory `extern` declarations follow v0.15.0 and no longer pass the
  `secure` argument, which the client dropped.
- `___tracy_c_zone_context` carries the `connectionId` field that the client's
  header adds under `TRACY_ON_DEMAND`, so the Zig struct and the C struct agree
  in both modes.
- `TracyAllocator` follows the variant in ZLS and Exosphere rather than the
  compiler's: it asserts a non-empty length, reports a resize or a remap as a
  free and an allocation, and reports a failed remap to the caller without
  writing a message for it.

`src/root.zig` is checked by `zig fmt` and `ziglint` like the rest of `src/`. A
ziglint rule that fires on the vendored shape names the line it exempts.

## Tracy

- Upstream: <https://github.com/wolfpld/tracy>
- Pinned tag: v0.15.0, in `build.zig.zon`
- License: BSD 3-Clause, in the fetched package's `LICENSE`

The C client is a dependency, not vendored code. A build with `enable` false
never fetches it. When enabled, `build.zig` compiles `public/TracyClient.cpp`
into the module and adds the macros that select the client's behavior. The
package's release tarball carries none of it.

The Zig module talks to the client only through the `___tracy_*` functions in
`public/tracy/TracyC.h`. Those names, their argument lists, and the
`___tracy_c_zone_context` layout are the contract between the two, so a client
upgrade means checking that header before the tag moves in `build.zig.zon`.
