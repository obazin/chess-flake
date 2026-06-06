{
  description = "Chess workspace — shared toolchain pins and per-project devShells";

  # Single source of truth for nixpkgs + the Rust toolchain pin. Every project
  # in ../<name>/ inherits these via a 3-line delegate flake that points at this
  # workspace's `devShells.<system>.<project>`. Bump revisions here and run
  # `nix flake update` from each consumer to roll forward.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # ── Toolchain ───────────────────────────────────────────────────────
        # Reads the workspace's own rust-toolchain.toml — projects do not pin
        # their own toolchain; their local rust-toolchain.toml (where present)
        # is a hint for non-Nix editors only and must match this one.
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        # ── Reusable package sets ───────────────────────────────────────────
        commonTools = with pkgs; [
          git
          just
          ripgrep
          fd
          jq
          zsh
        ];

        rustTools = [
          rustToolchain # rustc, cargo, clippy, rustfmt, rust-src
          pkgs.rust-analyzer
          pkgs.cargo-nextest
        ];

        nodeTools = with pkgs; [
          nodejs_22
          pnpm
          nodePackages.typescript-language-server
          nodePackages.svelte-language-server
          nodePackages.prettier
        ];

        # macOS: Tauri builds against the system WebKit, so the dev shell needs
        # very little beyond rust + node + pkg-config. Linux would add gtk3,
        # webkitgtk_4_1, libsoup_3, openssl here — gated on `stdenv.isLinux`.
        tauriDarwinTools = [ pkgs.pkg-config ];

        # ── Shared resources ────────────────────────────────────────────────
        # Reproducible PGN corpora (R2-hosted). Shared across any shell that
        # needs sample games. Each consuming shell maps it to its own env var.
        # Empty set today — see nix/pgn-corpora.nix for how to add a corpus.
        pgnCorporaSpec = import ./nix/pgn-corpora.nix;
        pgnCorpora = pkgs.linkFarm "pgn-corpora" (
          pkgs.lib.mapAttrsToList (name: d: {
            name = "${name}.pgn";
            path = pkgs.fetchurl {
              inherit (d) url sha256;
              name = "${name}.pgn";
            };
          }) pgnCorporaSpec
        );

        # ── Shell composer ──────────────────────────────────────────────────
        # Every project shell goes through this. It pins CARGO_HOME inside the
        # consumer's project root (not ~/.cargo), so leaving / deleting the
        # project touches nothing else. zsh re-exec mirrors alexander's pattern
        # but is gated on interactive + not-already-in-our-zsh.
        mkProjectShell =
          {
            name,
            packages,
            env ? { },
            hook ? "",
          }:
          pkgs.mkShell (
            {
              name = "chess-${name}";
              packages = commonTools ++ packages;
              shellHook = ''
                # Keep cargo's caches per-project, not in $HOME.
                export CARGO_HOME="''${CARGO_HOME:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.cargo}"
                echo "chess-flake · ${name} · $(date +%H:%M:%S)"
                ${hook}
                export SHELL=${pkgs.zsh}/bin/zsh
                if [[ $- == *i* && -z "''${IN_CHESS_FLAKE_ZSH:-}" ]]; then
                  export IN_CHESS_FLAKE_ZSH=1
                  exec ${pkgs.zsh}/bin/zsh
                fi
              '';
            }
            // env
          );

      in
      {
        devShells = rec {
          # Rust-only projects — toolchain + analyzer + nextest
          pepsin = mkProjectShell {
            name = "pepsin";
            packages = rustTools;
            env.RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          pgn-sort = mkProjectShell {
            name = "pgn-sort";
            packages = rustTools;
            env.RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          chess-graphics = mkProjectShell {
            name = "chess-graphics";
            packages = rustTools;
            env.RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          uci-orchestra = mkProjectShell {
            name = "uci-orchestra";
            packages = rustTools ++ [ pkgs.samply ];
            env.RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          alexander = mkProjectShell {
            name = "alexander";
            packages = rustTools ++ [ pkgs.samply ];
            env = {
              RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
              # alexander's bench code reads $ALEXANDER_BENCH_DATA; the shared
              # corpora package is exposed as `packages.pgn-corpora` and
              # routed here. Other shells can route the same package to their
              # own env var names.
              ALEXANDER_BENCH_DATA = pgnCorpora;
            };
            hook = ''
              echo "  pgn corpora: ${pgnCorpora}"
            '';
          };

          # JS-only projects — pnpm + node + LSPs
          staunton = mkProjectShell {
            name = "staunton";
            packages = nodeTools;
          };

          svelte-chessground = mkProjectShell {
            name = "svelte-chessground";
            packages = nodeTools;
          };

          # Tauri — Rust + Node + macOS frameworks via pkg-config
          vera = mkProjectShell {
            name = "vera";
            packages = rustTools ++ nodeTools ++ tauriDarwinTools;
            env.RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          # Default = working on the workspace itself
          default = pkgs.mkShell {
            name = "chess-flake-workspace";
            packages = commonTools;
            shellHook = ''
              echo "chess-flake · workspace shell"
              echo "available project shells: alexander, pepsin, pgn-sort, chess-graphics, uci-orchestra, vera, staunton, svelte-chessground"
            '';
          };
        };

        # Buildable artifacts surfaced by the workspace. Add more as needed.
        packages.pgn-corpora = pgnCorpora;
      }
    );
}
