# AGENTS.md

Working notes for AI coding agents in baskingspot/tracy.

## What this is

Tracy profiler bindings for Zig: zones, plots, messages, and an allocator, compiled out when disabled. The Zig half is adapted from the Zig compiler and ZLS; the C half is the upstream client, fetched and compiled only when `enable` is true.

## Environment

Zig 0.17, the current stable. The flake is the tool contract, from `baskingspot/nix`: `nix develop` provides Zig, `ziglint`, the docs shell, and the base tools, and nothing comes from the system PATH. The justfile is the command interface: `just test`, `just client`, `just lint`, `just ci`. CI runs `just ci`. Run `just fmt` before you commit.

`just test` runs the module's tests and the guide's examples. `src/root.zig` forces `enable` false under `builtin.is_test`, so the suite always exercises the no-op path, even in a build with `-Denable=true`.

`just client` is the other half: it builds `test/client.zig` with the client compiled in and runs it. Every mistake in the C wiring so far has been a link error or an ABI mismatch that only that lane could see, so never change the options module, the macros, or an `extern` declaration without running it.

The guide is `docs/content/_index.md` on the baskingspot docs theme. `just doc` builds the site into `zig-out/site/tracy/`, `just guide` serves it with live reload, and the API reference comes from docgen over `src/root.zig`. The guide's code blocks are files in `docs/examples/`, embedded with `load_data` and compiled by `just test`.

## The two places the client's version lives

`build.zig.zon` fetches the client at a tag, and `client_version` at the top of `build.zig` names the directory inside that archive. Bump both in one change. The `just client` lane fails when they disagree, with a missing `TracyClient.cpp`.

The client's C API is a compile-time contract. `public/tracy/TracyC.h` decides the argument lists of the `___tracy_*` functions and the layout of `___tracy_c_zone_context`, which changes under `TRACY_ON_DEMAND`. `THIRD_PARTY.md` lists what the module depends on. Read that header before you move the tag.

## Rules

- Lint with `ziglint-0-17`, not `ziglint`: the wrapper points ziglint at the 0.17 std, the minimum supported.
- `src/root.zig` is adapted code. Keep the `ziglint-ignore` comments on the lines that need them, and add a line to `THIRD_PARTY.md` when the adaptation grows.
- Commit messages are one line, `area: summary`, and every commit is signed. Do not rewrite pushed history.
- Gate commands on their exit codes, and claim only what you ran.
- This repo's GitHub settings come from `baskingspot/.github`, with `just settings`. Do not change them by hand.

## Changelog

`CHANGELOG.md` is one file, Keep a Changelog format, newest first. Add a bullet under `## [Unreleased]` in the same change that alters something a user can notice: the public API, expected behavior, performance a benchmark row would show, a supported backend, or the build requirements. Docs, CI, and internal refactors do not need one unless they change how someone uses the package.

Write from the user's side: what changed, and what they must do about it. Name the symbol, flag, or error. One line, under Added, Changed, Fixed, or Removed.

To release, run `release-prep.py VERSION` in the repo, with the script from `baskingspot/.github`, review the diff, commit it signed, push, then `gh workflow run release.yml -f version=X.Y.Z`. The prep moves the Unreleased section into a dated heading, sets `.version` in `build.zig.zon`, and points the install command at the tag. The workflow changes no files and creates no commit, and it refuses a version the changelog does not carry. Do not tag by hand.
