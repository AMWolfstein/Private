#!/usr/bin/env python3
"""Read-only review inventory. Paths remain NUL-delimited until decoded by Python."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SUBSYSTEMS = {
    'ui': ('flutter-dart-auditor', 'ux-auditor'),
    'state': ('bug-hunter', 'flutter-dart-auditor'),
    'scanner': ('data-integrity-auditor', 'bug-hunter'),
    'metadata': ('data-integrity-auditor', 'bug-hunter'),
    'rust': ('rust-safety-auditor', 'concurrency-auditor'),
    'kotlin': ('kotlin-android-auditor', 'api-compat-auditor'),
    'audio': ('concurrency-auditor', 'kotlin-android-auditor'),
    'storage': ('data-integrity-auditor', 'api-compat-auditor'),
    'tests': ('test-auditor', '-'),
    'build': ('dependency-auditor', 'security-auditor'),
}


def git(*args):
    result = subprocess.run(['git', *args], cwd=ROOT, capture_output=True)
    if result.returncode:
        raise ValueError(result.stderr.decode(errors='replace').strip())
    return result.stdout


def paths(*args):
    return {p.decode(errors='surrogateescape') for p in git(*args).split(b'\0') if p}


def subsystem(path):
    # Changed bundled code is reviewable; unchanged vendor files are excluded only
    # from full inventory, never from an incremental scope.
    if path.startswith(('graphify-out/', 'reviews/', 'build/', '.dart_tool/')):
        return 'skip'
    if path.startswith(('third_party/', 'rust_backend/vendor/')):
        return 'build'
    if path.endswith('.md') or path.startswith(('docs/', '.claude/', '.opencode/', 'lib/l10n/')):
        return 'docs'
    if path.startswith(('test/', 'integration_test/', 'android/app/src/test/', 'android/app/src/androidTest/', 'scripts/test_')):
        return 'tests'
    name = Path(path).name
    if (name in ('Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', 'CMakeLists.txt', 'gradle.properties',
                 'analysis_options.yaml', 'l10n.yaml', '.fvmrc')
            or path.startswith(('pubspec.', '.github/', 'android/gradle'))
            or path.endswith(('.gradle', '.gradle.kts', '.cmake'))
            or '/res/xml/' in path or name == 'AndroidManifest.xml'):
        return 'build'
    if path.startswith('rust_backend/'):
        return 'rust'
    if path.startswith('android/'):
        audio_names = ('NativeAudio', 'HiRes', 'Usb', 'BitPerfect', 'Dsd', 'AudioOutput',
                       'BackgroundWork', 'ForegroundService', 'PlayerWidget', 'NativeReplayGain')
        return 'audio' if '/cpp/' in path or name.startswith(audio_names) else 'kotlin'
    if path.startswith(('lib/screens/', 'lib/widgets/', 'lib/theme/', 'lib/routes/', 'lib/constants/')):
        return 'ui'
    if path.startswith('lib/'):
        if name.startswith(('music_', 'playback_', 'automix', 'autoplay')) or name in (
                'notification_service.dart', 'player_widget_service.dart', 'system_volume_service.dart',
                'content_uri_playback_cache.dart', 'local_playback.dart', 'progress_stream_poller.dart'):
            return 'audio'
        if name in ('platform_bridge.dart', 'library_native_adapter.dart') or name.startswith('native_'):
            return 'kotlin'
        if 'database' in name or name.startswith(('sqlite_', 'collection_', 'library_collections_', 'm3u_', 'csv_', 'history_')) or name in (
                'library_schema.dart', 'backup_service.dart', 'user_profile_store.dart',
                'listening_statistics.dart', 'library_queue_store.dart'):
            return 'storage'
        if any(x in name for x in ('metadata', 'cover', 'lyrics')) or name.startswith(('ffmpeg_', 'audio_analysis_', 're_enrich_')):
            return 'metadata'
        if name.startswith('library_') or name in ('deleted_library_files.dart', 'source_deletion_events.dart',
                'file_access_check.dart', 'local_library_scan_prefs.dart', 'file_access.dart',
                'saf_display_path.dart', 'path_match_keys.dart', 'duplicate_cleanup_policy.dart'):
            return 'scanner'
        return 'state'
    return 'state' if path.startswith('scripts/') else 'build'


def flags(path):
    result = set()
    name = Path(path).name
    if ('Saf' in name or '/res/xml/' in path or name == 'AndroidManifest.xml'
            or name in ('file_access.dart', 'file_access_check.dart')
            or path.startswith(('third_party/', 'rust_backend/vendor/'))):
        result.add('security-auditor')
    if (name in ('platform_bridge.dart', 'library_schema.dart', 'backup_service.dart')
            or path.startswith('rust_backend/crates/mobile/') or 'Channel' in name):
        result.add('api-compat-auditor')
    return result


def baseline(unit):
    file = ROOT / 'reviews/coverage.md'
    if file.exists():
        for line in file.read_text().splitlines():
            columns = [c.strip(' `') for c in line.split('|')]
            if len(columns) > 5 and columns[1] == unit:
                sha = columns[4]
                if re.fullmatch('[0-9a-f]{7,40}', sha):
                    git('rev-parse', '--verify', sha + '^{commit}')
                    return sha, columns[3]
    return None, 'not reviewed'


def changed(base):
    # --no-renames deliberately reports both old and new names for independent routing.
    return (paths('diff', '--no-renames', '--name-only', '-z', base, 'HEAD', '--')
            | paths('diff', '--no-renames', '--name-only', '-z', 'HEAD', '--')
            | paths('ls-files', '--others', '--exclude-standard', '-z'))


def graph_status(scope):
    report = ROOT / 'graphify-out/GRAPH_REPORT.md'
    if not report.exists() or not (ROOT / 'graphify-out/graph.json').exists():
        return 'missing'
    match = re.search(r'^- Built from commit: `([0-9a-f]+)`', report.read_text(), re.M)
    if not match:
        return 'unknown (graph revision missing)'
    try:
        dirty = changed(match[1]) & set(scope)
    except ValueError:
        return 'unknown (graph revision unavailable)'
    return f'stale ({len(dirty)} scoped paths; use source inspection)' if dirty else f'fresh (built from {match[1]})'


def inventory(unit):
    sha, recorded = baseline(unit)
    current = paths('ls-files', '-z') | paths('ls-files', '--others', '--exclude-standard', '-z')
    historical = paths('ls-tree', '-r', '--name-only', '-z', sha) if sha else set()
    relevant = lambda p: subsystem(p) == unit
    # Vendor bodies are opt-in for a full audit. Always include their manifests and
    # every changed vendor file, and disclose excluded unchanged bodies.
    candidates = current | historical
    updates = changed(sha) if sha else changed('HEAD')
    excluded = {p for p in candidates if p.startswith(('third_party/', 'rust_backend/vendor/'))
                and Path(p).name not in ('Cargo.toml', 'Cargo.lock', 'pubspec.yaml', 'pubspec.lock')
                and p not in updates}
    selected = sorted(p for p in candidates - excluded if relevant(p))
    dirty = sorted(p for p in updates if relevant(p))
    state = 'stale' if sha and dirty else recorded
    # Historical "reviewed" is not proof of complete coverage: the path ledger must
    # close all chunks, and cross-subsystem changes may still invalidate a contract.
    return {'subsystem': unit, 'recorded_status': recorded, 'status': state,
            'reviewed_sha': sha, 'files': selected, 'changed': dirty,
            'deleted': [p for p in selected if not (ROOT / p).exists()],
            'excluded_vendor_bodies': len(excluded) if unit == 'build' else 0,
            'graph': graph_status(selected)}


def range_scope(revision, worktree):
    # Check return codes synchronously: invalid ranges must never become a clean PASS.
    selected = paths('diff', '--no-renames', '--name-only', '-z', revision, '--')
    if worktree:
        selected |= paths('ls-files', '--others', '--exclude-standard', '-z')
    files = sorted(p for p in selected if subsystem(p) != 'skip')
    roles = []
    risk = set().union(*(flags(p) for p in files))
    # Risk reviewers get seats before churn-based reviewers. Keep overflow visible.
    for role in ('security-auditor', 'api-compat-auditor'):
        if role in risk:
            roles.append(role)
    counts = {}
    for path in files:
        sub = subsystem(path)
        role = SUBSYSTEMS[sub][0] if sub in SUBSYSTEMS else 'docs-auditor'
        counts[role] = counts.get(role, 0) + 1
    # Preserve churn/test hints without Git's quoted-path or rename presentation.
    churn = 0
    test_lines = 0
    for row in git('diff', '--no-renames', '--numstat', '-z', revision, '--').split(b'\0'):
        if not row:
            continue
        add, delete, raw_path = row.split(b'\t', 2)
        path = raw_path.decode(errors='surrogateescape')
        amount = sum(int(n) for n in (add, delete) if n.isdigit())
        if subsystem(path) not in ('skip', 'docs'):
            churn += amount
            if subsystem(path) == 'tests':
                test_lines += amount
    if not worktree:
        subjects = git('log', '--format=%s', revision, '--').decode(errors='replace')
        if re.search(r'perf|optimi[sz]|speed ?up|faster|cache', subjects, re.I):
            counts['code-optimization-auditor'] = 0
    ordered = sorted(counts, key=lambda r: (-counts[r], r))
    all_roles = roles + [r for r in ordered if r not in roles]
    return {'range': revision, 'files': files, 'suggested_reviewers': all_roles[:3],
            'pending_reviewers': all_roles[3:], 'graph': graph_status(files),
            'split_required': len(all_roles) > 3 or len(files) > 25 or churn > 400,
            'changed_code_lines': churn,
            'NO_TEST_CHANGES': churn - test_lines > 100 and test_lines * 5 < churn,
            'note': 'Inspect hunks and risk; reviewer order uses file counts, not severity.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--worktree', action='store_true')
    group.add_argument('--subsystem', choices=SUBSYSTEMS)
    group.add_argument('--list-subsystems', action='store_true')
    group.add_argument('--coverage-status', action='store_true')
    parser.add_argument('--json', action='store_true', help='machine-readable inventory')
    parser.add_argument('revision', nargs='?')
    args = parser.parse_args()
    if args.revision and any((args.worktree, args.subsystem, args.list_subsystems, args.coverage_status)):
        parser.error('a revision cannot be combined with a scope mode')
    if args.list_subsystems:
        data = SUBSYSTEMS
    elif args.coverage_status:
        data = [inventory(unit) for unit in SUBSYSTEMS]
    elif args.subsystem:
        data = inventory(args.subsystem)
    else:
        revision = args.revision
        if not revision and not args.worktree:
            state = ROOT / 'reviews/STATE.md'
            match = re.search(r'^- Last reviewed commit: `([0-9a-f]+)`', state.read_text(), re.M) if state.exists() else None
            revision = match[1] + '..HEAD' if match else 'HEAD~1..HEAD'
        data = range_scope(revision or 'HEAD', args.worktree)
    # JSON is also the human report: quoted paths are unambiguous for whitespace,
    # tabs, newlines and Unicode; consumers never parse pretty Git rename strings.
    print(json.dumps(data, indent=2, ensure_ascii=True))
    if isinstance(data, dict) and 'range' in data and not data['files']:
        print('No reviewable changes.', file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(2)
