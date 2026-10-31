#!/usr/bin/env python3
"""Thin process boundary around Graphify's AST extraction, used by workmap.py.

Runs in whichever interpreter has Graphify installed, so it imports nothing from the
workflow. Two commands, JSON on stdout or in the --out file:

  version                                   what is installed (no Graphify import)
  extract --request R --out O               graphify.extract() over the request's files

Only local AST extraction is used (`graphify.extract`, exported by the package). No
LLM, network, clustering, report, hooks or skill installation. The caller sets
GRAPHIFY_OUT (an absolute directory for Graphify's cache) and PYTHONHASHSEED=0.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import sys
import tempfile
from importlib import metadata, util
from pathlib import Path

PACKAGE = 'graphifyy'  # PyPI distribution name; the import name is `graphify`
GRAMMARS = ('tree-sitter', 'tree-sitter-kotlin')
SCHEMA = 1


def version() -> dict:
    info = {'schema': SCHEMA, 'package': PACKAGE, 'python': platform.python_version()}
    try:
        info['version'] = metadata.version(PACKAGE)
    except metadata.PackageNotFoundError:
        return {**info, 'available': False, 'reason': f'{PACKAGE} is not installed for {sys.executable}'}
    if util.find_spec('graphify') is None:
        return {**info, 'available': False, 'reason': 'the graphify module cannot be imported'}
    grammars = {}
    for name in GRAMMARS:
        try:
            grammars[name] = metadata.version(name)
        except metadata.PackageNotFoundError:
            grammars[name] = None
    return {**info, 'available': True, 'grammars': grammars}


def write_json(path: Path, data: dict) -> None:
    handle, temporary = tempfile.mkstemp(prefix='.adapter.', dir=path.parent)
    with os.fdopen(handle, 'w', encoding='utf-8') as output:
        json.dump(data, output)
    os.replace(temporary, path)


def extract(request_path: Path, out: Path) -> int:
    request = json.loads(request_path.read_text(encoding='utf-8'))
    root = Path(request['root']).resolve()
    cache = os.environ.get('GRAPHIFY_OUT')
    if not cache or not Path(cache).is_absolute():
        print('GRAPHIFY_OUT must be an absolute cache directory', file=sys.stderr)
        return 2
    info = version()
    if not info['available']:
        print(info['reason'], file=sys.stderr)
        return 3
    import graphify  # noqa: E402  (heavy; only after the environment is checked)

    files = [root / path for path in request['files']]
    result = graphify.extract(files, cache_root=Path(cache), root=root,
                              parallel=bool(request.get('parallel', True)))
    stats = {key: value for key, value in result.items() if isinstance(value, (int, float))}
    write_json(out, {'schema': SCHEMA, 'tool': info, 'nodes': result.get('nodes', []),
                     'edges': result.get('edges', []), 'stats': stats})
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('version')
    command = sub.add_parser('extract')
    command.add_argument('--request', type=Path, required=True)
    command.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.action == 'version':
        print(json.dumps(version()))
        return 0
    return extract(args.request, args.out)


if __name__ == '__main__':
    sys.exit(main())
