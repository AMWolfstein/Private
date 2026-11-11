#!/usr/bin/env python3
"""Create review-only upstream diffs. Never import, execute, merge or publish source code."""
import argparse
import datetime as dt
import difflib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MAX_BYTES = 16 * 1024 * 1024


def read_json(path):
    return json.loads(path.read_text())


def blob_hash(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def due(config, today):
    anchor = dt.date.fromisoformat(config['anchor_monday'])
    interval = config['interval_days']
    if anchor.weekday() != 0 or interval != 14:
        raise ValueError('Expected a Monday anchor and 14-day interval')
    return today >= anchor and (today - anchor).days % interval == 0


def safe_path(path):
    if not re.fullmatch(r'[A-Za-z0-9_./-]+', path) or path.startswith('/') or '..' in PurePosixPath(path).parts:
        raise ValueError('Unsafe upstream path')
    return path


class GitHub:
    """Public read-only endpoints; no repository write token is sent upstream."""
    def read(self, url):
        request = urllib.request.Request(url, headers={'User-Agent': 'Mornye-source-watch/1'})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError('Upstream response exceeds size bound')
        return data

    def head(self, repository, branch):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid repository')
        ref = urllib.parse.quote(branch, safe='')
        value = json.loads(self.read(f'https://api.github.com/repos/{repository}/commits/{ref}'))
        sha = value['sha']
        if not re.fullmatch(r'[0-9a-f]{40}', sha):
            raise ValueError('Invalid upstream commit')
        return sha

    def tree(self, repository, commit):
        value = json.loads(self.read(f'https://api.github.com/repos/{repository}/git/trees/{commit}?recursive=1'))
        if value.get('truncated'):
            raise ValueError('Incomplete upstream tree; refusing to infer deletions')
        return {item['path']: item['sha'] for item in value['tree'] if item['type'] == 'blob'}

    def file(self, repository, commit, path):
        safe_path(path)
        encoded = urllib.parse.quote(path, safe='/')
        return self.read(f'https://raw.githubusercontent.com/{repository}/{commit}/{encoded}')


def selected(source, tree):
    explicit = set(source['paths'])
    return {safe_path(path): sha for path, sha in tree.items()
            if path in explicit or (any(path.startswith(prefix) for prefix in source['prefixes'])
                                   and PurePosixPath(path).suffix in {'.rs', '.js', '.cjs', '.mjs', '.json', '.md'})}


def fetch_verified(client, source, commit, path, expected):
    if expected is None:
        return b''
    data = client.file(source['repository'], commit, path)
    if blob_hash(data) != expected:
        raise ValueError(f'Upstream blob mismatch: {source["id"]}/{path}')
    return data


def scan(config, state, client, root=ROOT):
    """No filesystem mutations; finish every read before preparing an update."""
    updates, records = [], {}
    for source in config['sources']:
        source_id = source['id']
        previous = state['sources'][source_id]
        commit = client.head(source['repository'], source['branch'])
        latest = selected(source, client.tree(source['repository'], commit))
        old_commit = previous.get('reviewed_commit')
        old = previous.get('files')
        if old is None:
            old = latest if old_commit == commit else selected(source, client.tree(source['repository'], old_commit))
        changes = []
        for path in sorted(set(old) | set(latest)):
            before, after = old.get(path), latest.get(path)
            if before == after:
                continue
            safe_path(path)
            if old_commit:
                original = fetch_verified(client, source, old_commit, path, before)
            elif before is None:
                original = b''
            else:
                local = root / path
                original = local.read_bytes() if local.is_file() else None
                if original is not None and blob_hash(original) != before:
                    original = None
            current = fetch_verified(client, source, commit, path, after)
            patch = None
            if original is not None:
                lines = difflib.unified_diff(
                    original.decode('utf-8').splitlines(keepends=True),
                    current.decode('utf-8').splitlines(keepends=True),
                    fromfile='a/' + path, tofile='b/' + path)
                patch = ''.join(line if line.endswith('\n') else line + '\n\\ No newline at end of file\n'
                                for line in lines)
            changes.append({'path': path, 'before': before, 'after': after,
                            'patch': patch, 'baseline_available': original is not None})
        records[source_id] = {'reviewed_commit': commit, 'files': latest}
        if changes:
            updates.append({'id': source_id, 'repository': source['repository'],
                            'before_commit': old_commit, 'after_commit': commit, 'changes': changes})
    return updates, {'schema': 1, 'sources': records}


def prepare(root, updates, state, config):
    if not updates:
        return None
    folder = root / 'extensions/updates'
    identity = [(u['id'], u['after_commit']) for u in updates]
    digest = hashlib.sha256(json.dumps(identity).encode()).hexdigest()[:16]
    # One current review bundle, rather than an ever-growing source archive.
    patch_root = folder / 'patches'
    if patch_root.exists():
        import shutil
        shutil.rmtree(patch_root)
    lines = ['# Upstream source review', '',
             'Review-only proposal. **No provider implementation was updated, imported or executed.**',
             'Merging this PR records reviewed upstream versions; it does not mark the ports as updated.',
             'Review and port applicable changes in this PR before merging, or close it to retain the baseline.', '',
             '## Validation', '',
             '- Local Python watcher/publisher tests run in the workflow.',
             '- Upstream code is read as data only. Upstream tests are not executed.',
             '- Upstream changes require manual adaptation to Rust/configuration and native parity tests.',
             '- No merge, auto-merge, package signing, release or deployment is performed.', '']
    for update in updates:
        repository, commit = update['repository'], update['after_commit']
        lines += [f'## {update["id"]}', '', f'Repository: https://github.com/{repository}',
                  f'Proposed review commit: `{commit}`',
                  f'Previous upstream commit: `{update["before_commit"] or "local pinned native-file baseline"}`', '']
        for change in update['changes']:
            path = change['path']
            status = 'added' if change['before'] is None else 'removed' if change['after'] is None else 'modified'
            lines.append(f'- `{path}`: {status}.')
            lines.append(f'  Blob: `{change["before"] or "absent"}` → `{change["after"] or "absent"}`.')
            if change['patch'] is not None:
                destination = patch_root / update['id'] / (path + '.patch')
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(change['patch'])
            else:
                lines.append('  Original content unavailable locally; inspect the pinned upstream file manually. No synthetic diff was generated.')
            if change['after'] is not None:
                lines.append(f'  Source: https://github.com/{repository}/blob/{commit}/{path}')
        lines.append('')
    folder.joinpath('reports').mkdir(parents=True, exist_ok=True)
    folder.joinpath('reports/latest.md').write_text('\n'.join(lines) + '\n')
    folder.joinpath('state.json').write_text(json.dumps(state, indent=2, sort_keys=True) + '\n')
    result = {'branch': 'automation/extension-updates-' + digest, 'base': config['target_branch'],
              'title': 'chore(extensions): review upstream source updates',
              'body_file': 'extensions/updates/reports/latest.md'}
    folder.joinpath('.cache').mkdir(exist_ok=True)
    folder.joinpath('.cache/proposal.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    config = read_json(HERE / 'watch.json')
    today = dt.datetime.now(dt.timezone.utc).date()
    force = args.force or os.environ.get('WATCH_FORCE') == 'true'
    proposal = None
    if not force and not due(config, today):
        print('Not a scheduled fortnight; no upstream requests made.')
    else:
        updates, state = scan(config, read_json(HERE / 'state.json'), GitHub())
        print(json.dumps({'changed_sources': [u['id'] for u in updates],
                          'changed_files': sum(len(u['changes']) for u in updates), 'dry_run': args.dry_run}))
        if not args.dry_run:
            proposal = prepare(ROOT, updates, state, config)
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a') as stream:
            stream.write('proposal=' + ('true' if proposal else 'false') + '\n')


if __name__ == '__main__':
    main()
