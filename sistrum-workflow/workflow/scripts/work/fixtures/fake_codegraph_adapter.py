#!/usr/bin/env python3
"""MOCK of codegraph_adapter.py for the mocked tests: same protocol, no CodeGraph.

Behaviour is chosen with FAKE_CODEGRAPH: unset (normal), missing, fail, garbage, hang,
touch (edits FAKE_CODEGRAPH_TOUCH during extraction). FAKE_CODEGRAPH_VERSION sets the
reported version; FAKE_CODEGRAPH_LOG appends one line per extraction.
"""
import json
import os
import re
import sys
import time
from pathlib import Path


def info():
    if os.environ.get('FAKE_CODEGRAPH') == 'missing':
        return {'schema': 1, 'available': False, 'package': '@colbymchenry/codegraph', 'reason': 'fake: @colbymchenry/codegraph is not installed'}
    return {'schema': 1, 'available': True, 'package': '@colbymchenry/codegraph', 'python': 'fake',
            'version': os.environ.get('FAKE_CODEGRAPH_VERSION', '1.6.2'), 'grammars': {'tree-sitter': 'fake'}}


def ident(path, *names):
    return re.sub(r'[^a-z0-9]+', '_', '/'.join([path.rsplit('.', 1)[0], *names]).lower()).strip('_')


def extract(request, out):
    mode = os.environ.get('FAKE_CODEGRAPH', '')
    data = json.loads(Path(request).read_text())
    root, files = Path(data['root']), data['files']
    if os.environ.get('FAKE_CODEGRAPH_LOG'):
        with open(os.environ['FAKE_CODEGRAPH_LOG'], 'a') as log:
            log.write(f'extract {len(files)}\n')
    if mode == 'fail':
        print('fake extractor crashed', file=sys.stderr)
        return 1
    if mode == 'garbage':
        Path(out).write_text('{"schema": 1, "nodes": "not a list"}')
        return 0
    if mode == 'hang':
        time.sleep(60)
    if mode == 'touch':
        target = root / os.environ['FAKE_CODEGRAPH_TOUCH']
        target.write_text(target.read_text() + '\n// edited during extraction\n')
    nodes, edges, functions = [], [], {}
    for rel in files:
        text = (root / rel).read_text()
        file_id = ident(rel)
        nodes.append({'id': file_id, 'label': rel.rsplit('/', 1)[-1], 'source_file': rel, 'source_location': 'L1'})
        current = None
        for number, line in enumerate(text.split('\n'), 1):
            found = re.match(r'\s*(?:abstract\s+|data\s+)?class\s+(\w+)', line)
            if found:
                current = ident(rel, found.group(1))
                nodes.append({'id': current, 'label': found.group(1), 'source_file': rel, 'source_location': f'L{number}'})
                edges.append({'source': file_id, 'target': current, 'relation': 'defines', 'confidence': 'EXTRACTED',
                              'source_file': rel, 'source_location': f'L{number}'})
            found = re.match(r'\s*(?:private\s+)?fun\s+(\w+)\s*\(', line) or re.match(r'  [\w<>?]+\s+(\w+)\s*\(', line)
            if found:
                name = found.group(1)
                node = ident(rel, *(n for n in (current and current.split('_')[-1], name) if n))
                kotlin = rel.endswith('.kt')
                nodes.append({'id': node, 'label': f'.{name}()' if kotlin else name, 'source_file': rel,
                              'source_location': f'L{number}'})
                if kotlin and current:
                    edges.append({'source': current, 'target': node, 'relation': 'method', 'confidence': 'EXTRACTED',
                                  'source_file': rel, 'source_location': f'L{number}'})
                functions.setdefault(name, []).append((node, rel, number))
    for rel in files:
        if not rel.endswith('.kt'):
            continue
        caller = None
        for number, line in enumerate((root / rel).read_text().split('\n'), 1):
            found = re.match(r'\s*(?:private\s+)?fun\s+(\w+)\s*\(', line)
            if found:
                caller = next(n for n, f, l in functions[found.group(1)] if f == rel and l == number)
            for name in re.findall(r'\b(\w+)\s*\(', line):
                for target, file, _line in functions.get(name, []):
                    if caller and target != caller and not (found and found.group(1) == name):
                        edges.append({'source': caller, 'target': target, 'relation': 'calls',
                                      'confidence': 'EXTRACTED' if file == rel else 'INFERRED',
                                      'source_file': rel, 'source_location': f'L{number}'})
    Path(out).write_text(json.dumps({'schema': 1, 'tool': info(), 'nodes': nodes, 'edges': edges,
                                     'coverage': [{'file': f, 'status': 'indexed', 'errors': [], 'symbols': 0} for f in files],
                                     'stats': {'extracted_sources': len(files)}}))
    return 0


if __name__ == '__main__':
    if sys.argv[1] == 'version':
        print(json.dumps(info()))
        sys.exit(0)
    sys.exit(extract(sys.argv[sys.argv.index('--request') + 1], sys.argv[sys.argv.index('--out') + 1]))
