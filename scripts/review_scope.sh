#!/usr/bin/env bash
# Print the review scope for a commit range or a full-audit subsystem: changed files,
# their subsystem, suggested reviewers and code-graph freshness. Read-only.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review_scope.sh [RANGE | --worktree | --subsystem ID | --list-subsystems]

  RANGE              git range such as abc123..HEAD or HEAD~3..HEAD.
                     Default: <last reviewed commit in reviews/STATE.md>..HEAD,
                     or HEAD~1..HEAD when none is recorded.
  --worktree         Scope uncommitted changes against HEAD.
  --subsystem ID     List every file of a full-audit subsystem (see --list-subsystems).
  --list-subsystems  Print subsystem ids and their primary reviewers.
  --help             Show this help text.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

SUBSYSTEMS="ui state scanner metadata rust kotlin audio storage tests build"

# First match wins, so every file belongs to exactly one subsystem.
subsystem_of() {
  case "$1" in
    graphify-out/*|reviews/*|build/*|.dart_tool/*|rust_backend/vendor/*|third_party/*) echo skip ;;
    lib/l10n/*.arb|*.md|docs/*|.claude/*|.opencode/*) echo docs ;;
    test/*|integration_test/*|scripts/test_*|android/app/src/test/*|android/app/src/androidTest/*) echo tests ;;
    pubspec.*|*.gradle|*.gradle.kts|android/gradle*|android/app/src/main/AndroidManifest.xml|rust_backend/Cargo.*|rust_backend/rust-toolchain.toml|analysis_options.yaml|l10n.yaml|.fvmrc) echo build ;;
    rust_backend/*) echo rust ;;
    android/app/src/main/cpp/*|android/*/NativeAudio*.kt|android/*/HiRes*.kt|android/*/Usb*.kt|android/*/BitPerfect*.kt|android/*/Dsd*.kt|android/*/AudioOutput*.kt|android/*/BackgroundWork*.kt|android/*/ForegroundService*.kt|android/*/PlayerWidget*.kt|android/*/NativeReplayGain*.kt) echo audio ;;
    android/*) echo kotlin ;;
    lib/services/music_*|lib/services/playback_*|lib/services/automix*|lib/services/autoplay*|lib/services/notification_service.dart|lib/services/player_widget_service.dart|lib/services/system_volume_service.dart|lib/services/content_uri_playback_cache.dart|lib/providers/*playback*|lib/providers/music_player*|lib/utils/local_playback.dart|lib/utils/playback_*|lib/utils/progress_stream_poller.dart) echo audio ;;
    lib/services/platform_bridge.dart|lib/services/library_native_adapter.dart|lib/services/native_*) echo kotlin ;;
    lib/services/*database*|lib/services/library_schema.dart|lib/services/sqlite_*|lib/services/backup_service.dart|lib/services/collection_*|lib/services/m3u_*|lib/services/csv_*|lib/services/user_profile_store.dart|lib/services/history_*|lib/services/listening_statistics.dart|lib/services/library_queue_store.dart|lib/services/library_collections_*) echo storage ;;
    lib/services/ffmpeg_*|lib/services/*metadata*|lib/services/id3v23_lyrics.dart|lib/services/replaygain_service.dart|lib/services/*cover*|lib/services/audio_analysis_*|lib/utils/lyrics_*|lib/utils/cover_art_utils.dart|lib/utils/ffmpeg_*|lib/utils/re_enrich_*|lib/controllers/metadata_*) echo metadata ;;
    lib/services/library_*|lib/services/deleted_library_files.dart|lib/services/source_deletion_events.dart|lib/services/file_access_check.dart|lib/utils/local_library_scan_prefs.dart|lib/utils/file_access.dart|lib/utils/saf_display_path.dart|lib/utils/path_match_keys.dart|lib/utils/duplicate_cleanup_policy.dart) echo scanner ;;
    lib/screens/*|lib/widgets/*|lib/theme/*|lib/routes/*|lib/constants/*) echo ui ;;
    scripts/*|lib/*) echo state ;;
    *) echo build ;;
  esac
}

primary_of() {
  case "$1" in
    ui) echo flutter-dart-auditor ;;
    state) echo bug-hunter ;;
    scanner|metadata|storage) echo data-integrity-auditor ;;
    rust) echo rust-safety-auditor ;;
    kotlin) echo kotlin-android-auditor ;;
    audio) echo concurrency-auditor ;;
    tests) echo test-auditor ;;
    build) echo dependency-auditor ;;
    docs) echo docs-auditor ;;
  esac
}

secondary_of() {
  case "$1" in
    ui) echo ux-auditor ;;
    state) echo flutter-dart-auditor ;;
    scanner|metadata) echo bug-hunter ;;
    rust) echo concurrency-auditor ;;
    kotlin) echo api-compat-auditor ;;
    audio) echo kotlin-android-auditor ;;
    storage|build) echo api-compat-auditor ;;
    *) echo - ;;
  esac
}

# Extra reviewers triggered by specific paths regardless of line counts.
flag_of() {
  case "$1" in
    android/*/Saf*.kt|android/app/src/main/AndroidManifest.xml|lib/utils/file_access.dart|lib/services/file_access_check.dart) echo security-auditor ;;
    lib/services/platform_bridge.dart|lib/services/library_schema.dart|lib/services/backup_service.dart|rust_backend/crates/mobile/*) echo api-compat-auditor ;;
  esac
}

graph_commit() {
  sed -n 's/^- Built from commit: `\([0-9a-f]*\)`.*/\1/p' graphify-out/GRAPH_REPORT.md 2>/dev/null | head -1
}

# Prints "fresh", "stale (N files changed since <sha>)" or "missing" for the given files.
graph_status() {
  local built
  built="$(graph_commit)"
  if [[ ! -f graphify-out/graph.json || -z "$built" ]]; then
    echo missing
    return
  fi
  if ! git cat-file -e "$built^{commit}" 2>/dev/null; then
    echo "unknown (graph commit $built not in history)"
    return
  fi
  local changed
  changed="$( { git diff --name-only "$built" HEAD -- "$@"; git diff --name-only HEAD -- "$@"; } | sort -u | grep -c . || true)"
  if [[ "$changed" == 0 ]]; then
    echo "fresh (built from $built)"
  else
    echo "stale ($changed scoped files changed since $built; use source inspection)"
  fi
}

list_subsystems() {
  printf '%-9s %-24s %s\n' id primary secondary
  for s in $SUBSYSTEMS; do
    printf '%-9s %-24s %s\n' "$s" "$(primary_of "$s")" "$(secondary_of "$s")"
  done
}

scope_subsystem() {
  local id="$1" files=() f
  [[ " $SUBSYSTEMS " == *" $id "* ]] || { echo "Error: unknown subsystem: $id" >&2; exit 2; }
  while IFS= read -r f; do
    [[ "$(subsystem_of "$f")" == "$id" ]] && files+=("$f")
  done < <(git ls-files lib test integration_test android rust_backend scripts pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml .fvmrc \
    | grep -Ev '\.(png|jpg|jpeg|webp|ttf|otf|so|jar|xml)$|/res/|^rust_backend/vendor/' ; \
    git ls-files android/app/src/main/AndroidManifest.xml)
  ((${#files[@]})) || { echo "No files in subsystem $id"; exit 0; }

  local reviewed
  reviewed="$(awk -F'|' -v id="$id" '$2 ~ "^ *"id" *$" {gsub(/[ `]/, "", $5); print $5}' reviews/coverage.md 2>/dev/null || true)"
  echo "Subsystem: $id"
  echo "Reviewers: $(primary_of "$id") (+ $(secondary_of "$id") when needed)"
  echo "Graph:     $(graph_status "${files[@]}")"
  if [[ "$reviewed" =~ ^[0-9a-f]{7,40}$ ]] && git cat-file -e "$reviewed^{commit}" 2>/dev/null; then
    local changed
    changed="$(git diff --name-only "$reviewed" HEAD -- "${files[@]}" | grep -c . || true)"
    if [[ "$changed" == 0 ]]; then
      echo "Reviewed:  $reviewed (up to date; skip unless asked)"
    else
      echo "Reviewed:  $reviewed ($changed files changed since; audit only those)"
    fi
  else
    echo "Reviewed:  never"
  fi
  echo "Files (${#files[@]}, lines):"
  wc -l "${files[@]}" | sort -rn | sed 1d
}

scope_range() {
  local range="$1" label="$2"
  local -a numstat
  mapfile -t numstat < <(git diff --numstat $range)
  if ((${#numstat[@]} == 0)); then
    echo "No changes in $label."
    exit 0
  fi

  local -A lines_by_reviewer=()
  local -A flags=()
  local files=() code_files=() total=0 docs_lines=0 test_lines=0 line add del path sub n reviewer flag
  echo "Range: $label"
  if [[ "$range" != HEAD ]]; then
    echo "Commits:"
    git log --oneline --no-decorate $range | sed 's/^/  /'
  fi
  echo "Files:"
  for line in "${numstat[@]}"; do
    IFS=$'\t' read -r add del path <<<"$line"
    sub="$(subsystem_of "$path")"
    [[ "$sub" == skip ]] && continue
    [[ "$add" == - ]] && add=0
    [[ "$del" == - ]] && del=0
    n=$((add + del))
    files+=("$path")
    if [[ "$sub" == docs ]]; then
      docs_lines=$((docs_lines + n))
    else
      code_files+=("$path")
      [[ "$sub" == tests ]] && test_lines=$((test_lines + n))
      reviewer="$(primary_of "$sub")"
      lines_by_reviewer[$reviewer]=$(( ${lines_by_reviewer[$reviewer]:-0} + n ))
    fi
    flag="$(flag_of "$path")"
    [[ -n "$flag" ]] && flags[$flag]=1
    printf '  %-9s %5s  %s\n' "$sub" "+$add/-$del" "$path"
  done
  if ((${#files[@]} == 0)); then
    echo "  (only generated or review-state files changed; nothing to review)"
    exit 0
  fi
  if git log --format=%s $range 2>/dev/null | grep -qiE 'perf|optimi[sz]|speed ?up|faster|cache'; then
    flags[code-optimization-auditor]=1
  fi

  for r in "${!lines_by_reviewer[@]}"; do total=$((total + lines_by_reviewer[$r])); done
  echo "Changed lines: $total code, $docs_lines docs/translations"
  # Heuristics only: a large change with few test lines, or one too big for one brief.
  if ((total - test_lines > 100 && test_lines * 5 < total)); then
    echo "NO_TEST_CHANGES: $test_lines of $total changed lines are tests"
  fi
  if ((total > 400)); then
    echo "SPLIT_SUGGESTED: over 400 changed lines; review per commit or subsystem"
  fi
  if ((${#code_files[@]} == 0)); then
    echo "Graph: not needed (docs only)"
    echo "Suggested reviewers: docs-auditor (or the orchestrator directly for small edits)"
    return
  fi
  echo "Graph: $(graph_status "${code_files[@]}")"
  echo "Suggested reviewers (max 3; default 1):"
  # Primary reviewer by changed lines, a second when it owns >=20% or a path flag applies,
  # a third only for large (>400 line) changes where it owns >=15%.
  local picked=0 r share
  while IFS=$'\t' read -r n r; do
    share=$(( total ? n * 100 / total : 0 ))
    if (( picked == 0 )) || (( picked == 1 && share >= 20 )) || (( picked == 2 && total > 400 && share >= 15 )); then
      printf '  %-26s %3s%% of changed lines\n' "$r" "$share"
      picked=$((picked + 1))
      unset 'flags[$r]'
    fi
    (( picked < 3 )) || break
  done < <(for r in "${!lines_by_reviewer[@]}"; do printf '%s\t%s\n' "${lines_by_reviewer[$r]}" "$r"; done | sort -rn)
  for r in "${!flags[@]}"; do
    (( picked < 3 )) || break
    printf '  %-26s path/commit trigger\n' "$r"
    picked=$((picked + 1))
  done
  ((docs_lines == 0)) || echo "  docs-auditor only if AGENTS.md rules or l10n keys changed meaningfully"
  ((total >= 30 || ${#code_files[@]} > 1)) || echo "Tiny change: the orchestrator may review it directly."
}

last_reviewed() {
  sed -n 's/^- Last reviewed commit: `\([0-9a-f]\{7,40\}\)`.*/\1/p' reviews/STATE.md 2>/dev/null | head -1
}

if (( $# > 2 )); then
  usage >&2
  exit 2
fi
case "${1:-}" in
  --help|-h) usage ;;
  --list-subsystems) list_subsystems ;;
  --subsystem)
    [[ -n "${2:-}" ]] || { usage >&2; exit 2; }
    scope_subsystem "$2"
    ;;
  --worktree) scope_range HEAD "uncommitted changes vs HEAD" ;;
  -*) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  "")
    base="$(last_reviewed)"
    if [[ -n "$base" ]] && git cat-file -e "$base^{commit}" 2>/dev/null; then
      scope_range "$base..HEAD" "$base..HEAD (since last review)"
    else
      scope_range "HEAD~1..HEAD" "HEAD~1..HEAD"
    fi
    ;;
  *) scope_range "$1" "$1" ;;
esac
