# tracy: Tracy profiler bindings for Zig. README.md says what the package is;
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests and the guide's examples")]
[group("test")]
test:
    zig build test --summary all

[doc("Build and run a program against the compiled Tracy client: proves the client wiring links and runs")]
[group("test")]
client:
    zig build client --summary all

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, the ast-grep rules, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint-0-17
    baskingspot-lint src
    zig fmt --check src test docs/examples build.zig build.zig.zon
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content docs/config.toml .github wrangler.jsonc .oxfmtrc.jsonc
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src test docs/examples build.zig build.zig.zon
    nix fmt
    oxfmt README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content docs/config.toml .github wrangler.jsonc .oxfmtrc.jsonc
    just --fmt

[doc("The gate: the tests, the client lane, lint, and the docs build")]
[group("ci")]
ci: test client lint doc

[doc("Build the site into zig-out/site/tracy/: the guide (Zola, from docs/) and the API reference (docgen JSON, rendered by the theme's api.html) under api/. The router in baskingspot/site serves /tracy/... from it")]
[group("docs")]
doc: api
    baskingspot-docs build tracy

[doc("Edit the guide with live reload (http://127.0.0.1:1111), API reference included")]
[group("docs")]
guide: api
    baskingspot-docs serve tracy

# The API reference data. docgen comes from the baskingspot flake's docs shell,
# so this is not a Zig build dependency.
[private]
api:
    docgen --root src/root.zig --title tracy --repo-url https://github.com/baskingspot/tracy --rev main --format json --out docs/data

[doc("Deploy the rendered docs to Cloudflare as an assets-only Worker (config in wrangler.jsonc). Needs CLOUDFLARE_API_TOKEN in the environment, plus CLOUDFLARE_ACCOUNT_ID if the token can see more than one account")]
[group("docs")]
doc-deploy: doc
    wrangler deploy
