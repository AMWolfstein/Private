#!/usr/bin/env python3
"""Repo-local workflow tool: change records, gates, evidence and guards.

Standard library only; nothing to install. It records and checks evidence. It
does not review code, approve work or replace a person's decision.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PHASES = ('spec', 'plan', 'tasks', 'build', 'review', 'ship', 'done')
SIZES = ('feature', 'architecture')
CLOSED = {'fixed', 'contested', 'escalated', 'declined', 'false_positive', 'wontfix'}
STATUSES = CLOSED | {'open'}
SEVERITIES = {'blocker', 'major', 'nit'}
REVIEW_ROUND_CAP = 4
# Only progress/evidence records are excluded. Checks and policy affect evidence.
RECORD_DIRS = ('work/changes', '.work')
RECORD_PREFIXES = tuple(d + '/' for d in RECORD_DIRS)
TEST_DIRS = {'test', 'tests', 'integration_test', 'androidTest'}
TEST_SUFFIXES = ('_test.dart', 'Test.kt', 'Tests.kt', '_test.py', '_test.rs')


class Blocked(Exception):
    """A gate, guard or configuration problem the caller must resolve."""


class NoChecksSelected(Blocked):
    """Valid configuration, but no changed domain requests a check."""


# ---------------------------------------------------------------- utilities

def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(['git', *args], cwd=root, capture_output=True)
    if check and result.returncode != 0:
        raise Blocked(f'git {" ".join(args)} failed: {result.stderr.decode(errors="replace").strip()}')
    return result.stdout.decode('utf-8', errors='surrogateescape')


def is_record(path: str) -> bool:
    return path.startswith(RECORD_PREFIXES)


def is_test(path: str) -> bool:
    parts = path.split('/')
    return (any(part in TEST_DIRS for part in parts[:-1])
            or parts[-1].endswith(TEST_SUFFIXES) or parts[-1].startswith('test_'))


def fingerprint(root: Path) -> str:
    """Content id of the working tree: git's tree id after staging everything into a
    temporary index. Same content gives the same id before and after a commit; files
    ignored by .gitignore (generated output) and process records do not count.
    """
    index = Path(git(root, 'rev-parse', '--git-path', 'index').strip())
    index = index if index.is_absolute() else root / index
    with tempfile.TemporaryDirectory(prefix='work-fp-') as temp:
        temp_index = Path(temp) / 'index'
        if index.is_file():
            shutil.copy2(index, temp_index)  # reuse git's cached file hashes
        env = {**os.environ, 'GIT_INDEX_FILE': str(temp_index)}
        for argv in (['git', 'add', '--all', '--', '.'],
                     ['git', 'rm', '-r', '--cached', '-q', '--ignore-unmatch', '--', *RECORD_DIRS]):
            done = subprocess.run(argv, cwd=root, env=env, capture_output=True)
            if done.returncode != 0:
                raise Blocked(f'fingerprint failed: {done.stderr.decode(errors="replace").strip()}')
        return subprocess.run(['git', 'write-tree'], cwd=root, env=env, capture_output=True,
                              check=True).stdout.decode().strip()


def docs_fingerprint(folder: Path) -> str:
    digest = hashlib.sha256()
    for name in ('spec.md', 'plan.md'):
        path = folder / name
        digest.update(name.encode() + (path.read_bytes() if path.is_file() else b'<missing>'))
    return digest.hexdigest()


def changed_paths(root: Path, base: str = 'HEAD') -> list[str]:
    """Paths that differ from base, plus untracked files, excluding records."""
    tracked = git(root, 'diff', '--name-only', '-z', base).split('\0')
    untracked = git(root, 'ls-files', '-z', '--others', '--exclude-standard').split('\0')
    return sorted({p for p in tracked + untracked if p and not is_record(p)})


def load_config(root: Path) -> dict:
    path = root / 'work/checks.json'
    if not path.is_file():
        raise Blocked('work/checks.json is missing')
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


def domains_for(config: dict, paths: list[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in paths:
        for domain, patterns in config['domains'].items():
            if any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns):
                found.setdefault(domain, []).append(path)
    return found


def high_risk(config: dict, paths: list[str]) -> list[str]:
    return [p for p in paths if any(fnmatch.fnmatchcase(p, pat) for pat in config.get('high_risk', []))]


# ------------------------------------------------------------- change state

def changes_dir(root: Path) -> Path:
    return root / 'work/changes'


def find_change(root: Path, ident: str) -> Path:
    matches = [p for p in changes_dir(root).glob('*') if p.is_dir()
               and (p.name == ident or p.name.split('-', 1)[0] == ident.zfill(3))]
    if len(matches) != 1:
        raise Blocked(f'no single change matches "{ident}"')
    return matches[0]


def read_state(folder: Path) -> dict:
    return json.loads((folder / 'state.json').read_text())


def write_state(folder: Path, state: dict) -> None:
    (folder / 'state.json').write_text(json.dumps(state, indent=2, ensure_ascii=False) + '\n')


def slugify(title: str) -> str:
    slug = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
    return slug[:48].strip('-') or 'change'


def new_change(root: Path, title: str, size: str) -> Path:
    if size not in SIZES:
        raise Blocked(f'size must be one of {SIZES}')
    base = changes_dir(root)
    base.mkdir(parents=True, exist_ok=True)
    numbers = [int(p.name[:3]) for p in base.glob('[0-9][0-9][0-9]-*') if p.is_dir()]
    folder = base / f'{max(numbers, default=0) + 1:03d}-{slugify(title)}'
    folder.mkdir()
    templates = root / 'work/templates'
    for name in ('spec.md', 'plan.md', 'tasks.md', 'findings.md', 'log.md'):
        text = (templates / name).read_text().replace('{{TITLE}}', title).replace(
            '{{ID}}', folder.name).replace('{{DATE}}', now()[:10])
        (folder / name).write_text(text)
    base = git(root, 'rev-parse', 'HEAD', check=False).strip() or None
    write_state(folder, {'id': folder.name, 'title': title, 'size': size, 'phase': 'spec', 'base': base,
                         'created': now(), 'rounds': [], 'history': [{'phase': 'spec', 'at': now()}]})
    return folder


# ------------------------------------------------------------------ parsing

FINDING = re.compile(r'^### (F-\d+)\b(.*)$', re.M)


def parse_findings(text: str) -> list[dict]:
    items = []
    heads = list(FINDING.finditer(text))
    for index, head in enumerate(heads):
        end = heads[index + 1].start() if index + 1 < len(heads) else len(text)
        body = text[head.end():end]
        fields = dict((k.lower(), v.strip()) for k, v in re.findall(r'^- (\w+):[ \t]*(.*)$', body, re.M))
        items.append({'id': head.group(1), 'title': head.group(2).strip(), **fields})
    return items


def placeholders(text: str) -> list[str]:
    return re.findall(r'\[(?:FILL|NEEDS CLARIFICATION)[^\]]*\]', text)


def task_lines(text: str) -> list[tuple[bool, str]]:
    return [(mark.lower() == 'x', rest) for mark, rest in
            re.findall(r'^- \[( |x|X)\] (T\d{3}.*)$', text, re.M)]


def requirement_ids(text: str) -> set[str]:
    return set(re.findall(r'\bFR-\d{3}\b', text))


# ------------------------------------------------------------------- checks

def lint_change(root: Path, folder: Path, target: str | None = None) -> list[str]:
    """Cross-artifact problems; with target, only those that gate that phase."""
    state = read_state(folder)
    order = PHASES.index(target) if target else len(PHASES) - 1
    problems: list[str] = []
    read = lambda name: (folder / name).read_text() if (folder / name).is_file() else ''
    spec, plan, tasks, findings_text, log = (read(n) for n in
                                             ('spec.md', 'plan.md', 'tasks.md', 'findings.md', 'log.md'))
    if order >= PHASES.index('plan'):
        if placeholders(spec):
            problems.append(f'spec.md has unresolved markers: {", ".join(sorted(set(placeholders(spec))))}')
        if not requirement_ids(spec):
            problems.append('spec.md has no FR-### requirement')
        if not re.search(r'\bGiven\b.*\bWhen\b.*\bThen\b', spec, re.S | re.I):
            problems.append('spec.md has no Given/When/Then acceptance scenario')
    if order >= PHASES.index('tasks'):
        if placeholders(plan):
            problems.append('plan.md has unresolved [FILL] markers')
        gate = re.search(r'^## Constitution check\n(.*?)(?=^## |\Z)', plan, re.M | re.S)
        if gate and re.search(r'^- \[ \]', gate.group(1), re.M):
            problems.append('plan.md constitution check has unchecked items')
        if state['size'] == 'architecture':
            design = [r for r in state['rounds'] if r['stage'] == 'design']
            current = docs_fingerprint(folder)
            if len(design) < 2 or not all(r['result'] == 'clean' for r in design[-2:]):
                problems.append('architecture change needs two consecutive clean design-review rounds')
            elif design[-1]['fingerprint'] != current:
                problems.append('spec/plan changed after the last design review round')
    if order >= PHASES.index('build'):
        lines = task_lines(tasks)
        if not lines:
            problems.append('tasks.md has no T### tasks')
        if placeholders(tasks):
            problems.append('tasks.md has unresolved [FILL] markers')
        for _, rest in lines:
            if 'check:' not in rest:
                problems.append(f'task without "check:": {rest[:60]}')
        missing = requirement_ids(spec) - requirement_ids(tasks)
        if missing:
            problems.append(f'requirements with no task: {", ".join(sorted(missing))}')
    if order >= PHASES.index('review'):
        for done, rest in task_lines(tasks):
            if not done:
                problems.append(f'unfinished task: {rest[:60]}')
        problems += missing_evidence(root, state.get('base') or 'HEAD')
    if order >= PHASES.index('ship'):
        code = [r for r in state['rounds'] if r['stage'] == 'code']
        if not code or code[-1]['result'] != 'clean':
            problems.append('the last code-review round is missing or not clean')
        elif code[-1]['fingerprint'] != fingerprint(root):
            problems.append('code changed after the last clean review round; review the final code')
    for item in parse_findings(findings_text):
        status, severity = item.get('status', '').lower(), item.get('severity', '').lower()
        if status not in STATUSES or severity not in SEVERITIES:
            problems.append(f'{item["id"]}: needs Severity ({"/".join(sorted(SEVERITIES))}) '
                            f'and Status ({"/".join(sorted(STATUSES))})')
            continue
        if status in CLOSED and not item.get('evidence'):
            problems.append(f'{item["id"]} is {status} without Evidence (commit, test or file:line)')
        if order >= PHASES.index('ship') and status == 'open' and severity in ('blocker', 'major'):
            problems.append(f'{item["id"]} is an open {severity}')
        if order >= PHASES.index('ship') and status == 'escalated':
            problems.append(f'{item["id"]} waits for the owner (escalated)')
    if order >= PHASES.index('done'):
        close = log.split('## Close', 1)[-1] if '## Close' in log else ''
        for label in ('Drift:', 'Not verified:', 'Lessons:'):
            if not re.search(rf'^- {label}[ \t]*(?!\[FILL)\S', close, re.M):
                problems.append(f'log.md "## Close" needs a filled "- {label}" line')
    return problems


def advance(root: Path, ident: str, target: str) -> dict:
    folder = find_change(root, ident)
    state = read_state(folder)
    if target not in PHASES:
        raise Blocked(f'phase must be one of {PHASES}')
    current, wanted = PHASES.index(state['phase']), PHASES.index(target)
    if wanted > current + 1:
        raise Blocked(f'{state["phase"]} → {target} skips a phase; advance one phase at a time')
    if wanted > current:
        problems = lint_change(root, folder, target)
        if problems:
            raise Blocked('gate failed:\n  - ' + '\n  - '.join(problems))
    state['phase'] = target
    state['history'].append({'phase': target, 'at': now()})
    write_state(folder, state)
    return {'status': 'PASS', 'change': state['id'], 'phase': target}


def record_round(root: Path, ident: str, stage: str, result: str, reviewer: str) -> dict:
    if stage not in ('design', 'code') or result not in ('clean', 'dirty'):
        raise Blocked('usage: round <change> design|code clean|dirty --reviewer NAME')
    folder = find_change(root, ident)
    state = read_state(folder)
    rounds = [r for r in state['rounds'] if r['stage'] == stage]
    if len(rounds) >= REVIEW_ROUND_CAP and result == 'dirty':
        note = f'{stage} review reached {REVIEW_ROUND_CAP} rounds: report the open findings to the owner'
    else:
        note = ''
    fp = docs_fingerprint(folder) if stage == 'design' else fingerprint(root)
    state['rounds'].append({'stage': stage, 'round': len(rounds) + 1, 'result': result,
                            'reviewer': reviewer, 'fingerprint': fp, 'at': now()})
    write_state(folder, state)
    return {'status': 'PASS', 'round': len(rounds) + 1, 'note': note}


# ------------------------------------------------------------- run evidence

def runs_dir(root: Path) -> Path:
    return root / '.work/runs'


def latest_report(root: Path) -> dict | None:
    path = runs_dir(root) / 'latest.json'
    return json.loads(path.read_text()) if path.is_file() else None


def check_evidence(root: Path) -> dict:
    path = runs_dir(root) / 'by_check.json'
    return json.loads(path.read_text()) if path.is_file() else {}


def missing_evidence(root: Path, base: str) -> list[str]:
    """Checks the paths changed since base call for that lack a pass on the current tree."""
    try:
        config = load_config(root)
        required = select_checks(root, config, ['auto'], base)
    except NoChecksSelected:
        return []  # nothing in a checked domain changed
    evidence, current = check_evidence(root), fingerprint(root)
    problems = []
    for key in required:
        entry = evidence.get(key)
        if not entry or entry['status'] != 'PASS':
            problems.append(f'no passing "{key}" evidence (run: work.py check auto)')
        elif entry['fingerprint'] != current:
            problems.append(f'"{key}" evidence is stale: code changed after it passed')
    return problems


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

def worktree_changes(root: Path) -> list[tuple[str, str]]:
    """(status, path) for every changed or untracked path, renames split into both sides."""
    out = git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all').split('\0')
    items, index = [], 0
    while index < len(out):
        entry = out[index]
        index += 1
        if not entry:
            continue
        status, path = entry[:2], entry[3:]
        items.append((status, path))
        if 'R' in status or 'C' in status:
            items.append(('D ', out[index]))  # rename source must come back too
            index += 1
    return items


def prove(root: Path, command: list[str], timeout: int,
          expected_failure: str | None = None) -> dict:
    """Run proof in a disposable worktree; never revert the owner's files."""
    before = fingerprint(root)
    with tempfile.TemporaryDirectory(prefix='work-proof-') as temporary:
        isolated = Path(temporary) / 'tree'
        git(root, 'worktree', 'add', '--detach', str(isolated), 'HEAD')
        try:
            paths = git(root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0')
            for path in filter(None, paths):
                if is_record(path):
                    continue
                source, target = root / path, isolated / path
                if target.is_symlink() or target.is_file():
                    target.unlink()
                if source.is_symlink() or source.is_file():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target, follow_symlinks=False)
            # Ignored dependencies/build caches are deliberately not copied.
            result = _prove_in_worktree(isolated, command, timeout, expected_failure)
            proofs = isolated / '.work/proofs'
            if proofs.exists():
                shutil.copytree(proofs, root / '.work/proofs', dirs_exist_ok=True)
            if fingerprint(root) != before:
                result['status'] = 'INCONCLUSIVE'
                result['meaning'] = 'source tree changed while proof was running; rerun on stable inputs'
            result['isolation'] = 'disposable Git worktree; ignored dependencies are not copied'
            return result
        finally:
            git(root, 'worktree', 'remove', '--force', str(isolated))


def _prove_in_worktree(root: Path, command: list[str], timeout: int,
          expected_failure: str | None = None) -> dict:
    """Green/red/green command evidence with an explicit regression signature.

    Changes are restored even on errors/Ctrl-C. The signature is a literal assertion
    diagnostic selected by the caller, not automatic proof of semantic causality.
    """
    if not command:
        raise Blocked('usage: prove --expect-failure <assertion text> -- <test command>')
    domains = {d: pats for d, pats in load_config(root)['domains'].items() if d != 'workflow'}

    def is_code(path: str) -> bool:
        if path.startswith('scripts/work/'):
            return False
        return any(fnmatch.fnmatchcase(path, pat) for pats in domains.values() for pat in pats)

    targets = sorted({p for _, p in worktree_changes(root)
                      if not is_test(p) and not is_record(p) and is_code(p)})
    if not targets:
        raise Blocked('no non-test code change to revert; prove needs a fix in the working tree')
    directory = root / '.work/proofs' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    directory.mkdir(parents=True)
    before = fingerprint(root)
    phases = {}

    def execute(phase):
        log = directory / (phase + '.log')
        result = run_one(command, root, log, timeout, None)
        result['log'] = log.relative_to(root).as_posix()
        phases[phase] = result
        return result, log.read_text(errors='replace')

    def report(status, meaning, reverted, output=''):
        result = {'status': status, 'meaning': meaning, 'reverted': reverted,
                  'command': command, 'expected_failure': expected_failure,
                  'fingerprint': before, 'phases': phases,
                  'output_tail': output[-4000:],
                  'scope': 'Command transitions and literal diagnostic only; inspect failure cause.'}
        (directory / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
        return result

    baseline, output = execute('with_fix')
    if baseline['status'] != 'PASS':
        return report('INCONCLUSIVE', 'the command must pass with the fix before testing the old code', [], output)
    if fingerprint(root) != before:
        return report('INCONCLUSIVE', 'the baseline command changed tracked or untracked inputs', [], output)
    if not expected_failure or not expected_failure.strip():
        return report('INCONCLUSIVE', 'provide --expect-failure with the specific regression assertion diagnostic', [])
    if expected_failure in output:
        return report('INCONCLUSIVE', 'failure diagnostic also appears in the passing run; choose a specific assertion', [], output)

    backup = Path(tempfile.mkdtemp(prefix='work-prove-'))
    saved: list[tuple[str, bool]] = []

    def interrupted(*_):
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        for path in targets:
            full = root / path
            exists = full.exists() or full.is_symlink()
            if exists:
                (backup / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(full, backup / path, follow_symlinks=False)
            saved.append((path, exists))
            head = subprocess.run(['git', 'show', f'HEAD:{path}'], cwd=root, capture_output=True)
            if head.returncode == 0:
                # Never follow a changed symlink while writing the temporary old file.
                if full.is_symlink():
                    full.unlink()
                full.parent.mkdir(parents=True, exist_ok=True)
                full.write_bytes(head.stdout)
            elif exists:
                full.unlink()
        negative, output = execute('without_fix')
    finally:
        for path, existed in saved:
            full = root / path
            if full.is_symlink():
                full.unlink()
            if existed:
                full.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(backup / path, full, follow_symlinks=False)
            elif full.exists():
                full.unlink()
        signal.signal(signal.SIGTERM, previous)
        shutil.rmtree(backup, ignore_errors=True)

    if fingerprint(root) != before:
        return report('INCONCLUSIVE', 'inputs changed during the negative run; inspect the tree', targets, output)
    restored, restored_output = execute('restored_fix')
    if restored['status'] != 'PASS' or fingerprint(root) != before:
        return report('INCONCLUSIVE', 'the restored fix did not pass unchanged', targets, restored_output)
    if expected_failure in restored_output:
        return report('INCONCLUSIVE', 'failure diagnostic appears in the restored passing run', targets, restored_output)
    if negative['status'] == 'PASS':
        return report('FAIL', 'the same command also passes without the fix', targets, output)
    if (negative['status'] != 'FAIL' or (negative.get('exit_code') or 0) <= 0
            or expected_failure not in output):
        return report('INCONCLUSIVE', 'old-code failure was not the expected regression assertion', targets, output)
    return report('PASS', 'the same command passed with/restored fix and failed without it with the expected diagnostic; review the logs to confirm the cause', targets, output)


# ------------------------------------------------------------------- packet

def packet(root: Path, base: str, goal_file: str | None, ident: str | None, out: str) -> dict:
    parts = ['# Review packet', '',
             'Read this packet and the repository. You have no conversation history; '
             'do not assume anything the packet or the code does not show.', '']
    if ident:
        folder = find_change(root, ident)
        for name in ('spec.md', 'plan.md'):
            if (folder / name).is_file():
                parts += [f'## {name} ({folder.name})', '', (folder / name).read_text(), '']
    if goal_file:
        parts += ['## Goal', '', (root / goal_file).read_text(), '']
    paths = changed_paths(root, base)
    parts += [f'## Changed files (against {base})', ''] + [f'- {p}' for p in paths] + ['']
    diff = git(root, 'diff', base, '--', *paths, check=False) if paths else ''
    parts += ['## Diff', '', '```diff', diff.rstrip(), '```', '']
    untracked = git(root, 'ls-files', '--others', '--exclude-standard', '--', *paths).split('\n') if paths else []
    for path in filter(None, untracked):
        parts += [f'## New file {path}', '', '```', (root / path).read_text(errors='replace'), '```', '']
    report = latest_report(root)
    if report:
        fresh = report['fingerprint'] == fingerprint(root)
        parts += ['## Latest checks', '',
                  f'Status {report["status"]}, {"fresh" if fresh else "STALE"}, tests {report["tests"]}', '']
    target = root / out
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(parts))
    return {'status': 'PASS', 'packet': out, 'files': len(paths)}


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
            return 2, f'Blocked by work/hooks: {reason}'
    return 0, ''


def status(root: Path, brief: bool) -> str:
    lines = []
    active = []
    if changes_dir(root).is_dir():
        for folder in sorted(changes_dir(root).iterdir()):
            if (folder / 'state.json').is_file():
                state = read_state(folder)
                if state['phase'] != 'done':
                    active.append(state)
    if active:
        for state in active:
            problems = lint_change(root, find_change(root, state['id']))
            lines.append(f'Change {state["id"]} ({state["size"]}): phase {state["phase"]}'
                         f'{"; " + str(len(problems)) + " open issue(s), run work.py lint" if problems else ""}')
    else:
        lines.append('No active change record. Small fixes need none.')
    report = latest_report(root)
    if report:
        fresh = report['fingerprint'] == fingerprint(root)
        lines.append(f'Last checks: {report["status"]} at {report["at"]} '
                     f'({"matches the tree" if fresh else "stale: code changed since"})')
    changed = changed_paths(root)
    if changed:
        lines.append(f'Uncommitted code paths: {len(changed)}')
    if not brief:
        lines.append('Workflow: .claude/skills/work/SKILL.md. Constitution: work/constitution.md.')
    return '\n'.join(lines)


# ---------------------------------------------------------------------- cli

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path)
    sub = parser.add_subparsers(dest='action', required=True)
    s = sub.add_parser('status'); s.add_argument('--brief', action='store_true')
    sub.add_parser('remind')
    s = sub.add_parser('new'); s.add_argument('title'); s.add_argument('--size', default='feature')
    s = sub.add_parser('advance'); s.add_argument('change'); s.add_argument('phase')
    s = sub.add_parser('lint'); s.add_argument('change', nargs='?')
    s = sub.add_parser('round'); s.add_argument('change'); s.add_argument('stage'); s.add_argument('result')
    s.add_argument('--reviewer', required=True)
    s = sub.add_parser('scope'); s.add_argument('--base', default='HEAD')
    s = sub.add_parser('check'); s.add_argument('names', nargs='+'); s.add_argument('--base', default='HEAD')
    sub.add_parser('fresh')
    s = sub.add_parser('prove'); s.add_argument('--timeout', type=int, default=900)
    s.add_argument('--expect-failure', help='literal regression assertion diagnostic, not a test name or compiler error')
    s.add_argument('cmd', nargs=argparse.REMAINDER)
    s = sub.add_parser('packet'); s.add_argument('--base', default='HEAD'); s.add_argument('--goal')
    s.add_argument('--change'); s.add_argument('--out', default='.work/review/packet.md')
    sub.add_parser('hook-bash')
    args = parser.parse_args(argv)
    if args.action == 'hook-bash':
        code, message = hook_bash(sys.stdin.read())
        if message:
            print(message, file=sys.stderr)
        return code
    try:
        root = (args.root or Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').strip())).resolve()
        if args.action == 'hook-bash':
            code, message = hook_bash(sys.stdin.read())
            if message:
                print(message, file=sys.stderr)
            return code
        if args.action in ('status', 'remind'):
            text = status(root, True)
            if args.action == 'remind':
                text = 'Workflow active (work skill, constitution). ' + text.replace('\n', ' | ')
            print(text)
            return 0
        if args.action == 'new':
            result = {'status': 'PASS', 'folder': new_change(root, args.title, args.size).relative_to(root).as_posix()}
        elif args.action == 'advance':
            result = advance(root, args.change, args.phase)
        elif args.action == 'lint':
            folders = [find_change(root, args.change)] if args.change else [
                p for p in sorted(changes_dir(root).glob('*')) if (p / 'state.json').is_file()
                and read_state(p)['phase'] != 'done']
            problems = {f.name: lint_change(root, f) for f in folders}
            result = {'status': 'PASS' if not any(problems.values()) else 'ISSUES', 'problems': problems}
        elif args.action == 'round':
            result = record_round(root, args.change, args.stage, args.result, args.reviewer)
        elif args.action == 'scope':
            config = load_config(root)
            paths = changed_paths(root, args.base)
            found = domains_for(config, paths)
            checks = sorted({c for d in found for c in config['domain_checks'].get(d, [])},
                            key=list(config['checks']).index)
            result = {'status': 'PASS', 'changed': len(paths), 'domains': {d: len(p) for d, p in found.items()},
                      'high_risk': high_risk(config, paths), 'checks': checks,
                      'tests_changed': [p for p in paths if is_test(p)]}
        elif args.action == 'check':
            config = load_config(root)
            result = run_checks(root, config, select_checks(root, config, args.names, args.base))
        elif args.action == 'fresh':
            report = latest_report(root)
            ok = bool(report) and report['status'] == 'PASS' and report['fingerprint'] == fingerprint(root)
            result = {'status': 'PASS' if ok else 'STALE_OR_INCOMPLETE'}
        elif args.action == 'prove':
            command = args.cmd[1:] if args.cmd[:1] == ['--'] else args.cmd
            result = prove(root, command, args.timeout, expected_failure=args.expect_failure)
        else:
            result = packet(root, args.base, args.goal, args.change, args.out)
    except (Blocked, OSError, KeyError, ValueError) as error:
        print(json.dumps({'status': 'BLOCKED', 'reason': str(error)}, ensure_ascii=False, indent=2))
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get('status') == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
