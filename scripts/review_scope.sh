#!/usr/bin/env bash
# Read-only scope inventory; Python stdlib preserves NUL-delimited Git paths.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/review_scope.py" "$@"
