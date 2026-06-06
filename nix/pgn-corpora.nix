# Cloudflare R2-hosted PGN corpora — shared resource for any chess-flake shell
# that needs sample game data (benchmarks, tests, training, ingest pilots).
#
# Exposed as `packages.pgn-corpora` (a linkFarm of `<name>.pgn` files in the
# nix store). Each consuming shell points its own env var at the package:
#   alexander shell  -> ALEXANDER_BENCH_DATA
#   <future shell>   -> <its own>_PGN_DIR
# The resource itself is project-agnostic.
#
# This file lives in the workspace (not in any single project) because the
# workspace is the single source of truth under the top-down model. Adding a
# corpus is a workspace commit.
#
# A public R2 object is served over plain HTTPS with no SigV4 signing — exactly
# what Nix's fetcher needs. Public URLs:
#   - Managed "Public Development URL":  https://pub-<hash>.r2.dev/<key>
#   - A custom domain:                   https://data.example.com/<key>
#
# To pin a dataset:
#   nix store prefetch-file --json "<public-url>" | jq -r .hash
#
# Example:
#   twic-1900 = {
#     url = "https://pub-0123456789abcdef.r2.dev/twic-1900.pgn";
#     sha256 = "sha256-0000000000000000000000000000000000000000000=";
#   };
#
# The set may stay empty: shells still work, and benchmarks that need a corpus
# skip themselves when the file is absent.
{
}
