# chess-flake

Shared Nix environment provider for the polyrepo at `~/projects/chess/`.
Exposes a **library** (`workspace.lib.${system}`) of primitives and opinionated
bundles. Each consumer project composes its own shell from this library — the
workspace does NOT enumerate projects.

Single source of truth for:

- One Rust toolchain (`rust-toolchain.toml` here is canonical)
- One nixpkgs pin → unified `openssl`, `sqlite`, system libs
- One Node version + `pnpm` across all JS projects
- LSPs (`rust-analyzer`, `typescript-language-server`, `svelte-language-server`)
- Shared resources (`packages.pgn-corpora`)

This flake **does not** mutualise cargo crate caches or `node_modules` — those
stay per-project. The win here is the build environment, not the application
dependency graph. Cross-project Rust deps are handled at the cargo layer via
git-tagged deps; cross-project npm deps via the standard pnpm content-addressed
global store (`~/Library/pnpm`).

## Public API

### Bundles (opinionated shell shapes)

Every bundle takes `{ name, extra ? [], env ? {}, hook ? "" }`. Most projects
use a bundle verbatim; projects with extras add them through the knobs.

| Bundle | Stack | What's inside |
|---|---|---|
| `lib.bundles.rustShell` | Rust | `rustToolchain` + `rust-analyzer` + `cargo-nextest`, sets `RUST_SRC_PATH` |
| `lib.bundles.nodeShell` | Node | `nodejs_22` + `pnpm` + TS/Svelte LSPs + `prettier` |
| `lib.bundles.tauriShell` | Rust + Node + Tauri | `rustShell` ∪ `nodeShell` + `pkg-config` (macOS sysdeps) |

### Primitives (compose your own shell)

`lib.mkProjectShell { name; packages; env ? {}; hook ? "" }` is the bare
composer. Useful when the bundles don't fit. Reach for it instead of
re-implementing the `commonTools`, `CARGO_HOME`, zsh-reexec scaffolding.

`lib.{rustTools, nodeTools, tauriDarwinTools, commonTools, rustToolchain}` —
the underlying package lists. `lib.pkgs` is the pinned nixpkgs for one-off
extras like `pkgs.samply`.

### Resources

`workspace.packages.${system}.pgn-corpora` — linkFarm of `<name>.pgn` files
in the nix store. Reproducible, R2-sourced. Empty today (see
`nix/pgn-corpora.nix` for how to add a corpus). Consumers route it to their
own env var name, e.g. `env.ALEXANDER_BENCH_DATA = pkgs.pgn-corpora`.

## Consumer pattern

Each project's `flake.nix` is ~10 lines:

```nix
{
  inputs.workspace.url = "git+ssh://git@github.com/obazin/chess-flake.git?ref=main";
  outputs = { self, workspace }: {
    devShells = builtins.mapAttrs (system: lib: {
      default = lib.bundles.rustShell { name = "pepsin"; };
    }) workspace.lib;
  };
}
```

For projects that need extras:

```nix
default = lib.bundles.rustShell {
  name = "uci-orchestra";
  extra = [ lib.pkgs.samply ];
};
```

For projects that consume shared resources:

```nix
default = lib.bundles.rustShell {
  name = "alexander";
  extra = [ lib.pkgs.samply ];
  env.ALEXANDER_BENCH_DATA = workspace.packages.${system}.pgn-corpora;
};
```

## Use

With `.envrc` (`use flake`) + `direnv allow`, `cd <project>` auto-loads the
shell. Or invoke directly:

```bash
nix develop ~/projects/chess/<project>
nix develop ~/projects/chess/chess-flake     # workspace meta-shell
```

## Bumping versions

```bash
cd ~/projects/chess/chess-flake
nix flake update                # bump everything
nix flake update rust-overlay   # bump just one input
```

After bumping + push, each consumer project needs `nix flake update workspace`
once to pick up the new workspace lock.
