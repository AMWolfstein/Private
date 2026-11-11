#!/usr/bin/env python3
"""Open one draft review PR; never merge, force-push, execute patches or release."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ALLOWED = ('extensions/updates/state.json', 'extensions/updates/reports/', 'extensions/updates/patches/')


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    proposal = json.loads((ROOT / 'extensions/updates/.cache/proposal.json').read_text())
    branch, base = proposal['branch'], proposal['base']
    if not re.fullmatch(r'automation/extension-updates-[0-9a-f]{16}', branch):
        raise ValueError('Invalid proposal branch')
    expected = json.loads((ROOT / 'extensions/updates/watch.json').read_text())['target_branch']
    if base != expected or proposal['body_file'] != 'extensions/updates/reports/latest.md':
        raise ValueError('Unexpected proposal target or body')
    pending = json.loads(run('gh', 'pr', 'list', '--base', base, '--state', 'open', '--limit', '100',
                             '--json', 'headRefName,url'))
    for pr in pending:
        if pr['headRefName'].startswith('automation/extension-updates-'):
            print('An upstream review is already pending: ' + pr['url'])
            return
    # A previously closed proposal is not automatically reopened or overwritten.
    if run('git', 'ls-remote', '--heads', 'origin', 'refs/heads/' + branch):
        print('This proposal branch already exists; no history is rewritten.')
        return
    # Git -z output preserves filenames; reject unrelated work before staging.
    unstaged = run('git', 'ls-files', '-m', '-o', '--exclude-standard', '-z')
    staged = run('git', 'diff', '--cached', '--name-only', '-z')
    deleted = run('git', 'ls-files', '-d', '-z')
    paths = sorted({p for p in (unstaged + '\0' + staged + '\0' + deleted).split('\0') if p})
    if not paths:
        print('No proposal changes to commit.')
        return
    if any(not any(p.startswith(prefix) if prefix.endswith('/') else p == prefix for prefix in ALLOWED) for p in paths):
        raise ValueError('Unrelated checkout changes; refusing to stage')
    run('git', 'switch', '-c', branch)
    run('git', 'config', 'user.name', 'github-actions[bot]')
    run('git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
    run('git', 'add', '--', *paths)
    run('git', 'diff', '--cached', '--check')
    run('git', 'commit', '-m', 'chore(extensions): propose upstream source review')
    run('git', 'push', 'origin', 'HEAD:refs/heads/' + branch)
    print(run('gh', 'pr', 'create', '--draft', '--base', base, '--head', branch,
              '--title', proposal['title'], '--body-file', proposal['body_file']))


if __name__ == '__main__':
    main()
