#!/usr/bin/env python3
"""Repo-local workflow tool: change records, gates, evidence and guards.

Standard library only; nothing to install. It records and checks evidence. It
does not review code, approve work or replace a person's decision.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import workflow_env
import workmap  # noqa: E402  (map and context retrieval)
from worklib import Blocked, domains_for, git, now, snapshot  # noqa: E402,F401

PHASES = ('spec', 'plan', 'tasks', 'build', 'review', 'ship', 'done')
SIZES = ('feature', 'architecture')
CLOSED = {'fixed', 'contested', 'escalated', 'declined', 'false_positive', 'wontfix'}
STATUSES = CLOSED | {'open'}
SEVERITIES = {'blocker', 'major', 'nit'}
REVIEW_ROUND_CAP = 4
# Only progress/evidence records are excluded. Checks and policy affect evidence.
RECORD_DIRS = ('workflow/work/changes', '.work')
RECORD_PREFIXES = tuple(d + '/' for d in RECORD_DIRS)


class NoChecksSelected(Blocked):
    """Valid configuration, but no changed domain requests a check."""


# ---------------------------------------------------------------- utilities



def is_record(path: str) -> bool:
    return path.startswith(RECORD_PREFIXES)


def changed_paths(root: Path, base: str = 'HEAD') -> list[str]:
    """Paths that differ from base, plus untracked files, excluding records."""
    tracked = git(root, 'diff', '--name-only', '-z', base).split('\0')
    untracked = git(root, 'ls-files', '-z', '--others', '--exclude-standard').split('\0')
    return sorted({p for p in tracked + untracked if p and not is_record(p)})


def check_evidence(root: Path) -> dict:
    path = runs_dir(root) / 'by_check.json'
    return json.loads(path.read_text()) if path.is_file() else {}


def fingerprint(root: Path) -> str:
    """Content id of the working tree: git's tree id after staging everything into a
    temporary index. Same content gives the same id before and after a commit; files
    ignored by .gitignore (generated output) and process records do not count.
    """
    return snapshot(root, drop=RECORD_DIRS)[0]






def load_config(root: Path) -> dict:
    path = root / 'workflow/work/checks.json'
    if not path.is_file():
        raise Blocked('workflow/work/checks.json is missing')
    config = json.loads(path.read_text())
    for key, check in config['checks'].items():
        if not isinstance(check.get('run'), list) or not all(isinstance(v, str) for v in check['run']):
            raise Blocked(f'check {key}: "run" must be an argv list')
        if not isinstance(check.get('requires', []), list):
            raise Blocked(f'check {key}: "requires" must be a list of paths')
        for number in ('timeout', 'stall'):
            if number in check and (not isinstance(check[number], int) or check[number] <= 0):
                raise Blocked(f'check {key}: "{number}" must be a positive integer')
    for domain, checks in config['domain_checks'].items():
        for key in checks:
            if key not in config['checks']:
                raise Blocked(f'domain {domain} names unknown check {key}')
    return config




# ------------------------------------------------------------- change state













# ------------------------------------------------------------------ parsing

FINDING = re.compile(r'^### (F-\d+)\b(.*)$', re.M)










# ------------------------------------------------------------------- checks











# ------------------------------------------------------------- run evidence

def runs_dir(root: Path) -> Path:
    return root / '.work/runs'








def test_targets(root: Path, folder: str) -> list[str]:
    """Top-level test folders/files that contain tests; helper-only folders are skipped."""
    base = root / folder
    targets = []
    for entry in sorted(base.iterdir()):
        if entry.is_dir() and any(entry.rglob('*_test.dart')):
            targets.append(f'{folder}/{entry.name}')
        elif entry.is_file() and entry.name.endswith('_test.dart'):
            targets.append(f'{folder}/{entry.name}')
    return targets


COUNT = re.compile(rb'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: ')


def run_one(argv: list[str], cwd: Path, log: Path, timeout: int, stall: int | None) -> dict:
    """Run a command; kill its process group on timeout or when output stops for `stall` s."""
    started = time.monotonic()
    with log.open('wb') as output:
        try:
            process = subprocess.Popen(argv, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                       stdin=subprocess.DEVNULL, start_new_session=True)
        except OSError as error:
            return {'status': 'BLOCKED', 'reason': str(error)}
        last_size, last_change, status = 0, started, None
        while process.poll() is None:
            time.sleep(0.2)
            size = log.stat().st_size
            if size != last_size:
                last_size, last_change = size, time.monotonic()
            if time.monotonic() - started > timeout:
                status = 'TIMEOUT'
            elif stall and time.monotonic() - last_change > stall:
                status = 'STALLED'
            if status:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                break
    item = {'status': status or ('PASS' if process.returncode == 0 else 'FAIL'),
            'exit_code': None if status else process.returncode,
            'seconds': round(time.monotonic() - started, 1)}
    data = log.read_bytes()
    counts = COUNT.findall(data)
    if counts:
        passed, skipped, failed = counts[-1]
        item['tests'] = {'passed': int(passed), 'skipped': int(skipped or 0), 'failed': int(failed or 0)}
    else:
        summaries = re.findall(rb'^Ran (\d+) tests? in [^\n]+\n\s*\n(OK(?: \([^\n]*\))?|FAILED \([^\n]*\))', data, re.M)
        if summaries:
            total, outcome = summaries[-1]
            def count(name):
                found = re.search(name + rb'=(\d+)', outcome)
                return int(found.group(1)) if found else 0
            skipped = count(b'skipped')
            failed = count(b'failures') + count(b'errors') + count(b'unexpected successes')
            item['tests'] = {'passed': max(0, int(total) - skipped - failed),
                             'skipped': skipped, 'failed': failed}
    return item


def run_checks(root: Path, config: dict, keys: list[str]) -> dict:
    before = fingerprint(root)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    directory = runs_dir(root) / stamp
    directory.mkdir(parents=True)
    results = []
    for key in keys:
        check = config['checks'][key]
        missing = [p for p in check.get('requires', []) if not (root / p).exists()]
        if missing:
            results.append({'id': key, 'status': 'BLOCKED', 'reason': f'missing {missing}'})
            continue
        argv = [sys.executable if v == '{python}' else v for v in check['run']]
        timeout, stall = check.get('timeout', 1800), check.get('stall')
        targets = test_targets(root, check['split']) if check.get('split') else [None]
        for target in targets:
            label = key if target is None else f'{key}:{target}'
            log = directory / f'{len(results):02d}-{re.sub(r"[^A-Za-z0-9.]+", "_", label)}.log'
            command = argv + ([target] if target else [])
            item = run_one(command, root, log, timeout, stall)
            if item['status'] == 'STALLED':
                # A stalled runner is retried once; a second stall is reported, never passed.
                item = run_one(command, root, log, timeout, stall)
                item['retried_after_stall'] = True
            results.append({'id': label, 'command': command, 'log': log.relative_to(root).as_posix(), **item})
    after = fingerprint(root)
    totals = {'passed': 0, 'skipped': 0, 'failed': 0}
    for item in results:
        for name in totals:
            totals[name] += item.get('tests', {}).get(name, 0)
    status = 'PASS' if results and before == after and all(r['status'] == 'PASS' for r in results) else 'INCOMPLETE'
    report = {'schema': 1, 'checks': results, 'tests': totals, 'fingerprint': after,
              'source_changed_during_run': before != after, 'status': status, 'at': now(),
              'scope': 'Command exits only. Not review, not device verification.'}
    try:  # a finished check run ends an edit batch: bring the code map up to date as well
        refreshed = workmap.update(root)
        report['map'] = {'state': 'current', 'rebuilt': refreshed['rebuilt'],
                         'structure': (refreshed.get('structure') or {}).get('status')}
    except Blocked as error:
        report['map'] = {'state': 'not current', 'error': str(error)[:500]}
    encoded = json.dumps(report, indent=2) + '\n'
    (directory / 'report.json').write_text(encoded)
    (runs_dir(root) / 'latest.json').write_text(encoded)
    evidence = check_evidence(root)
    for key in keys:
        items = [r for r in results if r['id'] == key or r['id'].startswith(key + ':')]
        passed = bool(items) and before == after and all(r['status'] == 'PASS' for r in items)
        evidence[key] = {'status': 'PASS' if passed else 'INCOMPLETE', 'fingerprint': after,
                         'at': report['at'], 'run': stamp}
    (runs_dir(root) / 'by_check.json').write_text(json.dumps(evidence, indent=2) + '\n')
    return report


def select_checks(root: Path, config: dict, names: list[str], base: str) -> list[str]:
    keys: list[str] = []
    for name in names:
        if name == 'auto':
            found = domains_for(config, changed_paths(root, base))
            for domain in config['domain_checks']:
                if domain in found:
                    keys += config['domain_checks'][domain]
        elif name in config['checks']:
            keys.append(name)
        else:
            raise Blocked(f'unknown check "{name}"; known: {", ".join(config["checks"])}, auto')
    ordered = [k for k in config['checks'] if k in keys]  # config order keeps Flutter and Gradle serial
    if not ordered:
        raise NoChecksSelected('no check selected: nothing changed in a configured domain')
    return ordered


# -------------------------------------------------------------------- prove







# ------------------------------------------------------------------- packet



# -------------------------------------------------------------------- hooks

GUARDS = [
    (r'\bgit\s+add\s+(?:[^|;&]*\s)?(?:-A|--all|\.)(?=\s|$)',
     'Stage explicit paths. git add -A / . also stages generated files.'),
    (r'\bgit\s+push\b[^|;&]*\s(?:-f|--force(?:-with-lease)?(?=[\s=]|$)|\+\S)',
     'Force push is not allowed from the agent; ask the owner.'),
    (r'--no-verify\b', 'Do not skip git hooks.'),
    (r'\bgit\s+(?:reset\s+--hard|clean\s+-\w*f|checkout\s+--\s+\.|restore\s+(?:--\S+\s+)*\.(?=\s|$))',
     'This discards work in the tree; ask the owner first.'),
    (r'\bpkill\s+(?:-\w*\s+)*(?:-f|--full)\b',
     'pkill -f matches this shell\'s own command line and kills it. '
     'Find PIDs with ps and kill them by number.'),
]


def hook_bash(stdin: str) -> tuple[int, str]:
    try:
        command = json.loads(stdin).get('tool_input', {}).get('command', '')
    except json.JSONDecodeError:
        return 0, ''
    for pattern, reason in GUARDS:
        if re.search(pattern, command):
            return 2, f'Blocked by workflow/work/hooks: {reason}'
    return 0, ''




# ---------------------------------------------------------------------- cli

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('hook-bash')
    s = sub.add_parser('setup', help='provision Linux project-local Python and CodeGraph tools')
    s.add_argument('--offline', action='store_true', help='validate/reuse only; never download')
    sub.add_parser('doctor', help='read-only tool/version/parser diagnostics')
    s = sub.add_parser('check', help='run the checks for the change, or named checks')
    s.add_argument('names', nargs='+'); s.add_argument('--base', default='HEAD')
    s = sub.add_parser('map', help='code map: build (full), update (incremental), status')
    s.add_argument('op', choices=('build', 'update', 'status', 'coverage'))
    s = sub.add_parser('context', help='bounded context packet for a task from the code map')
    s.add_argument('task', nargs='?', default='')
    s.add_argument('--file', action='append', default=[], help='entry file (repeatable)')
    s.add_argument('--symbol', action='append', default=[], help='entry symbol name (repeatable)')
    s.add_argument('--budget', type=int, help='approximate token budget (characters / 4)')
    s.add_argument('--depth', type=int, choices=(1, 2), default=1, help='2 adds bridges of import neighbours')
    s.add_argument('--expand', help='file:<path>, symbol:<name>, bridge:<channel> or module:<id>')
    s.add_argument('--no-refresh', action='store_true', help='use the published map even when it is stale')
    s.add_argument('--json', action='store_true', help='print the structured data instead of the packet')
    args = parser.parse_args(argv)
    if args.action == 'hook-bash':
        code, message = hook_bash(sys.stdin.read())
        if message:
            print(message, file=sys.stderr)
        return code
    try:
        root = (args.root or Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').strip())).resolve()
        if __name__ == '__main__' and args.action not in ('setup', 'doctor'):
            workflow_env.reexec(root)
        if args.action == 'setup':
            result = workflow_env.setup(root, args.offline)
        elif args.action == 'doctor':
            result = workflow_env.doctor(root)
        elif args.action == 'check':
            config = load_config(root)
            result = run_checks(root, config, select_checks(root, config, args.names, args.base))
        elif args.action == 'map':
            if args.op == 'coverage':
                result = workmap.coverage_report(root)
            elif args.op == 'status':
                status_now = workmap.map_status(root)
                result = {'status': 'PASS' if status_now['state'] == 'current' else status_now['state'].upper(),
                          **status_now}
            else:
                result = workmap.update(root, force=args.op == 'build')
        else:
            if not (args.task or args.file or args.symbol or args.expand):
                raise Blocked('usage: context "<task>" [--file PATH] [--symbol NAME] [--expand HANDLE]')
            packet_now = workmap.context(root, args.task, args.file, args.symbol, args.budget, args.depth,
                                         args.expand, refresh=not args.no_refresh)
            if args.json:
                print(json.dumps(packet_now['data'], indent=2, ensure_ascii=False))
            else:
                print(packet_now['text'], end='')
            return 0
    except (Blocked, OSError, KeyError, ValueError) as error:
        print(json.dumps({'status': 'BLOCKED', 'reason': str(error)}, ensure_ascii=False, indent=2))
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get('status') == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
