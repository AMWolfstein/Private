#!/usr/bin/env python3
"""Local workflow evidence, not an AI reviewer or an application approval gate."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
from datetime import datetime, timezone

# Excluded anywhere: generated/tool directories only. Source, docs, config,
# lockfiles and untracked fixtures are included. Symlink targets are fingerprinted
# as text; external targets are not read and need separate provenance.
EXCLUDED = {'.git', '.workflow-runs', '__pycache__', '.dart_tool', '.gradle',
            'build', '.kotlin', '.venv', 'node_modules'}
SKILLS = ('workflow', 'spec', 'design', 'implement', 'port', 'review', 'verify')


def fingerprint(root):
    digest = hashlib.sha256()
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED)
        links = [d for d in dirs if (Path(directory) / d).is_symlink()]
        for name in sorted(files + links):
            path = Path(directory) / name
            if path.suffix == '.pyc':
                continue
            relative = path.relative_to(root).as_posix().encode()
            content = (b'link:' + os.readlink(path).encode() if path.is_symlink()
                       else b'file:' + path.read_bytes())
            digest.update(len(relative).to_bytes(8, 'big') + relative)
            digest.update(hashlib.sha256(content).digest())
    return digest.hexdigest()


def local_path(root, value):
    path = (root / value).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f'Path escapes project root: {value}')
    return path


def load_config(root):
    config = json.loads((root / 'workflow/verification.json').read_text())
    checks = config['checks']
    for key, item in checks.items():
        command = item['command']
        if not isinstance(command, list) or any(not isinstance(v, str) for v in command):
            raise ValueError(f'{key}: command must be an argv list')
        if not isinstance(item['timeout_seconds'], int) or item['timeout_seconds'] <= 0:
            raise ValueError(f'{key}: timeout must be a positive integer')
        local_path(root, item['cwd'])
        for prerequisite in item['requires']:
            local_path(root, prerequisite)
    for profile, ids in config['profiles'].items():
        if not ids or any(key not in checks for key in ids):
            raise ValueError(f'Invalid/empty profile: {profile}')
    return config


def route(intent, paths):
    text = (intent + ' ' + ' '.join(paths)).lower()
    action = intent.strip().lower()
    domains = set()
    if any(p.endswith('.dart') for p in paths): domains.add('flutter')
    if any(p.endswith(('.kt', '.kts')) or p.startswith('android/') for p in paths):
        domains.add('android')
    if any(w in text for w in ('bridge', 'channel', 'قناة', 'بريدج')):
        domains.update(('bridge', 'flutter', 'android'))
    if any(w in text for w in ('backup', 'sqlite', 'database', 'metadata', 'tag', 'بيانات')):
        domains.add('data')
    if any(w in text for w in ('playback', 'audio', 'media3', 'exoplayer', 'تشغيل', 'صوت')):
        domains.add('playback')
    mode = 'feature'
    # An explicit review request stays read-only even when its subject is a port.
    # File names inform domains, not permission to change the requested action.
    if re.match(r'(?:please\s+)?(?:review|audit)\b', action) or action.startswith(('راجع', 'مراجعة', 'افحص')):
        mode = 'audit'
    elif re.search(r'\b(?:port|porting|migrat\w*)\b', action) or any(w in action for w in ('بورت', 'انقل', 'نقل')):
        mode = 'migration'
    elif any(w in action for w in ('architect', 'تصميم', 'معمار')):
        mode = 'architecture'
    elif re.search(r'\b(?:fix|debug|repair)\b', action) or any(w in action for w in ('صلح', 'إصلاح', 'اصلح')):
        mode = 'fix'
    elif re.search(r'\b(?:review|audit)\b', action) or any(w in action for w in ('راجع', 'مراجعة')):
        mode = 'audit'
    skills = {
        'feature': ['spec', 'implement', 'review', 'verify'],
        'architecture': ['spec', 'design', 'implement', 'review', 'verify'],
        'migration': ['spec', 'design', 'port', 'review', 'verify'],
        'fix': ['implement', 'review', 'verify'],
        'audit': ['review'],
    }
    return {'mode': mode, 'domains': sorted(domains), 'advisory_only': True,
            'suggested_skills': ['sistrum-' + name for name in skills[mode]],
            'note': 'Trace callers and select explicit profiles. Skills are suggestions, not an execution order; simplify trivial work. Routing never proves scope or executes commands.'}


def validate(root):
    load_config(root)
    for name in SKILLS:
        path = root / f'.agents/skills/sistrum-{name}/SKILL.md'
        text = path.read_text()
        if not text.startswith('---\n') or f'name: sistrum-{name}\n' not in text or 'description:' not in text:
            raise ValueError(f'Invalid skill header: {path}')
    for name in ('AGENTS.md', 'workflow/STATE.md', 'workflow/architecture.md',
                 'workflow/quality.md', 'workflow/migration.md',
                 'workflow/spec-driven.md', 'workflow/templates/spec.md',
                 'workflow/templates/task.md', 'workflow/templates/design.md',
                 'workflow/contracts/playback-bridge.md',
                 'workflow/contracts/data-compatibility.md'):
        if not (root / name).is_file(): raise ValueError(f'Missing {name}')
    return {'status': 'PASS', 'scope': 'package structure and check configuration only'}


def run_checks(root, config, profile):
    before = fingerprint(root)
    directory = root / '.workflow-runs' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    directory.mkdir(parents=True)
    results = []
    for key in config['profiles'][profile]:
        check = config['checks'][key]
        item = {'id': key, 'command': check['command'], 'cwd': check['cwd'],
                'status': 'BLOCKED', 'exit_code': None}
        results.append(item)
        missing = [p for p in check['requires'] if not local_path(root, p).exists()]
        if missing or not check['command']:
            item['reason'] = f'Missing prerequisites: {missing}' if missing else 'Command not configured'
            continue
        cwd = local_path(root, check['cwd'])
        if not cwd.is_dir():
            item['reason'] = 'Working directory missing'
            continue
        command = [sys.executable if value == '{python}' else value for value in check['command']]
        log = directory / f'{len(results):02d}.log'
        item['log'] = log.relative_to(root).as_posix()
        try:
            with log.open('wb') as output:
                process = subprocess.Popen(command, cwd=cwd, stdout=output,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    item['exit_code'] = process.wait(timeout=check['timeout_seconds'])
                    item['status'] = 'PASS' if item['exit_code'] == 0 else 'FAIL'
                except subprocess.TimeoutExpired:
                    # POSIX toolchain: stop descendants, not just the wrapper.
                    try: os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                    process.wait()
                    item['status'] = 'TIMEOUT'
        except OSError as error:
            item['reason'] = str(error)
    after = fingerprint(root)
    report = {'schema': 1, 'profile': profile, 'checks': results,
              'started_fingerprint': before, 'finished_fingerprint': after,
              'source_changed_during_run': before != after,
              'status': 'PASS' if before == after and all(r['status'] == 'PASS' for r in results) else 'INCOMPLETE',
              'timestamp': datetime.now(timezone.utc).isoformat(),
              'scope': 'Configured command exits only; task/review/device gates are separate.'}
    encoded = json.dumps(report, indent=2) + '\n'
    (directory / 'report.json').write_text(encoded)
    (root / '.workflow-runs/latest.json').write_text(encoded)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('validate')
    routing = sub.add_parser('route')
    routing.add_argument('--intent', required=True)
    routing.add_argument('--paths', nargs='*', default=[])
    for name in ('plan', 'run'):
        cmd = sub.add_parser(name)
        cmd.add_argument('--profile', required=True)
    fresh = sub.add_parser('fresh')
    fresh.add_argument('report')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        if args.action == 'route': result = route(args.intent, args.paths)
        elif args.action == 'validate': result = validate(root)
        elif args.action == 'fresh':
            report = json.loads(local_path(root, args.report).read_text())
            passed = (report['status'] == 'PASS' and not report['source_changed_during_run']
                      and report['finished_fingerprint'] == fingerprint(root))
            result = {'status': 'PASS' if passed else 'STALE_OR_INCOMPLETE',
                      'scope': 'Freshness of recorded command evidence only'}
        else:
            config = load_config(root)
            if args.profile not in config['profiles']: raise ValueError('Unknown profile')
            result = (run_checks(root, config, args.profile) if args.action == 'run' else
                      {'profile': args.profile, 'checks':
                       [dict(id=key, **config['checks'][key]) for key in config['profiles'][args.profile]]})
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if result.get('status', 'PASS') == 'PASS' else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({'status': 'BLOCKED', 'reason': str(error)}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
