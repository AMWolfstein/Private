#!/usr/bin/env python3
"""Compare `work.py context` packets with a no-map baseline on representative tasks.

    python3 workflow/scripts/work/bench_context.py --tasks TASKS.json [--root .] [--out RESULT.json]

TASKS.json: [{"id", "kind", "task", "files": [], "symbols": [], "expected": [paths or text that must appear]}]

Baseline (a deterministic model of searching without the map, not a recorded agent session): the output of a
case-insensitive whole-word search for the task's words over the same corpus files (what `rg -n -i -w` would
print), plus the full text of the `--read` files with the most distinct matching words. The map side is the
context packet. Sizes are characters; tokens are estimated as characters / 4 and labelled as estimates.
Coverage counts expected items present in what each side puts in front of the agent.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import workmap  # noqa: E402
from worklib import snapshot  # noqa: E402


def baseline(root: Path, task: dict, read: int) -> dict:
    started = time.monotonic()
    config = workmap.load_config(root)
    _tree, listing = snapshot(root, listing=True)
    corpus, _ = workmap.corpus_of(listing, config)
    terms = sorted({w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]{2,}', task['task'])
                    if w.lower() not in workmap.STOPWORDS} | set(task.get('symbols', [])))
    pattern = re.compile(r'\b(?:' + '|'.join(map(re.escape, terms)) + r')\b', re.I) if terms else None
    output, scores = [], {}
    for path in corpus:
        try:
            text = (root / path).read_text(errors='replace')
        except OSError:
            continue
        found = set()
        for number, line in enumerate(text.split('\n'), 1):
            hits = pattern.findall(line) if pattern else []
            if hits:
                output.append(f'{path}:{number}:{line}')
                found |= {h.lower() for h in hits}
        if found:
            scores[path] = (len(found), sum(1 for o in output if o.startswith(path + ':')))
    named = [p for p in task.get('files', []) if p in corpus]
    top = named + [p for p, _ in sorted(scores.items(), key=lambda kv: (-kv[1][0], -kv[1][1], kv[0]))
                   if p not in named][:max(0, read - len(named))]
    grep_text = '\n'.join(output)
    read_text = ''.join((root / p).read_text(errors='replace') for p in top)
    seen = grep_text + '\n' + '\n'.join(top) + '\n' + read_text
    return {'seconds': round(time.monotonic() - started, 2), 'search_chars': len(grep_text),
            'search_lines': len(output), 'files_matched': len(scores), 'read_files': top,
            'read_chars': len(read_text), 'chars': len(grep_text) + len(read_text),
            'tokens_estimate': (len(grep_text) + len(read_text)) // 4,
            'covered': [e for e in task['expected'] if e in seen],
            'covered_in_read_files': [e for e in task['expected'] if e in read_text or e in top]}


def mapped(root: Path, task: dict, budget: int | None) -> dict:
    started = time.monotonic()
    result = workmap.context(root, task['task'], task.get('files', []), task.get('symbols', []), budget=budget,
                             refresh=False)
    text, data = result['text'], result['data']
    return {'seconds': round(time.monotonic() - started, 2), 'chars': len(text), 'tokens_estimate': len(text) // 4,
            'entry_files': [e['file'] for e in data['entries']], 'truncated': data['truncated'],
            'critical_over_budget': data['critical_over_budget'], 'fallback': bool(data['fallback']),
            'covered': [e for e in task['expected'] if e in text]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--tasks', type=Path, required=True)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--read', type=int, default=5, help='files the baseline reads in full')
    parser.add_argument('--budget', type=int)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    started = time.monotonic()
    update = workmap.update(root)
    status = workmap.map_status(root)
    results = {'map': {'state': status['state'], 'files': status['files'], 'structure': update.get('structure'),
                       'update_seconds': round(time.monotonic() - started, 2), 'rebuilt': update['rebuilt']},
               'note': 'tokens are estimates (characters / 4); no model token counts were available',
               'tasks': []}
    for task in json.loads(args.tasks.read_text()):
        item = {'id': task['id'], 'kind': task['kind'], 'task': task['task'], 'expected': task['expected'],
                'map': mapped(root, task, args.budget), 'baseline': baseline(root, task, args.read)}
        results['tasks'].append(item)
        print(f'{task["id"]:<20} map {item["map"]["tokens_estimate"]:>6} tok est, '
              f'{len(item["map"]["covered"])}/{len(task["expected"])} covered, {item["map"]["seconds"]}s | '
              f'baseline {item["baseline"]["tokens_estimate"]:>7} tok est, '
              f'{len(item["baseline"]["covered"])}/{len(task["expected"])} seen, '
              f'{len(item["baseline"]["covered_in_read_files"])} in read files, {item["baseline"]["seconds"]}s')
    if args.out:
        args.out.write_text(json.dumps(results, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
