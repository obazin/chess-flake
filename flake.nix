{
  description = "Chess workspace — shared toolchain pins, library of bundles + primitives";

  # The workspace owns the canonical Rust toolchain, the nixpkgs pin, the Node
  # version, and shared resources (pgn-corpora). It does NOT enumerate consumer
  # projects — projects compose their own shells from `lib` exposed here.
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
        # Reads the workspace's own rust-toolchain.toml. Consumer projects do
        # not pin their own toolchain.
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        # ── Reusable package sets (primitives) ──────────────────────────────
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
          # sccache caches compiled rustc outputs by content hash. Wired into
          # rustEnv via RUSTC_WRAPPER. The cache at ~/.cache/sccache/ is shared
          # across every Rust project on the host (not just chess-flake), so
          # building project B after project A finds tokio/serde/etc. already
          # compiled. Run `sccache --show-stats` to see hit rate.
          pkgs.sccache
        ];

        nodeTools = with pkgs; [
          nodejs_22
          pnpm
          nodePackages.typescript-language-server
          nodePackages.svelte-language-server
          tailwindcss-language-server
          vtsls
          nodePackages.prettier
        ];

        # macOS: Tauri builds against the system WebKit, so the dev shell needs
        # very little beyond rust + node + pkg-config. Linux would add gtk3,
        # webkitgtk_4_1, libsoup_3, openssl here (gated on `stdenv.isLinux`).
        tauriDarwinTools = [ pkgs.pkg-config ];

        # ── Shared resources ────────────────────────────────────────────────
        # Reproducible PGN corpora (R2-hosted). Project-agnostic. Each
        # consuming shell maps it to its own env var name.
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

        # ── Shared formatting config ────────────────────────────────────────
        # Canonical prettier rules owned by the workspace — formatting only,
        # no plugins (so it can never break a project that lacks one). Built
        # into the store; Node/Tauri bundles symlink it into the project root
        # as .prettierrc.json on shell entry, so prettier and its LSP discover
        # it by walking up the tree. Consumers should gitignore .prettierrc.json.
        prettierConfig = pkgs.writeText "prettierrc.json" (
          builtins.toJSON {
            useTabs = true;
            tabWidth = 4;
            printWidth = 100;
          }
        );

        # Materializes prettierConfig at the project root. Prepended to the
        # Node/Tauri bundle hooks so every JS-touching shell enforces it.
        prettierHook = ''
          ln -sfn ${prettierConfig} "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")/.prettierrc.json"
        '';

        # ── Primitive shell composer ────────────────────────────────────────
        # Pins CARGO_HOME inside the consumer's project root and exec'es into
        # zsh interactively. Bundles below wrap this with smart defaults.
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

        # ── Opinionated bundles ─────────────────────────────────────────────
        # Each bundle = a blessed shell shape. Projects pick a bundle and add
        # `extra` packages, `env` vars, or a `hook` line if they need to. The
        # uniformity win lives here: every Rust shell shares one definition,
        # drift is visible (the extras are in the project's own flake).
        rustEnv = {
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          # Route every rustc invocation through sccache so identical
          # crate+flags compilations across projects hit the shared cache
          # instead of recompiling.
          RUSTC_WRAPPER = "sccache";
        };

        bundles = {
          # Plain Rust shell — toolchain + analyzer + nextest + RUST_SRC_PATH.
          rustShell =
            {
              name,
              extra ? [ ],
              env ? { },
              hook ? "",
            }:
            mkProjectShell {
              inherit name hook;
              packages = rustTools ++ extra;
              env = rustEnv // env;
            };

          # Plain Node shell — nodejs_22 + pnpm + TS/Svelte LSPs + prettier.
          nodeShell =
            {
              name,
              extra ? [ ],
              env ? { },
              hook ? "",
            }:
            mkProjectShell {
              inherit name env;
              hook = prettierHook + hook;
              packages = nodeTools ++ extra;
            };

          # Tauri shell — Rust + Node + macOS pkg-config + RUST_SRC_PATH.
          tauriShell =
            {
              name,
              extra ? [ ],
              env ? { },
              hook ? "",
            }:
            mkProjectShell {
              inherit name;
              hook = prettierHook + hook;
              packages = rustTools ++ nodeTools ++ tauriDarwinTools ++ extra;
              env = rustEnv // env;
            };
        };

      in
      {
        # ── Public library ──────────────────────────────────────────────────
        # Consumer flake.nix files reach into this via
        # `workspace.lib.${system}.<thing>`. Stable API surface; treat changes
        # to these names as breaking.
        lib = {
          inherit
            pkgs
            rustToolchain
            commonTools
            rustTools
            nodeTools
            tauriDarwinTools
            prettierConfig
            mkProjectShell
            bundles
            ;
        };

        # ── Workspace's own meta-shell ──────────────────────────────────────
        # Default shell for editing chess-flake itself. Project shells are
        # composed in each project's flake — not here.
        devShells.default = pkgs.mkShell {
          name = "chess-flake-workspace";
          packages = commonTools;
          shellHook = ''
            echo "chess-flake · workspace shell"
            echo "  lib API: pkgs · rustToolchain · commonTools · rustTools · nodeTools · tauriDarwinTools · prettierConfig · mkProjectShell · bundles"
            echo "  bundles: rustShell · nodeShell · tauriShell"
            echo "  packages: pgn-corpora · prettier-config"
          '';
        };

        # ── Buildable artifacts surfaced by the workspace ───────────────────
        packages.pgn-corpora = pgnCorpora;
        packages.prettier-config = prettierConfig;
      }
    );
}
