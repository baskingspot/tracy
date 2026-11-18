const std = @import("std");

/// What a consumer sets with `b.dependency("tracy", .{ ... })`, or on the
/// command line as `-Denable`, `-Denable_allocation`, and so on. The field
/// name is the option name in both places.
pub const Options = struct {
    /// Compile the Tracy client in and emit events. When false, every public
    /// function in the module is a no-op and the client is never compiled.
    enable: bool = false,
    /// Report memory through `TracyAllocator`. Defaults to `enable`.
    enable_allocation: bool = false,
    /// Collect a callstack with every zone, message, and allocation. Defaults
    /// to `enable`.
    enable_callstack: bool = false,
    /// Emit only while a profiler is connected, so a program running without
    /// one pays for nothing.
    enable_on_demand: bool = false,
    /// Bind the profiler's listener to the loopback address and stop
    /// announcing it on the network. A profiler connects through a port
    /// forward, not over the LAN.
    only_localhost: bool = false,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable = b.option(bool, "enable", "Compile the Tracy client in and emit events") orelse false;
    const enable_allocation = b.option(bool, "enable_allocation", "Report memory through TracyAllocator") orelse enable;
    const enable_callstack = b.option(bool, "enable_callstack", "Collect a callstack with every event") orelse enable;
    const enable_on_demand = b.option(bool, "enable_on_demand", "Emit only while a profiler is connected") orelse false;
    const only_localhost = b.option(
        bool,
        "only_localhost",
        "Bind the listener to loopback and stop announcing it",
    ) orelse false;
    const mod = module(b, "tracy", target, optimize, .{
        .enable = enable,
        .enable_allocation = enable_allocation,
        .enable_callstack = enable_callstack,
        .enable_on_demand = enable_on_demand,
        .only_localhost = only_localhost,
    });

    // A consumer's fetch graph stops at this module. Everything below is for
    // working on the package itself.
    if (b.pkg_hash.len != 0) return;

    // testingx provides the test runner. It is lazy because only the root
    // build uses it. On the first configure pass it is not fetched yet,
    // `dependencyLazy` reports that it is needed, and the build runner
    // fetches it and reruns this script.
    const testingx_dep = b.dependencyLazy("testingx", .{ .target = target }) catch null;
    const test_runner: ?std.Build.Step.Compile.TestRunner = if (testingx_dep) |dep|
        .{ .path = dep.path("src/runner.zig"), .mode = .simple }
    else
        null;

    const test_step = b.step("test", "Run the unit tests and the guide's examples");

    const unit_tests = b.addTest(.{ .root_module = mod, .test_runner = test_runner });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // The guide's code blocks are files under docs/examples, imported here so
    // a page cannot show code that does not build.
    const examples_mod = b.createModule(.{
        .root_source_file = b.path("docs/examples/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "tracy", .module = mod }},
    });
    const example_tests = b.addTest(.{ .root_module = examples_mod, .test_runner = test_runner });
    test_step.dependOn(&b.addRunArtifact(example_tests).step);

    // The client lane: a program that emits real events through the C client,
    // built and run so a change to the client wiring fails CI rather than a
    // user's build. It pins the options that keep CI quiet: on demand, and
    // loopback only.
    const client_step = b.step("client", "Build and run a program against the compiled Tracy client");
    const client_mod = module(b, null, target, optimize, .{
        .enable = true,
        .enable_allocation = true,
        .enable_callstack = false,
        .enable_on_demand = true,
        .only_localhost = true,
    });
    const client_exe = b.addExecutable(.{
        .name = "tracy-client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "tracy", .module = client_mod }},
        }),
    });
    client_step.dependOn(&b.addRunArtifact(client_exe).step);
}

/// The module a consumer imports as `tracy`, with the options module it needs
/// and, when enabled, the upstream C client compiled into it.
fn module(
    b: *std.Build,
    comptime name: ?[]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    options: Options,
) *std.Build.Module {
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable", options.enable);
    build_options.addOption(bool, "enable_allocation", options.enable and options.enable_allocation);
    build_options.addOption(bool, "enable_callstack", options.enable and options.enable_callstack);
    // The zone context carries a connection id only when the client is built
    // with TRACY_ON_DEMAND, so the Zig view of the struct depends on it.
    build_options.addOption(bool, "enable_on_demand", options.enable and options.enable_on_demand);

    const config: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "tracy_options", .module = build_options.createModule() }},
        .link_libc = options.enable,
        .link_libcpp = options.enable,
        .sanitize_c = .off,
    };
    const mod = if (name) |n| b.addModule(n, config) else b.createModule(config);
    if (!options.enable) return mod;

    mod.addCMacro("TRACY_ENABLE", "1");
    if (options.only_localhost) {
        mod.addCMacro("TRACY_ONLY_LOCALHOST", "1");
        mod.addCMacro("TRACY_NO_BROADCAST", "1");
    }
    if (options.enable_on_demand) mod.addCMacro("TRACY_ON_DEMAND", "1");

    // The client is vendored under vendor/tracy at the tag THIRD_PARTY.md
    // records. TracyClient.cpp includes from both the root and public/.
    mod.addIncludePath(b.path("vendor/tracy"));
    mod.addIncludePath(b.path("vendor/tracy/public"));
    mod.addCSourceFile(.{
        .file = b.path("vendor/tracy/public/TracyClient.cpp"),
    });

    return mod;
}
