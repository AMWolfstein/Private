#!/usr/bin/env bash
# Native unit checks; this task does not assemble or package an APK.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../android"
export SPOTIFLAC_RUST_ANDROID_ABIS="${SPOTIFLAC_RUST_ANDROID_ABIS:-arm64-v8a}"
exec ./gradlew :app:testDebugUnitTest --console=plain --max-workers="${SPOTIFLAC_GRADLE_MAX_WORKERS:-2}" "$@"
