#!/usr/bin/env python3
"""Read-only checks for the pinned discovery evidence; not application tests.

Run from any working directory inside the repository. The explicitly fetched
upstream release history must be available (see HANDOFF.md).
"""
import collections
import csv
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(__file__).resolve().parent


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def check(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)
    print('PASS: ' + message)


def main():
    evidence = json.loads((DATA / 'evidence.json').read_text())
    with (DATA / 'commits.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    with (DATA / 'paths.csv').open(newline='') as stream:
        paths = list(csv.DictReader(stream))
    reviewed = json.loads((DATA / 'source-reviewed.json').read_text())
    baseline = evidence['comparison_baseline']
    target = evidence['target_commit']
    snapshot = evidence['local_snapshot_root']
    actual = git('rev-list', '--reverse', f'{baseline}..{target}').splitlines()
    check([row['sha'] for row in rows] == actual and len(rows) == 238,
          'all 238 pinned commits inventoried exactly once in Git order')
    check(len(set(row['id'] for row in rows)) == len(rows), 'unique inventory IDs')
    check(dict(collections.Counter(row['classification'] for row in rows))
          == evidence['classification_counts'], 'classification totals match evidence')
    check(dict(collections.Counter(row['evidence_level'] for row in rows))
          == evidence['evidence_counts'], 'review-depth totals match evidence')
    expected_classes = {'ADOPT', 'ADAPT', 'ALREADY IMPLEMENTED', 'REJECT',
                        'DEFER', 'INVESTIGATE'}
    check(all(row['classification'] in expected_classes and all(row[key] for key in (
        'sha', 'subject', 'upstream_files', 'local_implementation', 'dependency_impact',
        'decision_scope', 'evidence_level', 'reasoning', 'expected_benefit',
        'implementation_complexity', 'regression_risk',
        'recommended_thinking_effort', 'required_tests', 'priority', 'batch'))
        for row in rows), 'required change-assessment fields populated')
    check(all(item in rows for item in reviewed), 'focused records match full inventory')
    changed = git('diff', '--name-status', baseline, target).splitlines()
    check([p['upstream_path'] for p in paths]
          == [line.split('\t')[-1] for line in changed] and len(paths) == 858,
          'all 858 changed paths inventoried')
    check(git('diff', '--name-status', baseline, snapshot).splitlines()
          == evidence['snapshot_difference'] and len(evidence['snapshot_difference']) == 4
          and all(line.startswith('D\t') for line in evidence['snapshot_difference']),
          'content baseline differs from snapshot by only four recorded deletions')
    check(git('rev-list', '--parents', '-n', '1', snapshot) == snapshot,
          'local snapshot is parentless')
    result = subprocess.run(['git', 'merge-base', snapshot, target], cwd=ROOT,
                            capture_output=True, text=True)
    check(result.returncode == 1 and not result.stdout.strip(),
          'no shared merge base; no upstream ancestry asserted')
    check(git('rev-parse', '--is-shallow-repository') == 'false',
          'repository is not shallow')
    for label, commit in [('baseline', baseline), ('target', target),
                          ('local_snapshot', snapshot)]:
        check(git('rev-parse', commit + '^{tree}') == evidence[label + '_tree'],
              label + ' tree pinned correctly')
    check(git('rev-parse', evidence['target_tag_object'] + '^{commit}') == target,
          'annotated release tag peels to pinned target')
    graph = json.loads((ROOT / 'graphify-out/graph.json').read_text())
    nodes = graph['nodes']
    links = graph['links']
    node_ids = {node['id'] for node in nodes}
    check(len(node_ids) == len(nodes) and all(
        link['source'] in node_ids and link['target'] in node_ids for link in links),
        f'Graphify JSON has {len(nodes)} unique nodes and valid link endpoints')
    check(graph.get('built_at_commit') == evidence['graph_source_commit'],
          'Graphify built_at_commit matches recorded source checkpoint')
    changed_since_source = git('diff', '--name-only',
                              evidence['graph_source_commit']).splitlines()
    check(all(p.startswith(('reviews/', 'graphify-out/')) or p in (
        'LOCAL_OFFLINE_MIGRATION_PLAN.md', 'AGENTS.md')
        for p in changed_since_source), 'no application divergence since graph source')
    changed_since_entry = git('diff', '--name-only',
                             evidence['local_source_checkpoint']).splitlines()
    check(all(p.startswith('reviews/') for p in changed_since_entry),
          'tracked audit changes confined to reviews/')
    for name in ('STATE.md', 'HANDOFF.md', 'BACKLOG.md', 'VERIFICATION.md',
                 'upstream-v5.2.0-audit.md', 'upstream-v5.2.0-backlog.md'):
        check((ROOT / 'reviews' / name).is_file(), 'persistent report exists: ' + name)
    subprocess.run(['git', 'diff', '--check'], cwd=ROOT, check=True)
    print('PASS: working diff whitespace check')
    print('Application tests/build NOT RUN by this review-only verifier.')


if __name__ == '__main__':
    main()
