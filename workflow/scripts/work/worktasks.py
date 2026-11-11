"""Reviewed task execution. Checks/review are evidence, never semantic proof.

The CLI supplies the existing runner/map API. No application dependency or shell
evaluation is introduced. Progress is excluded from code fingerprints; task
requirements have a separate identity so editing records cannot reuse checks.
"""
from __future__ import annotations

import hashlib
import json
import re
import uuid
from pathlib import Path
from types import SimpleNamespace

from worklib import Blocked, atomic_write, committed_fingerprint, domains_for, file_lock, git, now, snapshot

REVIEW_LIMIT = 3
TASK = re.compile(r'^- \[([ xX])\] ((?:T\d{3}|TOR\d{3}))\b([^\n]*)$', re.M)


def rows(folder: Path) -> list[dict]:
    return [{'id': m[2], 'done': m[1].lower() == 'x', 'text': (m[2] + m[3]).strip(),
             'kind': next((kind for kind, mark in (('final', '[FINAL]'), ('audit', '[AUDIT]'), ('apk', '[APK]'))
                           if mark in m[3]), 'work')}
            for m in TASK.finditer((folder / 'tasks.md').read_text())]


def active_base(root: Path) -> str | None:
    """Read durable task records; a missing cache must not admit another owner."""
    active = []
    head = git(root, 'rev-parse', 'HEAD').strip()
    for path in (root / 'workflow/work/changes').glob('*/state.json'):
        state = json.loads(path.read_text())
        if state.get('workflow_version') != 2 or state.get('closed'):
            continue
        execution = state.get('execution', {})
        ident = execution.get('active')
        if not ident:
            ident = next((key for key, item in execution.get('tasks', {}).items()
                          if item.get('status') == 'done' and item.get('commit_parent') == head), None)
        if ident:
            base = execution['tasks'][ident]['base']
            if not re.fullmatch(r'[0-9a-f]{40}', base):
                raise Blocked('active task has an invalid baseline')
            active.append(base)
    if len(active) > 1:
        raise Blocked('multiple active tasks; preserve work and reconcile ownership')
    return active[0] if active else None


class TaskLoop:
    def __init__(self, root: Path, api: dict):
        self.root, self.c = root, SimpleNamespace(**api)

    def execute(self, operation: str, change: str, task: str | None = None, **options) -> dict:
        with file_lock(self.root / '.work/tasks/operation.lock'):
            self.folder = self.c.find_change(self.root, change)
            if not self.folder.resolve().is_relative_to(self.root.resolve()):
                raise Blocked('change records must stay inside this repository')
            self.state = self.c.read_state(self.folder)
            if self.state.get('workflow_version') != 2:
                raise Blocked('this record predates the task loop and is read-only')
            if self.state.get('closed'):
                if operation == 'status':
                    return {'status': 'CLOSED', 'change': self.folder.name, 'closed': self.state['closed']}
                raise Blocked('this change was closed outside the task loop; its records are read-only')
            self.execution = self.state.setdefault('execution', {'active': None, 'tasks': {}})
            self.items = self.execution['tasks']
            self.queue = rows(self.folder)
            self._validate()
            operations = {'start': self.start, 'check': self.check, 'packet': self.packet,
                          'review': self.review, 'complete': self.complete, 'add': self.add,
                          'resume': self.resume, 'status': self.status, 'planning-commit': self.planning_commit}
            if operation not in operations:
                raise Blocked('unknown task operation')
            return operations[operation](task, **options)

    def save(self):
        atomic_write(self.folder / 'state.json', json.dumps(self.state, indent=2, ensure_ascii=False) + '\n')

    def log(self, message: str):
        path = self.folder / 'log.md'
        atomic_write(path, path.read_text() + f'\n- {now()}: {message}\n')

    def _row(self, ident: str) -> dict:
        found = [r for r in self.queue if r['id'] == ident]
        if len(found) != 1:
            raise Blocked(f'no unique task {ident}')
        return found[0]

    def _validate(self):
        if not self.queue:
            raise Blocked('tasks.md has no tasks')
        if len({r['id'] for r in self.queue}) != len(self.queue):
            raise Blocked('duplicate task IDs')
        pending_apks = [i for i, r in enumerate(self.queue) if r['kind'] == 'apk' and not r['done']]
        if pending_apks and pending_apks != [len(self.queue) - 1]:
            raise Blocked('an unfinished [APK] task is optional, single, and the very last task')
        final_at = len(self.queue) - (2 if self.queue[-1]['kind'] == 'apk' else 1)
        if final_at < 0 or self.queue[final_at]['kind'] != 'final':
            raise Blocked('the last task must have [FINAL] cumulative review (only an [APK] build may follow it)')
        pending_finals = [i for i, r in enumerate(self.queue) if r['kind'] == 'final' and not r['done']]
        if pending_finals and pending_finals != [final_at]:
            raise Blocked('only the last task may be an unfinished final review')
        pending_audits = [i for i, r in enumerate(self.queue) if r['kind'] == 'audit' and not r['done']]
        if pending_audits and pending_audits != [final_at - 1]:
            raise Blocked('an unfinished [AUDIT] task is optional, single, and directly before the [FINAL] task')
        missing = set(self.items) - {row["id"] for row in self.queue}
        if missing:
            raise Blocked(f"recorded tasks cannot be removed from tasks.md: {', '.join(sorted(missing))}")
        self.pending_commit = []
        for row in self.queue:
            item = self.items.get(row['id'], {})
            preparing = item.get('status') == 'done' and git(self.root, 'rev-parse', 'HEAD').strip() == item.get('commit_parent')
            if row['done'] != (item.get('status') == 'done') and not preparing:
                raise Blocked(f'{row["id"]}: completion must be recorded by task commit, not a manual checkbox')
            if item.get('status') == 'done' and item.get('declaration') != row['text']:
                raise Blocked(f'{row["id"]}: a completed task declaration was edited; add a TOR request')
            if item.get('status') == 'done':
                if not self._committed(item, row['id']):
                    self.pending_commit.append(row['id'])

    def _committed(self, item: dict, ident: str):
        parent = item.get('commit_parent')
        if not parent or not re.fullmatch(r'[0-9a-f]{40}', parent) or not item.get('transaction'):
            raise Blocked(f'{ident}: completion has no committed checkpoint')
        descendants = git(self.root, 'rev-list', '--reverse', '--ancestry-path', f'{parent}..HEAD').splitlines()
        if not descendants:
            return False
        path = (self.folder / 'state.json').relative_to(self.root).as_posix()
        try:
            record = json.loads(git(self.root, 'show', f'{descendants[0]}:{path}'))
            stored = record['execution']['tasks'][ident]
        except (Blocked, KeyError, ValueError) as error:
            raise Blocked(f'{ident}: cannot prove committed completion') from error
        changed = git(self.root, 'diff', '--name-only', parent, descendants[0]).splitlines()
        prefix = self.folder.relative_to(self.root).as_posix() + '/'
        if any(self.c.is_record(p) and not p.startswith(prefix) for p in changed):
            raise Blocked(f'{ident}: unrelated records were included in the task commit')
        if set(changed) & set(self._protected(ident, item)):
            raise Blocked(f'{ident}: unrelated pre-existing files were included in the commit')
        if (stored.get('transaction') != item.get('transaction') or stored.get('status') != 'done'
                or stored.get('declaration') != item.get('declaration')):
            raise Blocked(f'{ident}: completion does not match its Git checkpoint')
        expected_records = stored.get('record_hashes', {})
        if not expected_records:
            raise Blocked(f'{ident}: completion record manifest is missing')
        for name, expected in expected_records.items():
            data = git(self.root, 'show', f'{descendants[0]}:{self.folder.relative_to(self.root).as_posix()}/{name}')
            if hashlib.sha256(data.encode('utf-8', errors='surrogateescape')).hexdigest() != expected:
                raise Blocked(f'{ident}: task records were omitted or changed in its commit: {name}')
        committed_tasks = git(self.root, 'show', f'{descendants[0]}:{self.folder.relative_to(self.root).as_posix()}/tasks.md')
        if not re.search(r'^- \[x\] ' + re.escape(ident) + r'\b', committed_tasks, re.M):
            raise Blocked(f'{ident}: task checkbox is not committed')
        actual = committed_fingerprint(self.root, descendants[0], self.c.RECORD_DIRS)
        if actual != stored['reviews'][-1].get('commit_fingerprint'):
            raise Blocked(f'{ident}: committed code differs from the clean review')
        return True

    def _planning_committed(self):
        if self.state['size'] == 'small':
            return
        parent = self.state.get('planning', {}).get('parent')
        if not parent:
            raise Blocked('commit planning once before starting tasks: planning-commit')
        commits = git(self.root, 'rev-list', '--reverse', '--ancestry-path', f'{parent}..HEAD').splitlines()
        if not commits:
            raise Blocked('planning is not committed')
        prefix = self.folder.relative_to(self.root).as_posix() + '/'
        checkpoint = json.loads(git(self.root, 'show', f'{commits[0]}:{prefix}state.json'))
        if checkpoint.get('planning') != self.state['planning']:
            raise Blocked('the prepared planning checkpoint was not committed')
        required = ('spec.md', 'plan.md', 'tasks.md', 'findings.md', 'log.md', 'assurance.json')
        for name in required:
            content = git(self.root, 'show', f'{commits[0]}:{prefix}{name}')
            expected = checkpoint['planning'].get('record_hashes', {}).get(name)
            if expected and hashlib.sha256(content.encode('utf-8', errors='surrogateescape')).hexdigest() != expected:
                raise Blocked('planning artifact differs from its checkpoint: ' + name)
        paths = git(self.root, 'diff', '--name-only', parent, commits[0]).splitlines()
        if not paths or any(not p.startswith(prefix) for p in paths):
            raise Blocked('planning checkpoint must contain only its planning artifacts')

    def _protected_path(self, ident: str) -> Path:
        return self.root / '.work/tasks' / self.folder.name / f'{ident}-protected.json'

    def _protected(self, ident: str, item: dict) -> dict:
        """Untracked files present before the task. Machine-local, so kept under ignored .work/."""
        path = self._protected_path(ident)
        return json.loads(path.read_text()) if path.is_file() else {}

    def _code_fingerprint(self, ident: str, item: dict) -> str:
        return snapshot(self.root, drop=self.c.RECORD_DIRS, exclude=tuple(self._protected(ident, item)))[0]

    def _reopen(self, ident: str):
        """A reviewed task that is not committed yet returns to the loop when it is touched again."""
        item = self.items[ident]
        last = item['reviews'][-1] if item['reviews'] else {}
        unchanged = last.get('result') == 'clean' and last.get('fingerprint') == self.c.fingerprint(self.root)
        item['status'] = 'reviewed' if unchanged else 'fixing'
        self.execution['active'] = ident
        self.pending_commit.remove(ident)
        path = self.folder / 'tasks.md'
        atomic_write(path, re.sub(r'^- \[[xX]\] ' + re.escape(ident) + r'\b', '- [ ] ' + ident, path.read_text(), flags=re.M))
        self.queue = rows(self.folder)
        self.save()

    def _current(self, ident: str | None) -> tuple[dict, dict]:
        if ident in self.pending_commit and not self.execution['active']:
            self._reopen(ident)
        if ident is None or self.execution['active'] != ident:
            raise Blocked('the requested task is not the active task')
        row, item = self._row(ident), self.items[ident]
        if item['status'] == 'blocked':
            raise Blocked('task stopped after three reviews; report findings and wait for explicit owner instructions')
        if git(self.root, 'rev-parse', 'HEAD').strip() != item['head']:
            raise Blocked('HEAD changed during the task; preserve work and reconcile before continuing')
        self._protect(ident, item)
        return row, item

    def _protect(self, ident: str, item: dict):
        protected = self._protected(ident, item)
        if protected:
            _, listing = snapshot(self.root, drop=self.c.RECORD_DIRS, listing=True)
            for path, original in protected.items():
                if list(listing.get(path, ())) != original:
                    raise Blocked(f'protected pre-existing file changed: {path}')

    def _paths(self, base: str, item: dict, ident: str) -> list[str]:
        protected = self._protected(ident, item)
        return [p for p in self.c.changed_paths(self.root, base) if p not in protected]

    def _identity(self, row: dict) -> str:
        declaration = '\n'.join(r['text'] for r in self.queue) if row['kind'] == 'final' else row['text']
        return hashlib.sha256((self.c.docs_fingerprint(self.folder) + declaration).encode()).hexdigest()

    def _required(self, row: dict, item: dict, extra=()) -> list[str]:
        config = self.c.load_config(self.root)
        paths = self._paths(item['base'], item, row['id'])
        domains = domains_for(config, paths)
        required = {key for domain in domains for key in config['domain_checks'].get(domain, [])}
        declaration = row['text'].split('check:', 1)[-1]
        required.update(k for k in config['checks'] if re.search(r'(?<![\w-])' + re.escape(k) + r'(?![\w-])', declaration))
        for key in extra:
            if key not in config['checks']:
                raise Blocked(f'unknown additional check {key}')
            required.add(key)
        if row['kind'] == 'final' and (self.folder / 'assurance.json').is_file():
            # Preserve the declared port/bridge checks for the cumulative result.
            assurance = json.loads((self.folder / 'assurance.json').read_text())
            for component in assurance.get('port', {}).get('components', []):
                required.update(component.get('checks', []))
            for contract in assurance.get('bridge', {}).get('contracts', []):
                required.update(contract.get('caller_checks', []) + contract.get('native_checks', []))
        if required - config['checks'].keys():
            raise Blocked('a declared check is missing from checks.json')
        return [k for k in config['checks'] if k in required]

    def start(self, ident: str, **_):
        self._planning_committed()
        if self.pending_commit:
            raise Blocked('commit the reviewed task with ordinary Git before starting another')
        if self.execution['active']:
            raise Blocked('finish and commit the active task before starting another')
        pointer = self.root / '.work/active-task.json'
        if active_base(self.root) is not None:
            raise Blocked('another change has an active task')
        pending = next((r for r in self.queue if not r['done']), None)
        if pending is None or pending['id'] != ident:
            raise Blocked('tasks must execute in queue order')
        tracked = [p for p in git(self.root, 'diff', '--name-only', 'HEAD').splitlines() if not self.c.is_record(p)]
        if tracked:
            raise Blocked('preserve unrelated tracked changes before starting: ' + ', '.join(tracked))
        prefix = self.folder.relative_to(self.root).as_posix() + '/'
        if any(not p.startswith(prefix) for p in git(self.root, 'diff', '--cached', '--name-only').splitlines()):
            raise Blocked('preserve unrelated staged files before starting')
        untracked = [p for p in git(self.root, 'ls-files', '--others', '--exclude-standard', '-z').split('\0')
                     if p and not self.c.is_record(p)]
        if domains_for(self.c.load_config(self.root), untracked):
            raise Blocked('preserve pre-existing untracked source files before starting')
        _, listing = snapshot(self.root, drop=self.c.RECORD_DIRS, listing=True)
        self.c.workmap.ensure_current(self.root)
        context = self.c.workmap.context(self.root, pending['text'], refresh=False)['text']
        path = self.root / '.work/tasks' / self.folder.name / f'{ident}-context.md'
        atomic_write(path, context)
        head = git(self.root, 'rev-parse', 'HEAD').strip()
        self.items[ident] = {'status': 'active', 'head': head,
                            'base': self.state['base'] if pending['kind'] == 'final' else head,
                            'declaration': pending['text'], 'cycle': 1, 'reviews': [], 'checks': None}
        atomic_write(self._protected_path(ident), json.dumps({p: list(listing[p]) for p in untracked}))
        self.execution['active'] = ident
        self.save()
        atomic_write(pointer, json.dumps({'change': self.folder.name, 'task': ident}))
        result = {'status': 'PASS', 'task': ident, 'context': str(path.relative_to(self.root))}
        if pending['kind'] == 'audit':  # scope: everything this change touched, not the whole repository
            try:
                kinds = self.c.workaudit.load_config(self.root).get('task_kinds', ['code'])
                reports = [self.c.workaudit.audit(
                    self.root, base=self.state['base'], is_record=self.c.is_record, kind=kind,
                    label=f'{self.folder.name}-{ident}', high_risk=self.c.load_config(self.root).get('high_risk', []))
                    for kind in kinds]
                result['audit'] = [{key: report[key] for key in ('kind', 'report', 'files', 'proven', 'leads', 'gaps')}
                                   for report in reports]
            except Blocked as error:
                result['audit_blocked'] = str(error)
        return result

    def check(self, ident: str, checks=(), **_):
        row, item = self._current(ident)
        required = self._required(row, item, checks)
        identity, fp = self._identity(row), self.c.fingerprint(self.root)
        item['checks'] = {'status': 'RUNNING', 'identity': identity, 'fingerprint': fp, 'ids': required, 'extra': list(checks)}
        self.save()
        result = self.c.run_checks(self.root, self.c.load_config(self.root), required) if required else {'status': 'NOT_REQUIRED'}
        # Requirements live in excluded progress directories, so bind them too.
        self.queue = rows(self.folder)
        unchanged = fp == self.c.fingerprint(self.root) and identity == self._identity(self._row(ident))
        good = result['status'] in ('PASS', 'NOT_REQUIRED') and unchanged
        item['checks']['status'] = result['status'] if good else 'INCOMPLETE'
        self.save()
        result = {'status': 'PASS' if good else 'INCOMPLETE', 'task': ident,
                  'checks_status': item['checks']['status'], 'checks': required,
                  'requirements_changed': identity != self._identity(self._row(ident))}
        if good and len(self._cycles(item)) < REVIEW_LIMIT:
            try:  # passing checks hand the reviewer its packet in the same step
                result['packet'] = self.packet(ident)['packet']
            except Blocked as error:
                result['packet_blocked'] = str(error)
        return result

    def _evidence(self, row: dict, item: dict):
        evidence = item.get('checks') or {}
        required = self._required(row, item, evidence.get('extra', []))
        if (evidence.get('status') != ('PASS' if required else 'NOT_REQUIRED')
                or evidence.get('identity') != self._identity(row)
                or evidence.get('fingerprint') != self.c.fingerprint(self.root)
                or evidence.get('ids') != required):
            raise Blocked('task checks are missing or stale; run task check after the latest changes')
        if required:
            current = self.c.check_evidence(self.root)
            if any(current.get(k, {}).get('status') != 'PASS'
                   or current.get(k, {}).get('fingerprint') != evidence['fingerprint'] for k in required):
                raise Blocked('runner evidence is missing or stale')

    def packet(self, ident: str, **_):
        row, item = self._current(ident)
        if len(self._cycles(item)) >= REVIEW_LIMIT:
            last = item['reviews'][-1]
            if (last.get('fingerprint') != self.c.fingerprint(self.root)
                    or last.get('identity') != self._identity(row)):
                item['status'] = 'blocked'
                self.save()
            raise Blocked('three reviews reached; commit the unchanged clean task or report to the owner')
        self._evidence(row, item)
        self.c.workmap.ensure_current(self.root)
        path = f'.work/review/{self.folder.name}-{ident}-r{len(item["reviews"]) + 1}.md'
        result = self.c.packet(self.root, item['base'], None, self.folder.name, path,
                               exclude_paths=set(self._protected(ident, item)))
        target = self.root / path
        with target.open('a') as output:
            output.write('\n## Active task\n\n' + row['text'] + '\n\nTask checks: ' + json.dumps(item['checks']) + '\n')
            if row['kind'] == 'final':
                output.write('\n## Cumulative task outcomes\n\n' + json.dumps(self.items, indent=2) + '\n')
        item['packet'] = {'path': path, 'fingerprint': self.c.fingerprint(self.root),
                          'identity': self._identity(row), 'map': self.c.workmap.round_record(self.root)}
        self.save()
        return result

    def status(self, ident=None, **_):
        return {'status': 'BLOCKED' if any(i.get('status') == 'blocked' for i in self.items.values()) else 'PASS',
                'change': self.folder.name, 'active': self.execution['active'], 'waiting_for_git_commit': self.pending_commit,
                'tasks': [{'id': r['id'], 'status': 'waiting_commit' if r['id'] in self.pending_commit else self.items.get(r['id'], {}).get('status', 'pending'),
                           'cycle': self.items.get(r['id'], {}).get('cycle', 1)} for r in self.queue]}

    def _findings(self, ident: str, cumulative: bool):
        path = self.folder / 'findings.md'
        findings = self.c.parse_findings(path.read_text()) if path.is_file() else []
        for finding in findings:
            if not cumulative and finding.get('task') not in (None, ident):
                continue
            if finding.get('severity') not in self.c.SEVERITIES or finding.get('status') not in self.c.STATUSES:
                raise Blocked('review finding has invalid severity/status: ' + finding['id'])
            if finding['status'] in ('open', 'escalated'):
                raise Blocked('unresolved review finding: ' + finding['id'])
            if not finding.get('evidence'):
                raise Blocked('resolved finding needs evidence: ' + finding['id'])
            if finding['status'] == 'declined' and finding['severity'] != 'nit':
                raise Blocked('only nits may be declined: ' + finding['id'])

    def _cycles(self, item):
        return [r for r in item['reviews'] if r.get('cycle', 1) == item['cycle']]

    def review(self, ident: str, result=None, reviewer=None, note='', **_):
        row, item = self._current(ident)
        if result not in ('clean', 'dirty') or not reviewer or not reviewer.strip():
            raise Blocked('review requires clean/dirty and an independent reviewer name')
        rounds = self._cycles(item)
        if len(rounds) >= REVIEW_LIMIT:
            item['status'] = 'blocked'; self.save()
            raise Blocked('three reviews reached; report to the owner instead of starting a fourth')
        packet = item.get('packet', {})
        if not packet:
            raise Blocked('prepare a task packet before independent review')
        if result == 'clean':
            self._evidence(row, item)
            if (packet.get('fingerprint') != self.c.fingerprint(self.root)
                    or packet.get('identity') != self._identity(row)):
                raise Blocked('prepare a current task packet before independent review')
            self.c.workmap.ensure_current(self.root)
            if packet.get('map', {}).get('corpus') != self.c.current_map_corpus(self.root):
                raise Blocked('map changed after the packet; prepare the review against current code')
            self._findings(ident, row['kind'] == 'final')
        record = {'cycle': item['cycle'], 'round': len(rounds) + 1, 'result': result, 'reviewer': reviewer,
                  'note': note, 'path': packet['path'], 'fingerprint': packet['fingerprint'],
                  'identity': packet['identity'], 'at': now()}
        if result == 'clean':
            record['commit_fingerprint'] = self._code_fingerprint(ident, item)
        item['reviews'].append(record)
        item['status'] = 'reviewed' if result == 'clean' else 'blocked' if len(rounds) + 1 == REVIEW_LIMIT else 'fixing'
        self.save()
        if result == 'clean':  # a clean review prepares the task commit in the same step
            summary = {'task': ident, 'result': result, 'round': len(rounds) + 1, 'cycle': item['cycle']}
            try:
                return {**summary, **self.complete(ident)}
            except Blocked as error:
                return {**summary, 'status': 'PASS',
                        'note': f'clean review recorded; run task complete after resolving: {error}'}
        return {'status': 'BLOCKED' if item['status'] == 'blocked' else 'PASS', 'task': ident,
                'result': result, 'round': len(rounds) + 1, 'cycle': item['cycle'],
                'remaining_findings': [f for f in self.c.parse_findings((self.folder / 'findings.md').read_text()) if f.get('status') in ('open', 'escalated')] if (self.folder / 'findings.md').is_file() else [],
                'note': 'Stop and report remaining findings to the owner; no commit or next task.'
                        if item['status'] == 'blocked' else note}

    def resume(self, ident: str, owner_instruction=None, **_):
        if not owner_instruction or not owner_instruction.strip():
            raise Blocked('resume requires the explicit owner instruction; never invoke it automatically')
        if self.execution['active'] != ident or self.items[ident]['status'] != 'blocked':
            raise Blocked('only the active blocked task can resume')
        item = self.items[ident]
        if git(self.root, 'rev-parse', 'HEAD').strip() != item['head']:
            raise Blocked('HEAD changed; reconcile preserved work before resuming')
        self._protect(ident, item)
        item.setdefault('resumptions', []).append({'instruction': owner_instruction, 'at': now(), 'after_cycle': item['cycle']})
        item['cycle'] += 1; item['status'] = 'fixing'
        item.pop('packet', None)
        self.save()
        self.log(f'{ident} resumed only on owner instruction: {owner_instruction}')
        return {'status': 'PASS', 'task': ident, 'cycle': item['cycle']}

    def add(self, ident=None, request=None, **_):
        if not request or not request.strip():
            raise Blocked('TOR requires the owner request text')
        if any(i.get('status') == 'blocked' for i in self.items.values()):
            raise Blocked('resolve the stopped task with the owner before adding work')
        active = self.execution['active']
        if active and self._row(active)['kind'] == 'final':
            raise Blocked('finish the active final task first; a later request reopens a fresh final review')
        if self.queue[-1]['kind'] == 'apk' and not self.queue[-1]['done'] and self.queue[-2]['done']:
            raise Blocked('finish the [APK] task first; a later request then gets a fresh final review')
        if active and self._row(active)['kind'] == 'audit':
            raise Blocked('finish the active audit task first; the request then queues before the final review')
        number = max((int(r['id'][3:]) for r in self.queue if r['id'].startswith('TOR')), default=0) + 1
        if number > 999:
            raise Blocked('TOR numbering exhausted; start a new change')
        task = f'TOR{number:03d}'
        title = ' '.join(request.split())
        lines = (self.folder / 'tasks.md').read_text().splitlines()
        if self.state['phase'] == 'done':
            final_number = max(int(r['id'][1:]) for r in self.queue if not r['id'].startswith('TOR')) + 1
            if final_number > 999:
                raise Blocked('task numbering exhausted; start a new change')
            lines += [f'- [ ] {task} {title} — check: auto',
                      f'- [ ] T{final_number:03d} [FINAL] Review the cumulative result — check: auto']
            self.state['phase'] = 'tasks'
        else:
            following = next(r['id'] for r in self.queue
                             if not r['done'] and not r['id'].startswith('TOR') and r['id'] != self.execution['active'])
            at = next(i for i, line in enumerate(lines) if re.match(r'^- \[ \] ' + following + r'\b', line))
            lines.insert(at, f'- [ ] {task} {title} — check: auto')
        atomic_write(self.folder / 'tasks.md', '\n'.join(lines) + '\n')
        self.save(); self.log(f'{task}: owner request: {title}')
        return {'status': 'PASS', 'task': task, 'request': title}

    def _staged_records(self):
        prefix = self.folder.relative_to(self.root).as_posix() + '/'
        staged = git(self.root, 'diff', '--cached', '--name-only').splitlines()
        if any(self.c.is_record(p) and not p.startswith(prefix) for p in staged):
            raise Blocked('preserve unrelated staged records before completing this task')

    def complete(self, ident: str, **_):
        self._staged_records()
        if ident in self.pending_commit:  # already prepared: say so again without rewriting records
            last = self.items[ident]['reviews'][-1] if self.items[ident]['reviews'] else {}
            if last.get('fingerprint') != self.c.fingerprint(self.root):
                raise Blocked('code changed after the clean review; run task check to reopen the task')
            self.items[ident]['record_hashes'] = self._record_hashes()  # records edited since are part of the commit
            self.save()
            return {'status': 'READY_TO_COMMIT', 'task': ident,
                    'note': 'Stage explicit task paths and records, then commit once; the next task start verifies it.'}
        row, item = self._current(ident)
        self._evidence(row, item)
        last = item['reviews'][-1] if item['reviews'] else {}
        if (item['status'] != 'reviewed' or last.get('result') != 'clean'
                or last.get('fingerprint') != self.c.fingerprint(self.root)
                or last.get('identity') != self._identity(row)):
            raise Blocked('a clean review of the current task/code is required before commit')
        self._findings(ident, row['kind'] == 'final')
        if row['kind'] == 'final' and self.state['size'] != 'small':
            problems = self.c.assurance_problems(self.root, self.folder, 'ship')
            if problems:
                raise Blocked('\n'.join(problems))
        item['status'] = 'done'; item['declaration'] = row['text']
        item['commit_parent'] = item['head']; item.setdefault('transaction', uuid.uuid4().hex)
        self.execution['active'] = None
        for transient in ('packet', 'context'):
            item.pop(transient, None)
        if row is self.queue[-1]:  # the final review, or the [APK] build that follows it
            self.state['phase'] = 'done'
        text = (self.folder / 'tasks.md').read_text()
        tasks = re.sub(r'^- \[ \] ' + re.escape(ident) + r'\b', '- [x] ' + ident, text, flags=re.M)
        log = (self.folder / 'log.md').read_text() + f'\n- {now()}: {ident} reviewed and ready; implementation, fixes and records belong in one Git commit.\n'
        item['record_hashes'] = self._record_hashes({'tasks.md': tasks.encode(), 'log.md': log.encode()})
        self.save()
        atomic_write(self.folder / 'tasks.md', tasks)
        atomic_write(self.folder / 'log.md', log)
        return {'status': 'READY_TO_COMMIT', 'task': ident,
                'note': 'Stage explicit task paths and records, then commit once; the next task start verifies it.'}

    def planning_commit(self, ident=None, message=None, **_):
        self._staged_records()
        if self.state['size'] == 'small' or self.state.get('planning'):
            raise Blocked('planning is absent or already checkpointed')
        if self.state['phase'] not in ('plan', 'tasks'):
            raise Blocked('finish planning before its single commit')
        problems = self.c.planning_problems(self.root, self.folder, 'build')
        if problems:
            raise Blocked('\n'.join(problems))
        tracked = [p for p in self.c.changed_paths(self.root) if not self.c.is_record(p)]
        if domains_for(self.c.load_config(self.root), tracked) or any(
                not self.c.is_record(p) for p in git(self.root, 'diff', '--name-only', 'HEAD').splitlines()):
            raise Blocked('planning commit must not absorb source changes')
        nonce = uuid.uuid4().hex
        self.state['planning'] = {'parent': git(self.root, 'rev-parse', 'HEAD').strip(), 'transaction': nonce,
                                  'record_hashes': self._record_hashes()}
        self.state['phase'] = 'tasks'
        self.save()
        return {'status': 'READY_TO_COMMIT', 'note': 'Commit all planning artifacts together once using ordinary Git.'}


    def _record_hashes(self, overrides=None):
        content = {path.relative_to(self.folder).as_posix(): path.read_bytes()
                   for path in self.folder.rglob('*') if path.is_file() and path != self.folder / 'state.json'}
        content.update(overrides or {})
        return {name: hashlib.sha256(data).hexdigest() for name, data in content.items()}
