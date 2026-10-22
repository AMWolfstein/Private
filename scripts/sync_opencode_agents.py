#!/usr/bin/env python3
"""Mirror the reviewer agents in .claude/agents/ as OpenCode subagents.

OpenCode does not read .claude/agents/, and its frontmatter differs (mode and
permission instead of tools and a Claude model alias). The Claude files stay the
source; run this after editing one. `--check` exits 1 when the mirror is stale.
"""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / '.claude' / 'agents'
TARGET = ROOT / '.opencode' / 'agents'

# Reviewers only read code. The OpenCode session itself makes the fixes, so the
# Claude review-fixer has no OpenCode counterpart.
SKIPPED = {'review-fixer'}

# Last matching rule wins in OpenCode, so the catch-all deny comes first.
READ_ONLY_BASH = (
    'git diff*', 'git log*', 'git show*', 'git status*', 'git blame*',
    'git ls-files*', 'git rev-parse*', 'graphify query*', 'graphify explain*',
    'graphify path*', 'grep *', 'rg *', 'ls*', 'cat *', 'head *', 'tail *',
    'sed -n*', 'wc *', 'find *', 'scripts/review_scope.sh*',
    'bash scripts/review_scope.sh*',
)


def split(text, name):
    match = re.match(r'---\n(.*?)\n---\n(.*)', text, re.S)
    if not match:
        raise SystemExit(f'{name}: missing frontmatter')
    fields = dict(
        line.split(':', 1) for line in match.group(1).splitlines() if ':' in line
    )
    return {k.strip(): v.strip() for k, v in fields.items()}, match.group(2)


def render(path):
    fields, body = split(path.read_text(), path.name)
    lines = [
        '---',
        f"description: {fields['description']}",
        'mode: subagent',
        'permission:',
        '  edit: deny',
        '  webfetch: deny',
        '  bash:',
        '    "*": deny',
        *(f'    "{rule}": allow' for rule in READ_ONLY_BASH),
        '---',
        '',
        f'<!-- Generated from .claude/agents/{path.name} by '
        'scripts/sync_opencode_agents.py; edit that file instead. -->',
        '',
    ]
    return '\n'.join(lines) + body.lstrip('\n')


def expected():
    return {
        path.name: render(path)
        for path in sorted(SOURCE.glob('*.md'))
        if path.stem not in SKIPPED
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    files = expected()
    present = {path.name for path in TARGET.glob('*.md')} if TARGET.is_dir() else set()
    stale = sorted(
        name for name, text in files.items()
        if not (TARGET / name).is_file() or (TARGET / name).read_text() != text
    ) + sorted(present - files.keys())
    if args.check:
        for name in stale:
            print(f'stale: .opencode/agents/{name}')
        return 1 if stale else 0
    TARGET.mkdir(parents=True, exist_ok=True)
    for name in present - files.keys():
        (TARGET / name).unlink()
    for name, text in files.items():
        (TARGET / name).write_text(text)
    print(f'wrote {len(files)} agents to .opencode/agents/')
    return 0


if __name__ == '__main__':
    sys.exit(main())
