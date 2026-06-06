# Cloudflare R2-hosted PGN datasets for the `alexander` engine — exposed to
# benchmarks/tests via `$ALEXANDER_BENCH_DATA/<name>.pgn`.
#
# This file lives in the workspace (not in alexander-project) because the
# workspace is the single source of truth for project shells under the
# top-down model. Adding a corpus is a workspace commit.
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
# The set may stay empty: the alexander shell still works, and benchmarks that
# need a corpus skip themselves when the file is absent.
{
}
