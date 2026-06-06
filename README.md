# chess-flake

Shared Nix toolchain pins and per-project devShells for the polyrepo at
`~/projects/chess/`. Single source of truth for:

- One Rust toolchain (`rust-toolchain.toml` here is canonical)
- One nixpkgs pin → unified `openssl`, `sqlite`, system libs
- One Node version + `pnpm` across all JS projects
- LSPs (`rust-analyzer`, `typescript-language-server`, `svelte-language-server`)

This flake **does not** mutualise cargo crate caches or `node_modules` — those
stay per-project. The win here is the build environment, not the application
dependency graph. Cross-project Rust deps are handled at the cargo layer via
git-tagged deps; cross-project npm deps via the standard pnpm content-addressed
global store (`~/Library/pnpm`).

## Project shells

| Shell | Stack | Project root |
|---|---|---|
| `alexander` | Rust + bench data | `../alexander-project/` |
| `pepsin` | Rust | `../pepsin/` |
| `pgn-tools` | Rust | `../pgn-tools/` |
| `chess-graphics` | Rust | `../chess-graphics-project/` |
| `uci-orchestra` | Rust + samply | `../uci-orchestra/` |
| `vera` | Rust + Node + Tauri | `../vera/` |
| `staunton` | Node | `../staunton/` |
| `svelte-chessground` | Node | `../svelte-chessground/` |
| `default` | Workspace itself | `.` |

## Use

From any project dir with the matching delegate flake + `.envrc`:

```bash
cd ../vera
direnv allow      # one-time
# walking in now auto-loads the vera shell
```

Or invoke directly:

```bash
nix develop ~/projects/chess/chess-flake#vera
nix develop github:obazin/chess-flake#vera   # once published
```

## Bumping versions

```bash
cd ~/projects/chess/chess-flake
nix flake update                # bump everything
nix flake update rust-overlay   # bump just one input
```

After bumping, each consumer project needs `nix flake update` once to pick up
the new workspace lock (same commit dance as the git-tagged cross-project Rust
deps).
