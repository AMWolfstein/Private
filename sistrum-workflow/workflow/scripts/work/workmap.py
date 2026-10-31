"""Code map and bounded task context for the workflow tool.

The map joins three kinds of facts, each labelled with provenance and confidence:

* extracted: Graphify's local AST extraction (symbols, Kotlin calls and references) and
  this module's own pattern scans (Dart/Kotlin imports, platform-channel endpoints);
* declared: human-maintained declarations (workflow/work/architecture.json, the
  assurance.json of change records, the wrappers listed in workflow/work/map.json);
* inferred: heuristics (name-convention tests, single-channel attribution, rule checks
  derived from imports). Never presented as confirmed facts.

Generated data lives in .work/map/ and is rebuilt as one complete snapshot, published
atomically under a lock. Declarations are only read, never written. Freshness is a digest
of the selected sources, the configuration, the declarations and the extractor version.
Standard library only; Graphify runs in its own process through graphify_adapter.py.
"""
from __future__ import annotations

import bisect
import fnmatch
import hashlib
import math
import importlib.util
import json
import os
import posixpath
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from worklib import Blocked, atomic_write, domains_for, is_test, now, snapshot

SCHEMA = 1
CONFIG = 'workflow/work/map.json'
ARCHITECTURE = 'workflow/work/architecture.json'
CHECKS = 'workflow/work/checks.json'
CHANGES = 'workflow/work/changes'
HERE = Path(__file__).resolve().parent
ADAPTER = HERE / 'graphify_adapter.py'
TEXT_LIMIT = 1_000_000  # bytes; larger files are not pattern-scanned (reported)
FACTS = ('extracted', 'declared', 'inferred')
STOPWORDS = set('''a an and are as at be but by can do does for from has have how in into is it its
make makes new not of on or should so that the then this to update use when where which while with
without add change changes fix bug issue code file files feature implement support work works'''.split())


# ------------------------------------------------------------------ helpers

def map_dir(root: Path) -> Path:
    return root / '.work/map'


def sha(data: bytes | str) -> str:
    return hashlib.sha256(data.encode() if isinstance(data, str) else data).hexdigest()


def read_bytes(path: Path) -> bytes:
    return path.read_bytes() if path.is_file() else b'<missing>'


def fact(kind: str, via: str, confidence: str) -> dict:
    return {'fact': kind, 'via': via, 'confidence': confidence}


def matches(path: str, patterns) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


class Lines:
    """Offset to 1-based line number."""

    def __init__(self, text: str):
        self.starts = [0] + [m.end() for m in re.finditer('\n', text)]

    def __call__(self, offset: int) -> int:
        return bisect.bisect_right(self.starts, offset)


_TOKENS = re.compile(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\''
                     r'|/\*[\s\S]*?\*/|//[^\n]*')


def strip_comments(text: str) -> str:
    """Blank comments (keeping their newlines) and leave string literals in place."""
    return _TOKENS.sub(lambda m: '\n' * m.group(0).count('\n') if m.group(0)[0] == '/' else m.group(0), text)


def literal(token: str | None) -> str | None:
    if not token or len(token) < 2 or token[0] not in '\'"' or token[-1] != token[0]:
        return None
    return token[1:-1]


def match_close(text: str, start: int, opening: str = '{', closing: str = '}') -> int:
    """Index after the bracket closing the one at `start`, skipping string literals."""
    depth, index = 0, start
    while index < len(text):
        char = text[index]
        if char in '"\'':
            found = _TOKENS.match(text, index)
            index = found.end() if found else index + 1
            continue
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return len(text)


def depth_at(text: str) -> list[int]:
    """Bracket depth before each character, string literals skipped."""
    depths, depth, index = [0] * (len(text) + 1), 0, 0
    while index < len(text):
        char = text[index]
        if char in '"\'':
            found = _TOKENS.match(text, index)
            end = found.end() if found else index + 1
            for position in range(index, end):
                depths[position] = depth
            index = end
            continue
        depths[index] = depth
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
        index += 1
    depths[len(text)] = depth
    return depths


# ------------------------------------------------------------ configuration

DEFAULT_CONFIG = {
    'version': 1,
    'extractor': {'name': 'graphify', 'package': 'graphifyy', 'version': '0.9.97', 'enabled': True,
                  'allow_unverified': False, 'timeout': 900},
    'corpus': {'include': ['*.dart', '*.kt'], 'exclude': [], 'exceptions': []},
    'bridges': {'dart_channel_types': ['MethodChannel', 'OptionalMethodChannel', 'EventChannel',
                                       'BasicMessageChannel'],
                'dart_invoke_methods': ['invokeMethod', 'invokeMapMethod', 'invokeListMethod'],
                'dart_wrappers': [],
                'kotlin_channel_types': ['MethodChannel', 'EventChannel', 'BasicMessageChannel']},
    'context': {'budget_tokens': 2500, 'entry_files': 8, 'per_section': 12, 'excerpt_lines': 10,
                'max_excerpts': 3, 'fallback_hits': 20},
}


def load_config(root: Path) -> dict:
    path = root / CONFIG
    if not path.is_file():
        raise Blocked(f'{CONFIG} is missing')
    try:
        data = json.loads(path.read_text())
    except ValueError as error:
        raise Blocked(f'{CONFIG} is not valid JSON: {error}') from error
    if not isinstance(data, dict) or data.get('version') != 1:
        raise Blocked(f'{CONFIG}: version must be 1')
    config = {}
    for section, defaults in DEFAULT_CONFIG.items():
        value = data.get(section, defaults)
        if isinstance(defaults, dict):
            if not isinstance(value, dict):
                raise Blocked(f'{CONFIG}: "{section}" must be an object')
            unknown = set(value) - set(defaults)
            if unknown:
                raise Blocked(f'{CONFIG}: unknown {section} keys {sorted(unknown)}')
            value = {**defaults, **value}
        config[section] = value
    for key in ('include', 'exclude', 'exceptions'):
        if not isinstance(config['corpus'][key], list) or not all(isinstance(v, str) for v in config['corpus'][key]):
            raise Blocked(f'{CONFIG}: corpus.{key} must be a list of glob strings')
    for wrapper in config['bridges']['dart_wrappers']:
        if not (isinstance(wrapper, dict) and isinstance(wrapper.get('function'), str)
                and isinstance(wrapper.get('channel'), str)):
            raise Blocked(f'{CONFIG}: bridges.dart_wrappers entries need "function" and "channel"')
    for key, value in config['context'].items():
        if not isinstance(value, int) or value <= 0:
            raise Blocked(f'{CONFIG}: context.{key} must be a positive integer')
    return config


def adapter_path() -> Path:
    override = os.environ.get('WORK_MAP_ADAPTER')
    return Path(override).resolve() if override else ADAPTER


def interpreter() -> tuple[list[str] | None, str]:
    """The Python that has Graphify, and how it was found. Never a stored machine path."""
    override = os.environ.get('WORK_GRAPHIFY_PYTHON')
    if override:
        return shlex.split(override), 'WORK_GRAPHIFY_PYTHON'
    if importlib.util.find_spec('graphify') is not None:
        return [sys.executable], 'current interpreter'
    executable = shutil.which('graphify')
    if executable:
        try:
            first = Path(executable).read_text(errors='replace').split('\n', 1)[0]
        except OSError:
            first = ''
        if first.startswith('#!'):
            argv = shlex.split(first[2:].strip())
            if argv and Path(argv[0]).is_file():
                return argv, f'shebang of {executable}'
    return None, 'no interpreter with graphify found'


_TOOL_CACHE: dict[str, dict] = {}


def tool_info(config: dict) -> dict:
    """Extractor availability, checked once per process for the same environment and pin."""
    key = json.dumps([config['extractor'], sorted(os.environ.items()), str(adapter_path())], sort_keys=True)
    if key not in _TOOL_CACHE:
        _TOOL_CACHE[key] = probe_tool(config)
    return dict(_TOOL_CACHE[key])


def probe_tool(config: dict) -> dict:
    """`status` is ready, unavailable, unverified or disabled."""
    pinned = config['extractor']
    base = {'name': 'graphify', 'package': pinned['package'], 'pinned': pinned['version']}
    if not pinned['enabled'] or os.environ.get('WORK_MAP_STRUCTURE') == 'off':
        where = 'WORK_MAP_STRUCTURE=off' if os.environ.get('WORK_MAP_STRUCTURE') == 'off' else CONFIG
        return {**base, 'status': 'disabled', 'reason': f'structure extraction disabled by {where}'}
    argv, found = interpreter()
    install = f'pip install {pinned["package"]}=={pinned["version"]}'
    if argv is None:
        return {**base, 'status': 'unavailable', 'reason': f'{found}; {install} or set WORK_GRAPHIFY_PYTHON'}
    try:
        done = subprocess.run([*argv, str(adapter_path()), 'version'], capture_output=True, timeout=120,
                              env={**os.environ, 'PYTHONHASHSEED': '0'})
        info = json.loads(done.stdout.decode() or 'null')
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        return {**base, 'status': 'unavailable', 'reason': f'adapter version check failed: {error}'}
    if not isinstance(info, dict) or not info.get('available'):
        reason = info.get('reason') if isinstance(info, dict) else done.stderr.decode(errors='replace')[-300:]
        return {**base, 'status': 'unavailable', 'reason': f'{reason}; {install}'}
    tool = {**base, 'version': info.get('version'), 'python': info.get('python'),
            'grammars': info.get('grammars', {}), 'argv': argv, 'found': found}
    if info.get('version') != pinned['version'] and not pinned['allow_unverified']:
        return {**tool, 'status': 'unverified',
                'reason': f'{pinned["package"]} {info.get("version")} is installed, {pinned["version"]} is pinned; '
                          f'{install}, or run the smoke test and update the pin in {CONFIG}'}
    return {**tool, 'status': 'ready'}


# ----------------------------------------------------------------- inputs

def corpus_of(listing: dict, config: dict) -> tuple[list[str], dict]:
    corpus = config['corpus']
    selected, excluded = [], 0
    for path, (mode, _blob) in sorted(listing.items()):
        if mode == '120000' or not matches(path, corpus['include']):
            continue
        if matches(path, corpus['exclude']) and not matches(path, corpus['exceptions']):
            excluded += 1
            continue
        selected.append(path)
    return selected, {'excluded_by_pattern': excluded}


def aux_inputs(listing: dict, selected: set[str]) -> list[str]:
    """Inputs read besides the corpus: package manifests (Dart import resolution), the
    Graphify project rc file, and non-code test fixtures (bridge test candidates)."""
    aux = []
    for path in sorted(listing):
        if path in selected or listing[path][0] == '120000':
            continue
        name = path.rsplit('/', 1)[-1]
        if name in ('pubspec.yaml', '.graphifyrc') or (is_test(path) and not path.startswith(('workflow/', '.work/'))):
            aux.append(path)
    return aux


def declaration_inputs(root: Path) -> list[tuple[str, bytes]]:
    """Declaration files. A change's phase is read when a packet is rendered, so advancing a
    phase does not make the map stale."""
    items = [(ARCHITECTURE, read_bytes(root / ARCHITECTURE))]
    base = root / CHANGES
    if base.is_dir():
        for folder in sorted(p for p in base.iterdir() if (p / 'state.json').is_file()):
            items.append((f'{folder.name}/assurance.json', read_bytes(folder / 'assurance.json')))
    return items


def phase_of(root: Path, change: str) -> tuple[str, str, str]:
    """(phase, review label, confidence) of a change record, read now."""
    base = root / CHANGES
    folders = [p for p in base.glob('*') if p.is_dir() and (p.name == change or p.name.split('-', 1)[0] == change.zfill(3))]
    try:
        phase = json.loads((folders[0] / 'state.json').read_text()).get('phase') if len(folders) == 1 else None
    except (OSError, ValueError):
        phase = None
    if phase is None:
        return 'unknown', 'change record unreadable', 'low'
    if phase in ('tasks', 'build', 'review', 'ship', 'done'):
        return phase, 'accepted plan', 'high'
    return str(phase), 'draft (plan not accepted)', 'medium'


def inputs(root: Path, config: dict, tool: dict) -> dict:
    """Everything a map depends on, hashed by component."""
    _tree, listing = snapshot(root, listing=True)
    corpus, counts = corpus_of(listing, config)
    aux = aux_inputs(listing, set(corpus))
    files = {path: listing[path][1] for path in corpus}
    corpus_digest = sha(json.dumps([[p, listing[p][1]] for p in corpus + aux]))
    config_digest = sha(b''.join(read_bytes(root / p) for p in (CONFIG, CHECKS))
                        + read_bytes(Path(__file__)) + read_bytes(adapter_path()))
    declarations = sha(b''.join(name.encode() + b'\0' + data for name, data in declaration_inputs(root)))
    tool_key = {k: tool.get(k) for k in ('status', 'package', 'pinned', 'version', 'python', 'grammars')}
    components = {'corpus': corpus_digest, 'config': config_digest, 'declarations': declarations,
                  'tool': sha(json.dumps(tool_key, sort_keys=True))}
    return {'components': components, 'digest': sha(json.dumps(components, sort_keys=True)),
            'files': files, 'aux': aux, 'listing': listing, 'counts': counts}


# ------------------------------------------------------------------ state

def read_state(root: Path) -> dict | None:
    path = map_dir(root) / 'state.json'
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and data.get('schema') == SCHEMA else None


def load_map(root: Path, state: dict | None = None) -> dict | None:
    """The published map, or None when absent or not the one state.json describes."""
    state = state or read_state(root)
    path = map_dir(root) / 'map.json'
    if not state or not state.get('map_sha256') or not path.is_file():
        return None
    raw = path.read_bytes()
    if sha(raw) != state['map_sha256']:
        return None
    data = json.loads(raw)
    return data if data.get('meta', {}).get('digest') == state.get('digest') else None


def map_status(root: Path, config: dict | None = None, tool: dict | None = None) -> dict:
    """Read-only freshness: current, stale, missing or invalid, with the reasons."""
    config = config or load_config(root)
    tool = tool or tool_info(config)
    now_inputs = inputs(root, config, tool)
    state = read_state(root)
    result = {'tool': {k: v for k, v in tool.items() if k != 'argv'}, 'digest': now_inputs['digest'],
              'components': now_inputs['components'], 'files': len(now_inputs['files'])}
    if state and state.get('last_failure'):
        result['last_failure'] = state['last_failure']
    if not state or not state.get('map_sha256'):
        return {**result, 'state': 'missing', 'reasons': ['no map has been built: run work.py map update']}
    path = map_dir(root) / 'map.json'
    if not path.is_file() or sha(path.read_bytes()) != state['map_sha256']:
        return {**result, 'state': 'invalid', 'reasons': ['map.json does not match state.json; run work.py map update']}
    result.update({'built_at': state.get('built_at'), 'structure': state.get('structure'),
                   'map_digest': state.get('digest')})
    if state.get('digest') == now_inputs['digest']:
        return {**result, 'state': 'current', 'reasons': []}
    reasons, old = [], state.get('files', {})
    new = now_inputs['files']
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    modified = sorted(p for p in set(new) & set(old) if new[p] != old[p])
    if added or removed or modified:
        reasons.append(f'source files changed: {len(added)} added, {len(removed)} removed, {len(modified)} modified')
        result['changed'] = {'added': added[:20], 'removed': removed[:20], 'modified': modified[:20]}
    for name in ('corpus', 'config', 'declarations', 'tool'):
        if state.get('components', {}).get(name) != now_inputs['components'][name]:
            if name != 'corpus' or not (added or removed or modified):
                reasons.append({'corpus': 'manifests, fixtures or rc file changed',
                                'config': f'{CONFIG}, {CHECKS} or the map code changed',
                                'declarations': f'{ARCHITECTURE} or a change record assurance/phase changed',
                                'tool': 'extractor availability or version changed'}[name])
    return {**result, 'state': 'stale', 'reasons': reasons}


@contextmanager
def map_lock(root: Path, timeout: float):
    """Exclusive, non-blocking lock with a deadline: fcntl on POSIX, msvcrt on Windows (not tested here)."""
    path = map_dir(root) / 'update.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        import fcntl
        windows = None
    except ImportError:
        import msvcrt  # Windows: locks the first byte of the file
        fcntl, windows = None, msvcrt
    with open(path, 'a+') as handle:
        deadline = time.monotonic() + timeout
        while True:
            try:
                if fcntl:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                else:
                    handle.seek(0)
                    windows.locking(handle.fileno(), windows.LK_NBLCK, 1)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise Blocked('another map update holds .work/map/update.lock; retry when it finishes')
                time.sleep(0.1)
        try:
            yield
        finally:
            if fcntl:
                fcntl.flock(handle, fcntl.LOCK_UN)
            else:
                handle.seek(0)
                windows.locking(handle.fileno(), windows.LK_UNLCK, 1)


def lock_timeout() -> float:
    try:
        return float(os.environ.get('WORK_MAP_LOCK_TIMEOUT', '600'))
    except ValueError:
        return 600.0


def update(root: Path, force: bool = False, timeout: float | None = None) -> dict:
    """Publish a complete map for the current inputs, or keep the last one and say why."""
    config = load_config(root)
    with map_lock(root, lock_timeout() if timeout is None else timeout):
        tool = tool_info(config)
        before = inputs(root, config, tool)
        state = read_state(root)
        if not force and state and state.get('digest') == before['digest'] and load_map(root, state):
            return {'status': 'PASS', 'map': 'current', 'rebuilt': False, 'structure': state.get('structure')}
        started = time.monotonic()
        try:
            if force:
                shutil.rmtree(map_dir(root) / 'graphify', ignore_errors=True)
            data = build(root, config, tool, before)
            after = inputs(root, config, tool)
            if after['digest'] != before['digest']:
                raise Blocked('sources changed while the map was being built; run work.py map update again')
        except Blocked as error:
            record_failure(root, state, str(error), before['digest'])
            raise
        except Exception as error:  # an extractor bug must not look like a fresh map
            record_failure(root, state, f'{type(error).__name__}: {error}', before['digest'])
            raise Blocked(f'map update failed: {type(error).__name__}: {error}') from error
        data['meta']['seconds'] = round(time.monotonic() - started, 2)
        encoded = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()
        atomic_write(map_dir(root) / 'map.json', encoded)
        new_state = {'schema': SCHEMA, 'digest': before['digest'], 'components': before['components'],
                     'files': before['files'], 'structure': data['meta']['structure'],
                     'tool': data['meta']['tool'], 'built_at': data['meta']['built_at'],
                     'map_sha256': sha(encoded), 'counts': data['meta']['counts'], 'last_failure': None}
        atomic_write(map_dir(root) / 'state.json', json.dumps(new_state, indent=1) + '\n')
        return {'status': 'PASS', 'map': 'current', 'rebuilt': True, 'structure': data['meta']['structure'],
                'counts': data['meta']['counts'], 'seconds': data['meta']['seconds'],
                'problems': data['problems'][:20]}


def record_failure(root: Path, state: dict | None, reason: str, digest: str) -> None:
    """Keep the last valid map; remember that refreshing it failed."""
    kept = dict(state) if state else {'schema': SCHEMA}
    kept['last_failure'] = {'at': now(), 'reason': reason[:2000], 'for_digest': digest}
    atomic_write(map_dir(root) / 'state.json', json.dumps(kept, indent=1) + '\n')


def ensure_current(root: Path) -> dict:
    """Refresh a stale map before a graph-dependent step. Raises Blocked when it cannot."""
    status = map_status(root)
    if status['state'] != 'current':
        update(root)
        status = map_status(root)
        if status['state'] != 'current':
            raise Blocked('code map is still not current after updating: ' + '; '.join(status['reasons']))
    return status


def gate_problems(root: Path) -> list[str]:
    try:
        status = map_status(root)
    except Blocked as error:
        return [f'code map unavailable: {error}']
    if status['state'] == 'current':
        return []
    problems = [f'code map is {status["state"]} ({"; ".join(status["reasons"])}); run work.py map update']
    if status.get('last_failure'):
        problems.append('last map update failed: ' + status['last_failure']['reason'][:300])
    return problems


def round_record(root: Path) -> dict:
    status = ensure_current(root)
    return {'digest': status['digest'], 'corpus': status['components']['corpus'],
            'structure': (status.get('structure') or {}).get('status')}


def status_line(root: Path) -> str:
    try:
        status = map_status(root)
    except Blocked as error:
        return f'Code map: unavailable ({error})'
    structure = status.get('structure') or {}
    tool = status['tool']
    label = (f'graphify {tool.get("version")}' if structure.get('status') == 'graphify'
             else f'structure {structure.get("status", "?")}')
    text = f'Code map: {status["state"]}'
    if status['state'] != 'missing':
        text += f' ({status["files"]} files, {label})'
    if status['reasons']:
        text += ': ' + '; '.join(status['reasons'])
    if status.get('last_failure'):
        text += f' | last update FAILED at {status["last_failure"]["at"]}'
    if tool['status'] != 'ready':
        text += f' | extractor {tool["status"]}: {tool.get("reason", "")}'
    return text


# ------------------------------------------------------------- extraction

def build(root: Path, config: dict, tool: dict, current: dict) -> dict:
    files = sorted(current['files'])
    texts, problems = {}, []
    for path in files + [p for p in current['aux'] if p.endswith(('pubspec.yaml',))]:
        raw = (root / path).read_bytes()
        if len(raw) > TEXT_LIMIT:
            problems.append(f'{path}: larger than {TEXT_LIMIT} bytes, not pattern-scanned')
            continue
        texts[path] = raw.decode('utf-8', errors='replace')
    meta_structure = {'status': 'empty', 'note': 'no source file matches the corpus patterns'}
    symbols, edges, stats = [], [], {}
    if files and tool['status'] == 'ready':
        raw = run_adapter(root, files, config, tool)
        symbols, edges, extra = normalize(raw, set(files))
        problems += extra
        stats = raw.get('stats', {})
        if stats.get('failed_sources'):
            problems.append(f'graphify failed on {stats["failed_sources"]} file(s); see .work/map/logs/')
        meta_structure = {'status': 'graphify', 'note': 'symbols, calls and references from Graphify; Dart '
                          'declarations are regex-based, Dart calls are inferred by name; Dart and Kotlin imports and channels '
                          'come from pattern scans'}
    elif files:
        meta_structure = {'status': tool['status'], 'note': tool.get('reason', '')}
    file_info = {path: {'lang': language(path), 'test': is_test(path), 'blob': current['files'][path]}
                 for path in files}
    deps, kotlin_index, dep_problems = dependencies(root, texts, file_info, current['listing'], config)
    problems += dep_problems
    bridges = scan_bridges(texts, file_info, config)
    attach_bridge_tests(root, bridges, current['aux'], file_info, texts)
    name_edges, name_notes = dart_name_calls(texts, symbols, file_info)
    edges += name_edges
    problems += name_notes
    tests = link_tests(file_info, deps, symbols, edges)
    declarations = load_declarations(root, file_info, deps, bridges, problems)
    tool_public = {k: v for k, v in tool.items() if k not in ('argv',)}
    meta = {'schema': SCHEMA, 'digest': current['digest'], 'components': current['components'],
            'built_at': now(), 'tool': tool_public, 'structure': meta_structure, 'stats': stats,
            'counts': {'files': len(files), 'symbols': len(symbols), 'edges': len(edges), 'deps': len(deps),
                       'channels': len(bridges['channels']), **current['counts']}}
    return {'meta': meta, 'files': file_info, 'symbols': symbols, 'edges': edges, 'deps': deps,
            'kotlin_index': kotlin_index, 'bridges': bridges, 'tests': tests,
            'declarations': declarations, 'problems': problems}


LANGUAGE_BY_SUFFIX = {'.dart': 'dart', '.kt': 'kotlin', '.kts': 'kotlin', '.rs': 'rust', '.c': 'c', '.h': 'c',
                      '.cpp': 'cpp', '.cc': 'cpp', '.cxx': 'cpp', '.hpp': 'cpp', '.java': 'java', '.py': 'python',
                      '.swift': 'swift', '.sh': 'shell', '.bash': 'shell', '.gradle': 'gradle'}


# Calls that name too little to point at one declaration.
CALL_STOP = {'build', 'toString', 'setState', 'dispose', 'initState', 'then', 'of', 'call', 'get', 'set', 'add',
             'remove', 'length', 'map', 'where', 'first', 'last', 'isEmpty', 'isNotEmpty', 'print', 'main', 'super',
             'this', 'new', 'if', 'for', 'while', 'switch', 'catch', 'return', 'await', 'async', 'watch', 'read',
             'listen', 'emit', 'value', 'name', 'id', 'copyWith', 'fromJson', 'toJson', 'equals', 'hashCode',
             'close', 'start', 'stop', 'run', 'update', 'load', 'open', 'create', 'init', 'reset', 'clear', 'send'}
CALL_TOKEN = re.compile(r'\b([A-Za-z_]\w*)\s*\(')


def dart_name_calls(texts: dict, symbols: list, file_info: dict) -> tuple[list[dict], list[str]]:
    """Dart call edges inferred by name. Graphify emits none for Dart, so a call `f(` counts as a call to
    the declaration(s) named `f` in the corpus when the name is distinctive. Always labelled inferred; the
    caller is the nearest declaration above the call in the same file."""
    by_name: dict[str, list[dict]] = {}
    for symbol in symbols:
        if symbol['lang'] == 'dart' and symbol['name'] not in CALL_STOP and len(symbol['name']) > 2:
            by_name.setdefault(symbol['name'], []).append(symbol)
    per_file: dict[str, list[dict]] = {}
    for symbol in symbols:
        if symbol['lang'] == 'dart':
            per_file.setdefault(symbol['file'], []).append(symbol)
    edges, skipped = [], 0
    for path in sorted(per_file):
        if path not in texts or file_info.get(path, {}).get('lang') != 'dart':
            continue
        clean = strip_comments(texts[path])
        declared = sorted(per_file[path], key=lambda s: s['line'] or 0)
        line_of_call = Lines(clean)
        seen = set()
        for found in CALL_TOKEN.finditer(clean):
            name = found.group(1)
            targets = by_name.get(name)
            if not targets:
                continue
            # Only unqualified calls and this.x() are attributed: `Other.f(` or `value.f(` usually name a
            # member of a type the map does not know, and matching them by name produced false edges.
            before = clean[max(0, found.start() - 5):found.start()]
            if before.endswith('.') and not before.endswith('this.'):
                continue
            if len(targets) > 3:
                skipped += 1
                continue
            line = line_of_call(found.start())
            callers = [d for d in declared if d['line'] and d['line'] <= line and d['name'] != name]
            if not callers:
                continue
            caller = callers[-1]
            for target in targets:
                if target['file'] == path and target['line'] == line:
                    continue
                key = (caller['id'], target['id'], line)
                if key in seen:
                    continue
                seen.add(key)
                edges.append({'source': caller['id'], 'target': target['id'], 'relation': 'calls', 'file': path,
                              'line': line, 'context': 'name', 'fact': 'inferred', 'via': 'adapter:dart-name-call',
                              'confidence': 'medium' if len(targets) == 1 else 'low', 'target_file': target['file']})
    notes = [f'{skipped} Dart call site(s) named a symbol declared in more than three files: no call edge inferred']
    return edges, notes if skipped else []


def language(path: str) -> str:
    """Language of a corpus file: Dart and Kotlin get bridge and import handling; the rest get
    Graphify's AST symbols and calls only."""
    suffix = posixpath.splitext(path)[1]
    return LANGUAGE_BY_SUFFIX.get(suffix, 'other')


def run_adapter(root: Path, files: list[str], config: dict, tool: dict) -> dict:
    work = map_dir(root)
    (work / 'tmp').mkdir(parents=True, exist_ok=True)
    (work / 'logs').mkdir(parents=True, exist_ok=True)
    request, out = work / 'tmp/request.json', work / 'tmp/structure.json'
    out.unlink(missing_ok=True)
    atomic_write(request, json.dumps({'root': str(root), 'files': files}))
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    log = work / f'logs/extract-{stamp}.log'
    env = {**os.environ, 'PYTHONHASHSEED': '0', 'GRAPHIFY_OUT': str((work / 'graphify').resolve())}
    timeout = config['extractor']['timeout']
    with log.open('wb') as output:
        process = subprocess.Popen([*tool['argv'], str(adapter_path()), 'extract', '--request', str(request),
                                    '--out', str(out)], cwd=root, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise Blocked(f'graphify extraction timed out after {timeout}s; see {log.relative_to(root)}')
    for old in sorted((work / 'logs').glob('extract-*.log'))[:-5]:
        old.unlink(missing_ok=True)  # best-effort log rotation
    if code != 0:
        tail = log.read_text(errors='replace')[-600:]
        raise Blocked(f'graphify extraction failed (exit {code}); {log.relative_to(root)}: {tail}')
    try:
        data = json.loads(out.read_text())
    except (OSError, ValueError) as error:
        raise Blocked(f'graphify adapter wrote no valid output: {error}') from error
    if not (isinstance(data, dict) and data.get('schema') == 1 and isinstance(data.get('nodes'), list)
            and isinstance(data.get('edges'), list)
            and all(isinstance(n, dict) and isinstance(n.get('id'), str) for n in data['nodes'])
            and all(isinstance(e, dict) and all(isinstance(e.get(k), str) for k in ('source', 'target', 'relation'))
                    for e in data['edges'])):
        raise Blocked('graphify adapter output does not match the expected schema')
    if (data.get('tool') or {}).get('version') != tool.get('version'):
        raise Blocked('graphify version changed between the version check and extraction')
    return data


def line_of(location) -> int | None:
    found = re.fullmatch(r'L(\d+)', str(location or ''))
    return int(found.group(1)) if found else None


def normalize(raw: dict, corpus: set[str]) -> tuple[list[dict], list[dict], list[str]]:
    """Graphify nodes/edges as repository-relative facts. Redundant file->symbol edges and
    Dart import edges (resolved here instead) are dropped; nothing else is filtered."""
    by_id = {n['id']: n for n in raw['nodes']}
    problems, symbols, kept, file_ids = [], [], {}, {}
    outside = 0
    for node in raw['nodes']:
        source = node.get('source_file')
        if not source:
            continue
        if source not in corpus:
            outside += 1
            continue
        label = str(node.get('label', ''))
        if label == source.rsplit('/', 1)[-1]:
            file_ids[node['id']] = source
            continue
        name = label.strip('.').removesuffix('()') or label
        item = {'id': node['id'], 'name': name, 'label': label, 'file': source,
                'line': line_of(node.get('source_location')), 'lang': language(source)}
        kept[node['id']] = item
        symbols.append(item)
    if outside:
        problems.append(f'graphify returned {outside} node(s) outside the corpus; ignored')
    owners = {}
    edges = []
    for edge in raw['edges']:
        relation, source, target = edge['relation'], edge['source'], edge['target']
        source_file = edge.get('source_file') or ''
        lang = language(source_file)
        if source in file_ids and relation in ('defines', 'contains'):
            continue
        if lang == 'dart' and relation in ('imports', 'exports', 'includes'):
            continue  # resolved to files by dependencies()
        if source not in kept and source not in file_ids:
            continue
        if relation == 'method' and source in kept and target in kept:
            owners[target] = kept[source]['name']
        confidence = str(edge.get('confidence', 'EXTRACTED')).upper()
        # Dart is extracted by Graphify's regex extractor (no call edges); other languages by tree-sitter.
        via = 'graphify:dart-regex' if lang == 'dart' else f'graphify:{lang}-ast'
        if confidence == 'EXTRACTED':
            label = fact('extracted', via, 'medium' if lang == 'dart' else 'high')
        else:
            label = fact('inferred', via + ':resolver', 'low' if confidence == 'AMBIGUOUS' else 'medium')
        item = {'source': kept[source]['id'] if source in kept else 'file:' + file_ids[source],
                'relation': relation, 'file': source_file, 'line': line_of(edge.get('source_location')),
                'context': edge.get('context'), **label}
        if target in kept:
            item['target'] = target
        elif target in file_ids:
            item['target'] = 'file:' + file_ids[target]
        else:
            item['target'] = None
            item['target_label'] = str(by_id.get(target, {}).get('label', target))
        edges.append(item)
    for item in symbols:
        if item['id'] in owners:
            item['owner'] = owners[item['id']]
    return symbols, edges, problems


# ----------------------------------------------------------- dependencies

DART_DIRECTIVE = re.compile(r'^[ \t]*(import|export|part)[ \t]+(?!of\b)([\'"])([^\'"\n]+)\2', re.M)
DART_PART_OF = re.compile(r'^[ \t]*part[ \t]+of[ \t]+([\'"])([^\'"\n]+)\1', re.M)
KT_PACKAGE = re.compile(r'^[ \t]*package[ \t]+([\w.]+)', re.M)
KT_IMPORT = re.compile(r'^[ \t]*import[ \t]+([\w.]+)(\.\*)?', re.M)
KT_TOP = re.compile(r'^(?:(?:public|internal|private|data|sealed|enum|abstract|open|annotation|inline|value|'
                    r'expect|actual|const|suspend|operator|infix|tailrec)\s+)*'
                    r'(?:class|object|interface|typealias|fun(?:\s*<[^>]*>)?|val|var)\s+(?:[\w.]+\.)?(\w+)', re.M)


def dart_packages(texts: dict[str, str], listing: dict) -> dict[str, str]:
    packages = {}
    for path in listing:
        if path.rsplit('/', 1)[-1] == 'pubspec.yaml' and path in texts:
            found = re.search(r'^name:[ \t]*([\w-]+)', texts[path], re.M)
            if found:
                folder = posixpath.dirname(path)
                packages[found.group(1)] = posixpath.join(folder, 'lib') if folder else 'lib'
    return packages


def dependencies(root: Path, texts: dict, file_info: dict, listing: dict, config: dict):
    """Import/export/part edges with resolved targets. Mechanical pattern extraction."""
    deps, problems = [], []
    packages = dart_packages(texts, listing)
    kotlin_index: dict[str, list[str]] = {}
    packages_of: dict[str, str] = {}
    for path, info in file_info.items():
        if info['lang'] == 'kotlin' and path in texts:
            clean = strip_comments(texts[path])
            found = KT_PACKAGE.search(clean)
            package = found.group(1) if found else ''
            packages_of[path] = package
            for name in set(KT_TOP.findall(clean)):
                kotlin_index.setdefault(f'{package}.{name}' if package else name, []).append(path)
    for path, info in file_info.items():
        if path not in texts:
            continue
        clean = strip_comments(texts[path])
        line = Lines(clean)
        if info['lang'] == 'dart':
            for found in DART_DIRECTIVE.finditer(clean):
                kind, uri = found.group(1), found.group(3)
                target, where = resolve_dart(uri, path, packages, listing, file_info)
                deps.append({'from': path, 'to': target, 'uri': uri, 'kind': kind, 'line': line(found.start(3)),
                             'target': where, **fact('extracted', 'adapter:dart-directive', 'high')})
            for found in DART_PART_OF.finditer(clean):
                uri = found.group(2)
                target, where = resolve_dart(uri, path, packages, listing, file_info)
                deps.append({'from': path, 'to': target, 'uri': uri, 'kind': 'part-of', 'line': line(found.start(2)),
                             'target': where, **fact('extracted', 'adapter:dart-directive', 'high')})
        elif info['lang'] == 'kotlin':
            for found in KT_IMPORT.finditer(clean):
                name, wildcard = found.group(1), bool(found.group(2))
                targets = resolve_kotlin(name, wildcard, kotlin_index, packages_of)
                base = {'from': path, 'uri': name + ('.*' if wildcard else ''), 'kind': 'import',
                        'line': line(found.start(1))}
                if not targets:
                    deps.append({**base, 'to': None, 'target': 'external',
                                 **fact('extracted', 'adapter:kotlin-import', 'high')})
                for target in targets:
                    deps.append({**base, 'to': target, 'target': 'in_corpus', 'ambiguous': len(targets) > 1 and not wildcard,
                                 **fact('extracted' if len(targets) == 1 or wildcard else 'inferred',
                                        'adapter:kotlin-import', 'medium' if len(targets) == 1 or wildcard else 'low')})
    return deps, kotlin_index, problems


def resolve_dart(uri: str, source: str, packages: dict, listing: dict, file_info: dict) -> tuple[str | None, str]:
    if uri.startswith('dart:'):
        return None, 'external'
    if uri.startswith('package:'):
        name, _, rest = uri[len('package:'):].partition('/')
        if name not in packages:
            return None, 'external'
        path = posixpath.normpath(posixpath.join(packages[name], rest))
    elif re.match(r'^[a-z]+:', uri):
        return None, 'external'
    else:
        path = posixpath.normpath(posixpath.join(posixpath.dirname(source), uri))
    if path in file_info:
        return path, 'in_corpus'
    return path, 'outside_corpus' if path in listing else 'missing'


def resolve_kotlin(name: str, wildcard: bool, index: dict, packages_of: dict) -> list[str]:
    if wildcard:
        return sorted(p for p, package in packages_of.items() if package == name)
    parts = name.split('.')
    for cut in range(len(parts), 0, -1):  # nested classes: a.b.Outer.Inner resolves to a.b.Outer
        if '.'.join(parts[:cut]) in index:
            return sorted(set(index['.'.join(parts[:cut])]))
    return []


# ---------------------------------------------------------------- bridges

def channel_regex(types: list[str], kotlin: bool) -> re.Pattern:
    names = '|'.join(map(re.escape, types))
    if kotlin:
        return re.compile(rf'\b({names})\s*\(\s*([^,()]*(?:\([^()]*\))?[^,()]*?)\s*,\s*'
                          r'(?:("(?:[^"\\\n]|\\.)*")|([A-Za-z_][\w.]*))')
    return re.compile(rf'\b({names})\s*(?:<[^<>()]*>)?\s*\(\s*(?:(\'[^\'\n]*\'|"[^"\n]*")|([A-Za-z_][\w.]*))')


DART_CONST = re.compile(r'\b(?:const|final|static\s+const|static\s+final)\s+(?:String\s+)?(\w+)\s*=\s*'
                        r'(\'[^\'\n]*\'|"[^"\n]*")\s*;')
KT_CONST = re.compile(r'\b(?:const\s+)?val\s+(\w+)\s*(?::\s*String\s*)?=\s*("(?:[^"\\\n]|\\.)*")')
KIND = {'MethodChannel': 'method', 'OptionalMethodChannel': 'method', 'EventChannel': 'event',
        'BasicMessageChannel': 'message'}


def scan_bridges(texts: dict, file_info: dict, config: dict) -> dict:
    """Platform-channel endpoints on both sides, joined by literal channel name."""
    cfg = config['bridges']
    dart_channel = channel_regex(cfg['dart_channel_types'], kotlin=False)
    kotlin_channel = channel_regex(cfg['kotlin_channel_types'], kotlin=True)
    constants = {'dart': {}, 'kotlin': {}}
    for path, info in file_info.items():
        if path in texts and info['lang'] in constants:
            pattern = DART_CONST if info['lang'] == 'dart' else KT_CONST
            for name, value in pattern.findall(strip_comments(texts[path])):
                constants[info['lang']].setdefault(name, set()).add(literal(value))
    channels: dict[str, dict] = {}
    unresolved: list[dict] = []
    globals_dart: dict[str, set[str]] = {}

    def channel(name: str, kind: str) -> dict:
        return channels.setdefault(name, {'name': name, 'kind': kind, 'dart': [], 'kotlin': [], 'commands': {},
                                          'listeners': [], 'producers': [], 'dynamic': [], 'tests': [],
                                          'contracts': []})

    per_file: dict[str, dict] = {}
    for path, info in sorted(file_info.items()):
        if path not in texts or info['lang'] not in ('dart', 'kotlin'):
            continue
        clean = strip_comments(texts[path])
        if not re.search(r'Channel\b|MethodCall', clean):
            continue
        line = Lines(clean)
        kotlin = info['lang'] == 'kotlin'
        local = {}
        if kotlin:
            for name, value in KT_CONST.findall(clean):
                local[name] = literal(value)
        else:
            for name, value in DART_CONST.findall(clean):
                local[name] = literal(value)
        bindings: dict[str, str] = {}
        declared = []
        for found in (kotlin_channel if kotlin else dart_channel).finditer(clean):
            type_name = found.group(1)
            token = found.group(3) if kotlin else found.group(2)
            ref = found.group(4) if kotlin else found.group(3)
            name, how = literal(token), 'literal'
            if name is None and ref:
                short = ref.rsplit('.', 1)[-1]
                if short in local and local[short] is not None:
                    name, how = local[short], 'constant in file'
                else:
                    candidates = constants[info['lang']].get(short, set())
                    if len(candidates) == 1 and None not in candidates:
                        name, how = next(iter(candidates)), 'unique constant in corpus'
            where = {'file': path, 'line': line(found.start()), 'type': type_name}
            if name is None:
                unresolved.append({**where, 'side': info['lang'], 'detail': f'channel name is {ref!r}, not a resolvable literal'})
                continue
            confidence = 'high' if how == 'literal' else 'medium'
            if '$' in name:  # string interpolation: the real name is chosen at run time
                how, confidence = 'interpolated literal (name pattern)', 'low'
            kind = KIND.get(type_name, 'method')
            entry = {**where, 'resolved_by': how, **fact('extracted' if how != 'unique constant in corpus' else 'inferred',
                                                          f'adapter:{info["lang"]}-channel', confidence)}
            close = match_close(clean, clean.index('(', found.start()), '(', ')')
            before = clean[max(0, found.start() - 160):found.start()]
            bound = re.search(r'(\w+)\s*=\s*(?:[\w.]+\s*\?\?\s*)?(?:const\s+|new\s+)?$', before)
            names = set()
            if bound:
                names.add(bound.group(1))
            after = clean[close:close + 200]
            also = re.match(r'\s*\.\s*(?:also|let|apply)\s*\{\s*(\w+)\s*->', after)
            if also:
                names.add(also.group(1))
            entry['binding'] = sorted(names)
            for item in names:
                bindings[item] = name
            declared_constant = re.search(r'(?:^|\n)[ \t]*(?:static\s+)?(?:const|final)\s+(?:[\w<>?]+\s+)?(\w+)\s*=\s*'
                                          r'(?:const\s+)?$', before)
            if not kotlin and declared_constant:  # usable from importing files
                globals_dart.setdefault(declared_constant.group(1), set()).add(name)
            chained = re.match(r'\s*\.\s*(setMethodCallHandler|setStreamHandler|setMessageHandler)\s*', after)
            declared.append((name, kind, close, chained.group(1) if chained else None, entry))
            channel(name, kind)[info['lang']].append(entry)
        per_file[path] = {'clean': clean, 'line': line, 'bindings': bindings, 'declared': declared,
                          'kotlin': kotlin}
    # Dart aliases (`_channel = channel`) and channels imported as top-level constants.
    for path, data in per_file.items():
        if data['kotlin']:
            continue
        for _ in range(3):
            for left, right in re.findall(r'\b(\w+)\s*=\s*(\w+)\s*(?=[,;)])', data['clean']):
                if right in data['bindings'] and left not in data['bindings']:
                    data['bindings'][left] = data['bindings'][right]
    for path, data in sorted(per_file.items()):
        if data['kotlin']:
            scan_kotlin_handlers(path, data, channel, unresolved)
        else:
            scan_dart_calls(path, data, cfg, globals_dart, channel, unresolved)
    for path, info in sorted(file_info.items()):  # wrappers can be called from any Dart file
        if info['lang'] != 'dart' or path not in texts or not cfg['dart_wrappers']:
            continue
        clean = per_file[path]['clean'] if path in per_file else strip_comments(texts[path])
        line = per_file[path]['line'] if path in per_file else Lines(clean)
        for wrapper in cfg['dart_wrappers']:
            pattern = re.compile(rf'\b{re.escape(wrapper["function"])}\s*(?:<[^()]*?>)?\s*\(\s*(\'[^\'\n]*\'|"[^"\n]*")')
            for found in pattern.finditer(clean):
                command = literal(found.group(1))
                target = channel(wrapper['channel'], 'method')
                target['commands'].setdefault(command, {'dart': [], 'kotlin': []})['dart'].append(
                    {'file': path, 'line': line(found.start(1)), 'wrapper': wrapper['function'],
                     **fact('extracted', 'adapter:dart-wrapper (declared in map.json)', 'medium')})
    for item in channels.values():
        sides = bool(item['dart']), bool(item['kotlin'])
        item['status'] = {(True, True): 'linked', (True, False): 'dart_only', (False, True): 'kotlin_only',
                          (False, False): 'referenced_only'}[sides]
        for command in item['commands'].values():
            command['status'] = ('linked' if command['dart'] and command['kotlin'] else
                                 'no_kotlin_handler_found' if command['dart'] else 'no_dart_caller_found')
    return {'channels': dict(sorted(channels.items())), 'unresolved': unresolved}


def scan_dart_calls(path, data, cfg, globals_dart, channel, unresolved):
    methods = '|'.join(map(re.escape, cfg['dart_invoke_methods']))
    pattern = re.compile(rf'([A-Za-z_][\w.]*)\s*\.\s*({methods})\s*(?:<[^()]*?>)?\s*\(\s*'
                         r'(?:(\'[^\'\n]*\'|"[^"\n]*")|([^,()\s][^,()]*))')
    clean, line, bindings = data['clean'], data['line'], data['bindings']
    own = {name for name, *_ in data['declared']}

    def owner(receiver: str) -> tuple[str | None, dict]:
        short = receiver.rsplit('.', 1)[-1]
        if short in bindings:
            return bindings[short], fact('extracted', 'adapter:dart-channel-call', 'medium')
        if len(globals_dart.get(short, ())) == 1:
            return next(iter(globals_dart[short])), fact('inferred', 'adapter:dart-channel-call (imported constant)', 'medium')
        if len(own) == 1:
            return next(iter(own)), fact('inferred', 'adapter:dart-channel-call (only channel in file)', 'low')
        return None, {}

    for found in pattern.finditer(clean):
        name, label = owner(found.group(1))
        where = {'file': path, 'line': line(found.start())}
        command = literal(found.group(3))
        if name is None:
            unresolved.append({**where, 'side': 'dart', 'detail': f'{found.group(1)}.{found.group(2)}() on a receiver '
                               f'not bound to a channel{"; candidates " + ", ".join(sorted(own)) if own else ""}'})
            continue
        target = channel(name, 'method')
        if command is None:
            target['dynamic'].append({**where, 'side': 'dart', 'detail': f'command name is {found.group(4).strip()!r}'})
        else:
            target['commands'].setdefault(command, {'dart': [], 'kotlin': []})['dart'].append({**where, **label})
    for found in re.finditer(r'([A-Za-z_][\w.]*)\s*\.\s*receiveBroadcastStream\s*\(', clean):
        name, label = owner(found.group(1))
        if name:
            channel(name, 'event')['listeners'].append({'file': path, 'line': line(found.start()), **label})


KT_HANDLER = re.compile(r'([A-Za-z_][\w.]*)\s*\??\.\s*(setMethodCallHandler|setStreamHandler)\s*(\{|\()')
KT_WHEN = re.compile(r'\bwhen\s*\(\s*(\w+)\.method\s*\)\s*\{')
KT_COMPARE = re.compile(r'\b(\w+)\.method\s*(==|!=)\s*("(?:[^"\\\n]|\\.)*")|("(?:[^"\\\n]|\\.)*")\s*(==|!=)\s*(\w+)\.method\b')
KT_LABEL = re.compile(r'((?:"(?:[^"\\\n]|\\.)*"\s*,\s*)*"(?:[^"\\\n]|\\.)*")\s*->')


def scan_kotlin_handlers(path, data, channel, unresolved):
    clean, line, bindings = data['clean'], data['line'], data['bindings']
    regions: list[tuple[int, int, str | None]] = []  # (start, end, channel or None for `this`)
    method_channels = sorted({name for name, kind, *_ in data['declared'] if kind == 'method'})
    for name, kind, close, chained, entry in data['declared']:
        if chained:
            brace = clean.find('{', close)
            paren = clean.find('(', close)
            start = brace if brace != -1 and (paren == -1 or brace < paren) else paren
            end = match_close(clean, start, clean[start], '}' if clean[start] == '{' else ')')
            regions.append((start, end, name))
            if chained == 'setStreamHandler':
                channel(name, kind)['producers'].append({'file': path, 'line': line(start), **fact(
                    'extracted', 'adapter:kotlin-stream-handler', 'medium')})
    this_channels = []
    for found in KT_HANDLER.finditer(clean):
        receiver = found.group(1).rsplit('.', 1)[-1]
        name = bindings.get(receiver)
        if found.group(3) == '{':
            end = match_close(clean, found.end() - 1)
            arg = ''
        else:
            end = match_close(clean, found.end() - 1, '(', ')')
            arg = clean[found.end():end - 1].strip()
        if arg == 'null':
            continue  # handler removal
        if name is None:
            if receiver not in ('this',):
                unresolved.append({'file': path, 'line': line(found.start()), 'side': 'kotlin',
                                   'detail': f'{found.group(2)} on {found.group(1)!r}, not bound to a channel'})
            continue
        if found.group(2) == 'setStreamHandler':
            channel(name, 'event')['producers'].append({'file': path, 'line': line(found.start()), **fact(
                'extracted', 'adapter:kotlin-stream-handler', 'medium')})
            continue
        if arg == 'this':
            this_channels.append(name)
        elif found.group(3) == '(' and arg and not arg.startswith('{'):
            channel(name, 'method')['dynamic'].append({'file': path, 'line': line(found.start()), 'side': 'kotlin',
                                                       'detail': f'handler delegated to {arg!r}'})
        regions.append((found.end() - 1, end, name))
    for found in re.finditer(r'\bfun\s+onMethodCall\s*\(', clean):
        body = clean.find('{', found.end())
        if body != -1:
            regions.append((body, match_close(clean, body), None))

    def attribute(offset: int) -> tuple[str | None, dict, list[str]]:
        inside = [r for r in regions if r[0] <= offset < r[1]]
        if inside:
            start, end, name = max(inside, key=lambda r: r[0])
            if name is not None:
                return name, fact('extracted', 'adapter:kotlin-handler-region', 'medium'), []
            if len(set(this_channels)) == 1:
                return this_channels[0], fact('extracted', 'adapter:kotlin-onMethodCall', 'medium'), []
        if len(method_channels) == 1:
            return method_channels[0], fact('inferred', 'adapter:kotlin-handler (only channel in file)', 'low'), []
        return None, {}, sorted(set(this_channels) or set(method_channels))

    def handled(command: str, offset: int, how: str):
        name, label, candidates = attribute(offset)
        where = {'file': path, 'line': line(offset), 'how': how}
        if name is None:
            unresolved.append({**where, 'side': 'kotlin', 'detail': f'handler for "{command}" not attributable to one '
                               f'channel; candidates: {", ".join(candidates) or "none in file"}'})
            return
        channel(name, 'method')['commands'].setdefault(command, {'dart': [], 'kotlin': []})['kotlin'].append(
            {**where, **label})

    seen = set()
    for found in KT_WHEN.finditer(clean):
        block_start = found.end() - 1
        block = clean[block_start:match_close(clean, block_start)]
        depths = depth_at(block)
        for label in KT_LABEL.finditer(block):
            # A branch label sits directly in the when block and starts a line or follows { } ;
            head = block[:label.start()].rstrip(' \t')
            if depths[label.start()] != 1 or not head.endswith(('\n', '{', '}', ';')):
                continue
            for token in re.findall(r'"(?:[^"\\\n]|\\.)*"', label.group(1)):
                offset = block_start + label.start()
                seen.add(offset)
                handled(literal(token), offset, 'when branch')
    for found in KT_COMPARE.finditer(clean):
        token = found.group(3) or found.group(4)
        handled(literal(token), found.start(), 'comparison')
        seen.add(found.start())
    compared = {m.start() for m in KT_COMPARE.finditer(clean)} | {m.start() for m in KT_WHEN.finditer(clean)}
    for found in re.finditer(r'\b(\w+)\.method\b', clean):
        if any(abs(found.start() - offset) < 40 for offset in compared):
            continue
        name, _label, candidates = attribute(found.start())
        detail = {'file': path, 'line': line(found.start()), 'side': 'kotlin',
                  'detail': 'command chosen at run time: ' + clean[found.start():clean.find('\n', found.start())].strip()[:100]}
        if name:
            channel(name, 'method')['dynamic'].append(detail)
        elif candidates or method_channels:
            unresolved.append(detail)
    for found in re.finditer(r'\b(\w+)\s*\(\s*call\s*,\s*result\s*\)', clean):
        if found.group(1) in ('if', 'when', 'onMethodCall'):
            continue
        name, _label, _candidates = attribute(found.start())
        if name:
            channel(name, 'method')['dynamic'].append({'file': path, 'line': line(found.start()), 'side': 'kotlin',
                                                       'detail': f'call delegated to {found.group(1)}()'})


def attach_bridge_tests(root: Path, bridges: dict, aux: list[str], file_info: dict, texts: dict) -> None:
    """Tests and fixtures that mention a channel name: candidates, not proof of coverage."""
    names = list(bridges['channels'])
    if not names:
        return
    candidates = [p for p, info in file_info.items() if info['test']] + [p for p in aux if is_test(p)]
    for path in sorted(set(candidates)):
        text = texts.get(path)
        if text is None:
            try:
                raw = (root / path).read_bytes()
            except OSError:
                continue
            if len(raw) > TEXT_LIMIT or b'\0' in raw[:4096]:
                continue
            text = raw.decode('utf-8', errors='replace')
        for name in names:
            index = text.find(name)
            if index != -1:
                bridges['channels'][name]['tests'].append({'file': path, 'line': text.count('\n', 0, index) + 1,
                                                           **fact('inferred', 'adapter:text-match', 'low')})


# ------------------------------------------------------------------ tests

def link_tests(file_info: dict, deps: list, symbols: list, edges: list) -> dict:
    """source path -> tests that exercise it, strongest evidence first."""
    links: dict[str, dict[str, dict]] = {}
    rank = {'high': 3, 'medium': 2, 'low': 1}

    def add(source: str, test: str, label: dict):
        if source == test or source not in file_info or file_info[source]['test']:
            return
        current = links.setdefault(source, {}).get(test)
        if not current or rank[label['confidence']] > rank[current['confidence']]:
            links[source][test] = {'test': test, **label}

    for dep in deps:
        if dep['to'] and file_info.get(dep['from'], {}).get('test'):
            add(dep['to'], dep['from'], fact(dep['fact'], dep['via'] + ' (test imports it)', dep['confidence']))
    symbol_file = {s['id']: s['file'] for s in symbols}
    for edge in edges:
        test_file = edge['file']
        target = edge.get('target')
        target_file = symbol_file.get(target) or (target[5:] if target and target.startswith('file:') else None)
        if target_file and file_info.get(test_file, {}).get('test'):
            add(target_file, test_file, fact(edge['fact'], edge['via'] + f' ({edge["relation"]})', edge['confidence']))
    stems: dict[str, list[str]] = {}
    for path, info in file_info.items():
        if info['test']:
            name = path.rsplit('/', 1)[-1]
            stem = re.sub(r'(_test\.dart|Tests?\.kt)$', '', name)
            if stem != name:
                stems.setdefault(stem.lower(), []).append(path)
    for path, info in file_info.items():
        if not info['test']:
            stem = posixpath.splitext(path.rsplit('/', 1)[-1])[0].lower()
            for test in stems.get(stem, []):
                add(path, test, fact('inferred', 'adapter:name-convention', 'low'))
    for dep in deps:  # a part file is tested through its library
        if dep['kind'] == 'part-of' and dep['to'] in links and not file_info.get(dep['from'], {}).get('test'):
            for test, item in list(links[dep['to']].items()):
                add(dep['from'], test, fact(item['fact'], item['via'] + f' via library {dep["to"]}', item['confidence']))
    return {source: sorted(tests.values(), key=lambda t: (-rank[t['confidence']], t['test']))
            for source, tests in sorted(links.items())}


# ----------------------------------------------------------- declarations

def load_declarations(root: Path, file_info: dict, deps: list, bridges: dict, problems: list) -> dict:
    """Read human-maintained declarations; derive (never invent) links to the corpus."""
    result = {'modules': [], 'constraints': [], 'violations': [], 'contracts': [], 'ports': [],
              'prerequisites': [], 'membership': {}}
    path = root / ARCHITECTURE
    if path.is_file():
        try:
            data = json.loads(path.read_text())
        except ValueError as error:
            raise Blocked(f'{ARCHITECTURE} is not valid JSON: {error}') from error
        validate_architecture(data)
        result['modules'] = data['modules']
        result['constraints'] = data['constraints']
    modules = {m['id']: m for m in result['modules']}
    for module in result['modules']:
        members = [p for p in file_info if matches(p, module['paths'])]
        if not members:
            problems.append(f'{ARCHITECTURE}: module {module["id"]} matches no corpus file')
        for member in members:
            result['membership'].setdefault(member, []).append(module['id'])
    for member, ids in result['membership'].items():
        if len(ids) > 1:
            problems.append(f'{ARCHITECTURE}: {member} is in several modules ({", ".join(ids)})')
    for dep in deps:
        if not dep['to'] or dep['to'] not in file_info:
            continue
        sources, targets = result['membership'].get(dep['from'], []), result['membership'].get(dep['to'], [])
        for source in sources:
            allowed = modules[source].get('may_depend_on')
            for target in targets:
                if allowed is not None and target != source and target not in allowed:
                    result['violations'].append({
                        'from': dep['from'], 'to': dep['to'], 'line': dep['line'], 'rule': f'module {source} may depend on '
                        f'{", ".join(allowed) or "no other module"}; imports {target}', 'status': modules[source]['status'],
                        **fact('inferred', 'architecture.json may_depend_on + extracted import', 'medium')})
    for constraint in result['constraints']:
        for dep in deps:
            if any(m in constraint['applies_to'] for m in result['membership'].get(dep['from'], [])):
                if any(fnmatch.fnmatchcase(dep['uri'], pattern) for pattern in constraint.get('forbid_imports', [])):
                    result['violations'].append({
                        'from': dep['from'], 'to': dep['to'], 'line': dep['line'], 'uri': dep['uri'],
                        'rule': f'{constraint["id"]}: {constraint["rule"]}', 'status': constraint['status'],
                        **fact('inferred', 'architecture.json forbid_imports + extracted import', 'medium')})
    base = root / CHANGES
    paths = set(file_info)
    for folder in sorted(p for p in base.iterdir() if (p / 'state.json').is_file()) if base.is_dir() else []:
        try:
            state = json.loads((folder / 'state.json').read_text())
            assurance = json.loads((folder / 'assurance.json').read_text())
        except (OSError, ValueError) as error:
            problems.append(f'{folder.name}: assurance.json or state.json unreadable ({error})')
            continue
        if not isinstance(assurance, dict):
            problems.append(f'{folder.name}: assurance.json is not an object')
            continue
        origin = {'change': folder.name, 'source': f'{CHANGES}/{folder.name}/assurance.json'}
        bridge = assurance.get('bridge') if isinstance(assurance.get('bridge'), dict) else {}
        for row in bridge.get('contracts', []) if bridge.get('applies') is True else []:
            if not isinstance(row, dict):
                continue
            text = json.dumps(row)
            files = sorted(p for p in set(re.findall(r'[\w./-]+\.(?:dart|kts?)\b', text)) if p in paths)
            named = [name for name in bridges['channels'] if name in text]
            contract = {**origin, 'name': row.get('name'), 'files': files, 'channels': named,
                        'fields': {k: row.get(k) for k in ('caller', 'implementation', 'payload', 'ordering', 'ownership',
                                                           'cancellation', 'reconnect', 'errors')},
                        'checks': {'caller': row.get('caller_checks', []), 'native': row.get('native_checks', [])},
                        **fact('declared', origin['source'], 'by phase')}
            result['contracts'].append(contract)
            for name in named:
                bridges['channels'][name]['contracts'].append({'change': folder.name, 'name': row.get('name')})
            if not files and not named:
                problems.append(f'{folder.name}: bridge contract {row.get("name")!r} names no corpus file or channel')
        port = assurance.get('port') if isinstance(assurance.get('port'), dict) else {}
        for row in port.get('components', []) if port.get('applies') is True else []:
            if not isinstance(row, dict):
                continue
            destination = str(row.get('destination', '')).rstrip('/')
            files = sorted(p for p in paths if destination and (p == destination or p.startswith(destination + '/')
                                                                 or fnmatch.fnmatchcase(p, destination)))
            result['ports'].append({**origin, 'name': row.get('name'), 'destination': destination, 'files': files,
                                    'present': bool(files), 'disposition': row.get('disposition'),
                                    'source_repo': port.get('source'), 'revision': port.get('revision'),
                                    'checks': row.get('checks', []), **fact('declared', origin['source'], 'by phase')})
        for ident in assurance.get('prerequisites', []) if isinstance(assurance.get('prerequisites'), list) else []:
            result['prerequisites'].append({'change': folder.name, 'requires': ident})
    return result


def validate_architecture(data) -> None:
    def fail(message):
        raise Blocked(f'{ARCHITECTURE}: {message}')
    if not isinstance(data, dict) or data.get('version') != 1:
        fail('version must be 1')
    if not isinstance(data.get('modules'), list) or not isinstance(data.get('constraints'), list):
        fail('"modules" and "constraints" must be lists')
    ids = set()
    for module in data['modules']:
        if not isinstance(module, dict) or not isinstance(module.get('id'), str) or not module['id']:
            fail('each module needs an "id"')
        if module['id'] in ids:
            fail(f'duplicate module id {module["id"]}')
        ids.add(module['id'])
        if not isinstance(module.get('paths'), list) or not module['paths'] or not all(isinstance(p, str) for p in module['paths']):
            fail(f'module {module["id"]}: "paths" must be a non-empty list of globs')
        if module.get('status') not in ('reviewed', 'proposed'):
            fail(f'module {module["id"]}: "status" must be reviewed or proposed')
        if not isinstance(module.get('source'), str) or not module['source'].strip():
            fail(f'module {module["id"]}: "source" must say where the decision was made')
        if 'may_depend_on' in module and not (isinstance(module['may_depend_on'], list)
                                              and all(isinstance(v, str) for v in module['may_depend_on'])):
            fail(f'module {module["id"]}: "may_depend_on" must be a list of module ids')
    for module in data['modules']:
        for other in module.get('may_depend_on', []):
            if other not in ids:
                fail(f'module {module["id"]}: may_depend_on names unknown module {other}')
    for constraint in data['constraints']:
        if not isinstance(constraint, dict) or not all(isinstance(constraint.get(k), str) and constraint[k].strip()
                                                       for k in ('id', 'rule', 'source')):
            fail('each constraint needs "id", "rule" and "source"')
        if constraint.get('status') not in ('reviewed', 'proposed'):
            fail(f'constraint {constraint["id"]}: "status" must be reviewed or proposed')
        if not isinstance(constraint.get('applies_to'), list) or not all(m in ids for m in constraint['applies_to']):
            fail(f'constraint {constraint["id"]}: "applies_to" must list known module ids')
        if not isinstance(constraint.get('forbid_imports', []), list):
            fail(f'constraint {constraint["id"]}: "forbid_imports" must be a list of import patterns')


# ---------------------------------------------------------------- context

# Domain synonyms and inflections for lexical matching. Each family maps to one stem.
SYNONYMS = {'failure': 'error', 'failures': 'error', 'failed': 'error', 'fail': 'error', 'fails': 'error',
            'failing': 'error', 'errors': 'error', 'crash': 'error', 'crashed': 'error', 'exception': 'error',
            'exceptions': 'error', 'retries': 'retry', 'retrying': 'retry', 'songs': 'song', 'tracks': 'track',
            'lyrics': 'lyric', 'channels': 'channel', 'commands': 'command', 'handlers': 'handler',
            'tests': 'test', 'buttons': 'button', 'screens': 'screen', 'pages': 'page', 'files': 'file'}


def stem(word: str) -> str:
    word = word.lower()
    if word in SYNONYMS:
        return SYNONYMS[word]
    if len(word) > 4 and word.endswith('ing'):
        return word[:-3]
    if len(word) > 3 and word.endswith('s') and not word.endswith('ss'):
        return word[:-1]
    return word


def words(text: str) -> list[str]:
    parts = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', text)
    return [stem(w) for w in re.findall(r'[A-Za-z][A-Za-z0-9]*', parts.replace('_', ' '))]


class Context:
    """Bounded task packet over the published map. Critical sections are never cut."""

    def __init__(self, root: Path, data: dict, config: dict, status: dict, checks: dict | None):
        self.root, self.data, self.config, self.status, self.checks = root, data, config, status, checks
        self.symbols_by_file: dict[str, list[dict]] = {}
        self.symbol_by_id = {}
        for symbol in data['symbols']:
            self.symbols_by_file.setdefault(symbol['file'], []).append(symbol)
            self.symbol_by_id[symbol['id']] = symbol
        self.importers: dict[str, list[dict]] = {}
        self.imports: dict[str, list[dict]] = {}
        for dep in data['deps']:
            self.imports.setdefault(dep['from'], []).append(dep)
            if dep['to']:
                self.importers.setdefault(dep['to'], []).append(dep)

    # -- entry points
    def entries(self, task: str, files: list[str], symbols: list[str]) -> tuple[list[dict], list[str]]:
        notes, chosen = [], {}
        corpus = self.data['files']
        for raw in files:
            path = relative(self.root, raw)
            if path in corpus:
                chosen[path] = {'file': path, 'score': 100, 'reasons': ['named with --file'], 'symbols': []}
            else:
                notes.append(f'{path}: not in the map corpus (excluded, not Dart/Kotlin, or missing)')
        for name in symbols:
            found = [s for s in self.data['symbols'] if s['name'] == name] or \
                    [s for s in self.data['symbols'] if s['name'].lower() == name.lower()]
            if not found:
                notes.append(f'symbol {name!r}: no extracted declaration with that name')
            if len(found) > 1:
                notes.append(f'symbol {name!r} is ambiguous: {len(found)} declarations '
                             f'({", ".join(sorted({s["file"] for s in found})[:6])}); all listed, pick with --file')
            for symbol in found[:6]:
                entry = chosen.setdefault(symbol['file'], {'file': symbol['file'], 'score': 90,
                                                           'reasons': [], 'symbols': []})
                entry['reasons'].append(f'symbol {symbol["name"]}')
                entry['symbols'].append(symbol)
        if chosen and not task:
            return list(chosen.values()), notes
        task_words = [w for w in words(task) if len(w) >= 3 and w not in STOPWORDS]
        identifiers = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]{2,}', task))
        # Only code-shaped tokens (camelCase, snake_case, digits) are matched as exact names;
        # plain words such as "next" or "page" are weighted by how rare they are.
        code_tokens = {t for t in identifiers if '_' in t or re.search(r'[a-z][A-Z]|\d', t)}
        if not task_words and not chosen:
            notes.append('the task has no searchable English or identifier words; pass --file or --symbol')
            return [], notes
        wanted = set(task_words)
        scores: dict[str, dict] = {}
        frequency = self.word_frequency()

        files_total = max(1, len(corpus))

        def weight(hit: set[str]) -> float:
            # Inverse document frequency: a word found in many files says little about which file the
            # task means; a word found in few says a lot. Each file's words add up.
            return sum(math.log(1 + files_total / max(1, frequency.get(w, 1))) for w in hit) / 4

        def bump(path: str, points: float, reason: str, symbol: dict | None = None):
            entry = scores.setdefault(path, {'file': path, 'score': 0.0, 'reasons': [], 'symbols': []})
            entry['score'] += points
            if reason not in entry['reasons']:
                entry['reasons'].append(reason)
            if symbol and symbol not in entry['symbols']:
                entry['symbols'].append(symbol)

        for path in corpus:
            stem = posixpath.splitext(path.rsplit('/', 1)[-1])[0]
            if stem in code_tokens or stem in identifiers and len(words(stem)) > 1:
                bump(path, 6, f'file name {stem}')
            hit = wanted & set(words(path))
            if hit:
                bump(path, weight(hit), 'path words ' + ', '.join(sorted(hit)))
        hits_by_file: dict[str, tuple[set[str], list[tuple[int, dict]]]] = {}
        for symbol in self.data['symbols']:
            if symbol['name'] in code_tokens:
                bump(symbol['file'], 5, f'symbol {symbol["name"]}', symbol)
                continue
            hit = wanted & set(words(symbol['name']))
            if len(hit) >= 2 or (hit and len(words(symbol['name'])) == 1):
                union, found = hits_by_file.setdefault(symbol['file'], (set(), []))
                union |= hit
                found.append((len(hit), symbol))
        for path, (union, found) in hits_by_file.items():
            # One file's many symbols count each task word once, so large files do not win by size.
            best = [symbol for _, symbol in sorted(found, key=lambda f: (-f[0], f[1]['line'] or 0))[:3]]
            bump(path, weight(union), 'symbols ' + ', '.join(s['name'] for s in best))
            for symbol in best:
                if symbol not in scores[path]['symbols']:
                    scores[path]['symbols'].append(symbol)
        for name, item in self.data['bridges']['channels'].items():
            hit = wanted & set(words(name))
            commands = [c for c in item['commands'] if c in code_tokens or set(words(c)) <= wanted]
            if not (hit or commands):
                continue
            ends = {e['file'] for e in item['dart'] + item['kotlin'] if not corpus.get(e['file'], {}).get('test')}
            for command in commands:
                ends |= {e['file'] for e in item['commands'][command]['dart'] + item['commands'][command]['kotlin']
                         if not corpus.get(e['file'], {}).get('test')}
            for path in ends:
                bump(path, weight(hit) + 2 * len(commands), f'channel {name}'
                     + (f' commands {", ".join(commands[:4])}' if commands else ''))
        ranked = sorted(scores.values(), key=lambda e: (-e['score'], e['file']))
        if ranked:
            floor = ranked[0]['score'] / 3
            weak = [e for e in ranked if e['score'] < floor]
            ranked = [e for e in ranked if e['score'] >= floor]
            if weak:
                notes.append(f'{len(weak)} weaker lexical match(es) left out (score below {floor:.1f}); '
                             'name files with --file if one is relevant')
            if ranked[0]['score'] < 1.5:
                notes.append('only weak matches: the task words are common in this code base; '
                             'name a file, symbol or code identifier for a sharper packet')
        limit = self.config['context']['entry_files']
        if len(ranked) > limit and abs(ranked[limit - 1]['score'] - ranked[limit]['score']) < 1e-9:
            ties = sum(1 for e in ranked if abs(e['score'] - ranked[limit - 1]['score']) < 1e-9)
            notes.append(f'{ties} files tie at score {ranked[limit - 1]["score"]:.1f}; only {limit} shown. '
                         'Name the file or symbol to disambiguate')
        elif len(ranked) > limit:
            notes.append(f'{len(ranked) - limit} more lexical match(es) not shown; name files with --file')
        for entry in ranked[:max(0, limit - len(chosen))]:
            if entry['file'] not in chosen:
                entry['score'] = round(entry['score'], 1)
                chosen[entry['file']] = entry
        if not chosen:
            notes.append('no file, symbol or channel matches the task words')
        return list(chosen.values()), notes

    def word_frequency(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for path in self.data['files']:
            seen = set(words(path))
            for symbol in self.symbols_by_file.get(path, []):
                seen |= set(words(symbol['name']))
            for word in seen:
                counts[word] = counts.get(word, 0) + 1
        return counts

    # -- facts around one file
    def bridges_for(self, paths: set[str]) -> list[tuple[dict, str]]:
        """(channel, relation) for channels the paths declare or use; test doubles separately."""
        found = []
        files = self.data['files']
        for item in self.data['bridges']['channels'].values():
            declared = {e['file'] for e in item['dart'] + item['kotlin'] + item['listeners'] + item['producers']}
            used = set()
            for command in item['commands'].values():
                used |= {e['file'] for e in command['dart'] + command['kotlin']}
            production = {p for p in paths if not files.get(p, {}).get('test')}
            if declared & production:
                found.append((item, 'declares'))
            elif used & production:
                found.append((item, 'uses'))
            elif (declared | used) & paths:
                found.append((item, 'test double'))
        return found

    def checks_for(self, path: str) -> list[str]:
        if not self.checks:
            return []
        names = []
        for domain in domains_for(self.checks, [path]):
            names += self.checks.get('domain_checks', {}).get(domain, [])
        for key, check in self.checks.get('checks', {}).items():
            split = check.get('split')
            if split and path.startswith(split + '/') and key in names:
                names.append(f'{key}:{split}/{path[len(split) + 1:].split("/", 1)[0]}')
        return list(dict.fromkeys(names))


def relative(root: Path, raw: str) -> str:
    path = Path(raw)
    if path.is_absolute():
        try:
            return path.resolve().relative_to(root).as_posix()
        except ValueError:
            return raw
    return posixpath.normpath(raw)


def where(item: dict) -> str:
    return f'{item["file"]}:{item["line"]}' if item.get('line') else item['file']


def label(item: dict) -> str:
    return f'[{item["fact"]}, {item["confidence"]}, {item["via"]}]'


def context(root: Path, task: str = '', files: list[str] = (), symbols: list[str] = (), budget: int | None = None,
            depth: int = 1, expand: str | None = None, refresh: bool = True) -> dict:
    """A bounded packet for a task. Returns {'text', 'data'}; also saved under .work/map/context/."""
    config = load_config(root)
    files, symbols = list(files), list(symbols)
    per_section = config['context']['per_section']
    if expand:
        kind, _, value = expand.partition(':')
        if kind == 'file':
            files.append(value)
        elif kind == 'symbol':
            symbols.append(value)
        elif kind not in ('bridge', 'module'):
            raise Blocked('--expand takes file:<path>, symbol:<name>, bridge:<channel> or module:<id>')
        per_section *= 4
    budget = budget or config['context']['budget_tokens']
    failure = None
    status = map_status(root, config)
    if refresh and status['state'] != 'current':
        try:
            update(root)
        except Blocked as error:
            failure = str(error)
        status = map_status(root, config)
    data = load_map(root)
    try:
        checks = json.loads((root / CHECKS).read_text())
    except (OSError, ValueError):
        checks = None
    critical, optional, notes = [], [], []
    freshness = {'current': 'current', 'stale': 'STALE (built for an older tree; facts below may be outdated)',
                 'missing': 'MISSING', 'invalid': 'INVALID'}[status['state']]
    header = [f'# Context: {task or expand or ", ".join(files + symbols)}', '',
              f'Map: {freshness}' + (f', built {status.get("built_at")}' if status.get('built_at') else '')
              + f'; digest {status["digest"][:12]}; corpus {status["files"]} files.']
    structure = (status.get('structure') or {})
    if data:
        header.append(f'Structure: {structure.get("status")}'
                      + (f' {status["tool"].get("version")}' if structure.get('status') == 'graphify' else '')
                      + f'. {structure.get("note", "")}')
    if failure:
        header.append(f'Map update FAILED: {failure[:400]}')
    for reason in status.get('reasons', []):
        header.append(f'- stale because {reason}')
    header.append('Entry points come from lexical matches on the task words and named files/symbols, not from '
                  'meaning: confirm relevance before relying on them.')
    result_data = {'task': task, 'map': {k: status.get(k) for k in ('state', 'digest', 'built_at', 'reasons')},
                   'entries': [], 'bridges': [], 'fallback': []}
    if not data:
        hits = fallback_search(root, task, files, config)
        critical.append(render_fallback(hits, 'no usable map'))
        result_data['fallback'] = hits
        return finish(root, header, critical, [], notes, budget, result_data)
    view = Context(root, data, config, status, checks)
    entries = []
    if task or files or symbols:
        entries, entry_notes = view.entries(task, files, symbols)
        notes += entry_notes
    if expand and expand.startswith('bridge:'):
        name = expand.split(':', 1)[1]
        item = data['bridges']['channels'].get(name)
        if not item:
            raise Blocked(f'no channel named {name!r} in the map')
        entries += [{'file': f, 'score': 0, 'reasons': [f'endpoint of {name}'], 'symbols': []}
                    for f in sorted({e['file'] for e in item['dart'] + item['kotlin']
                                     if not data['files'].get(e['file'], {}).get('test')})]
    if expand and expand.startswith('module:'):
        ident = expand.split(':', 1)[1]
        members = [p for p, ids in data['declarations']['membership'].items() if ident in ids]
        if not members and ident not in {m['id'] for m in data['declarations']['modules']}:
            raise Blocked(f'no module {ident!r} in {ARCHITECTURE}')
        entries += [{'file': f, 'score': 0, 'reasons': [f'member of module {ident}'], 'symbols': []}
                    for f in sorted(members)[:per_section]]
    paths = {e['file'] for e in entries}
    result_data['entries'] = [{k: v for k, v in e.items() if k != 'symbols'} for e in entries]
    if entries:
        lines = ['## Entry points', '']
        for entry in entries:
            modules = data['declarations']['membership'].get(entry['file'], [])
            lines.append(f'- {entry["file"]} ({"; ".join(entry["reasons"])})'
                         + (f' - module {", ".join(modules)}' if modules else ''))
        critical.append('\n'.join(lines))
    neighbour_paths = set(paths)
    if depth >= 2:
        for path in paths:
            neighbour_paths |= {d['to'] for d in view.imports.get(path, []) if d['to'] in data['files']}
            neighbour_paths |= {d['from'] for d in view.importers.get(path, [])}
    bridges = view.bridges_for(paths)
    seen = {item['name'] for item, _ in bridges}
    bridges += [(item, 'via an import neighbour') for item, relation in view.bridges_for(neighbour_paths - paths)
                if item['name'] not in seen and relation != 'test double']
    full = bool(expand and expand.startswith('bridge:'))
    if bridges:
        critical.append(render_bridges(bridges, paths, data['files'], full))
        result_data['bridges'] = [item['name'] for item, _ in bridges]
    unresolved = [u for u in data['bridges']['unresolved'] if u['file'] in paths]
    if unresolved:
        critical.append('## Bridge endpoints not resolved (dynamic or ambiguous)\n\n' + '\n'.join(
            f'- {where(u)} ({u["side"]}): {u["detail"]}' for u in unresolved))
    critical += render_declarations(root, data, paths, {item['name'] for item, _ in bridges})
    users = []
    for path in sorted(paths):  # direct users of each entry file: short and always shown
        incoming = view.importers.get(path, [])
        if incoming:
            shown = [f'- {d["from"]}:{d["line"]} imports {path}' + (' (test)' if data['files'].get(d['from'], {}).get('test') else '')
                     for d in incoming[:8]]
            users.append(f'- {path} is used by {len(incoming)} file(s):')
            users += ['  ' + line for line in shown]
            if len(incoming) > 8:
                users.append(f'  ... {len(incoming) - 8} more: --expand file:{path}')
    if users:
        critical.append('## Direct users of entry files (never cut to eight per file)\n\n' + '\n'.join(users))
    lines, more = [], 0
    for entry in entries:
        own = view.symbols_by_file.get(entry['file'], [])
        hits = [s for s in entry['symbols'] if s in own] or own
        listed = hits[:per_section]
        more += max(0, len(hits) - len(listed))
        for symbol in listed:
            owner = f'{symbol["owner"]}.' if symbol.get('owner') else ''
            lines.append(f'- {owner}{symbol["name"]} at {where(symbol)}')
    if lines:
        optional.append(('## Symbols in entry files' + ('' if structure.get('status') == 'graphify' else ' (none: '
                         'structure unavailable)'), lines, more))
    for path in sorted(paths):
        out = [d for d in view.imports.get(path, []) if d['to']]
        incoming = list(view.importers.get(path, []))
        for library in [d['to'] for d in out if d['kind'] == 'part-of']:  # parts are imported via their library
            incoming += [{**d, 'from': f'{d["from"]} (via library {library})'} for d in view.importers.get(library, [])
                         if d['kind'] != 'part']
        lines = [f'- imports {d["to"]} ({d["target"]}) at line {d["line"]}' for d in out]
        lines += [f'- imported by {d["from"]}:{d["line"]}' + (' (test)' if data['files'].get(d['from'].split(' ')[0], {})
                                                              .get('test') else '') for d in incoming]
        graph = [e for e in data['edges'] if e['file'] == path and e.get('target') and e['relation'] in
                 ('calls', 'references', 'inherits', 'implements', 'extends', 'mixes_in')]
        for edge in graph:
            target = view.symbol_by_id.get(edge['target'])
            if target and target['file'] != path:
                lines.append(f'- {edge["relation"]} {target["name"]} in {where(target)} {label(edge)}')
        own_ids = {s['id'] for s in view.symbols_by_file.get(path, [])}
        for edge in data['edges']:
            if edge.get('target') in own_ids and edge['file'] != path and edge['relation'] in ('calls', 'references'):
                target = view.symbol_by_id[edge['target']]
                lines.append(f'- {edge["file"]}:{edge["line"]} {edge["relation"]} {target["name"]} {label(edge)}')
        if lines:
            listed = lines[:per_section]
            optional.append((f'## Dependencies of {path} (extracted imports; Kotlin calls/references from Graphify)',
                             listed, len(lines) - len(listed)))
    critical_lines, extra_lines = [], []
    for path in sorted(paths):
        tests = data['tests'].get(path, [])
        critical_lines += [f'- {path}: {t["test"]} {label(t)}' for t in tests[:3]]
        extra_lines += [f'- {path}: {t["test"]} {label(t)}' for t in tests[3:]]
        checks_now = view.checks_for(path)
        if checks_now:
            critical_lines.append(f'- {path}: checks {", ".join(checks_now)} (from {CHECKS})')
        if not tests and not data['files'][path]['test']:
            notes.append(f'{path}: no linked test found (imports, Kotlin references and names searched)')
    # The strongest three tests per entry file and its checks are never cut; the rest are optional.
    if critical_lines:
        critical.append('## Tests and checks (linked; first three per file, never cut)\n\n' + '\n'.join(critical_lines))
    if extra_lines:
        optional.append(('## More linked tests', extra_lines[:per_section], max(0, len(extra_lines) - per_section)))
    excerpts, shown = [], 0
    for entry in entries:
        for symbol in [s for s in entry['symbols'] if s.get('line')][:1]:
            if shown >= config['context']['max_excerpts']:
                break
            text = excerpt(root, symbol['file'], symbol['line'], config['context']['excerpt_lines'])
            if text:
                excerpts.append(f'{where(symbol)} ({symbol["name"]}):\n```\n{text}\n```')
                shown += 1
    if excerpts:
        optional.append(('## Excerpts (current files)', excerpts, 0))
    guidance = guidance_for(data, paths, bridges)
    if guidance:
        optional.append(('## Guidance to read for this task', [f'- {g}' for g in guidance], 0))
    if structure.get('status') == 'graphify' and any(p.endswith('.dart') for p in paths):
        notes.append('Dart calls are inferred by name from unqualified call sites (low and medium confidence); '
                     'qualified calls such as Type.f() are not attributed')
    if structure.get('status') != 'graphify':
        notes.append(f'code structure unavailable ({structure.get("status")}: {structure.get("note", "")}); '
                     'symbols and calls are missing, imports and bridges come from pattern scans')
    if not entries:
        hits = fallback_search(root, task, files, config)
        critical.append(render_fallback(hits, 'no entry point matched in the map'))
        result_data['fallback'] = hits
    if status['state'] != 'current' and entries:
        critical.append('## Changed since the map was built\n\n' + '\n'.join(
            f'- {kind}: {", ".join(items)}' for kind, items in (status.get('changed') or {}).items() if items)
            + '\nLines and links for these files may be wrong; re-read them.')
    return finish(root, header, critical, optional, notes, budget, result_data,
                  expand_hint=[f'work.py context --expand file:{p}' for p in sorted(paths)][:3]
                  + [f'work.py context --expand bridge:{item["name"]}' for item, _ in bridges][:2])


def render_bridges(bridges: list[tuple[dict, str]], paths: set[str], files: dict, full: bool = False) -> str:
    """Both sides of each touched channel. Production endpoints and the commands the entry
    files use are always listed; other commands and test doubles are counted, never dropped."""
    lines = ['## Bridges touched (both sides; never truncated)', '']
    rank = ['low', 'medium', 'high']
    test = lambda entry: files.get(entry['file'], {}).get('test', False)
    doubles_only = [item['name'] for item, relation in bridges if relation == 'test double']
    if doubles_only:
        lines.append('- test entry files fake these channels (production sides not expanded): '
                     + ', '.join(doubles_only) + '; expand with --expand bridge:<name>')
    for item, relation in bridges:
        if relation == 'test double':
            continue
        lines.append(f'### {item["name"]} ({item["kind"]} channel, {item["status"]}; entry {relation})')
        doubles = sorted({e['file'] for e in item['dart'] + item['kotlin'] if test(e)})
        for side in ('dart', 'kotlin'):
            real = [e for e in item[side] if not test(e)]
            for entry in real:
                lines.append(f'- {side} declares at {where(entry)} {label(entry)}')
            if not real:
                lines.append(f'- {side}: NO production endpoint in the corpus (dependency plugin, excluded code '
                             'or dynamic name)')
        if doubles:
            lines.append(f'- test doubles declare it in {len(doubles)} test file(s): {", ".join(doubles[:3])}'
                         + (' ...' if len(doubles) > 3 else ''))
        declares = relation == 'declares' or full
        shown, others = [], {}
        for command, sides in sorted(item['commands'].items()):
            used = {e['file'] for e in sides['dart'] + sides['kotlin']}
            if declares or used & paths:
                shown.append((command, sides))
            else:
                others[sides['status']] = others.get(sides['status'], 0) + 1
        for command, sides in shown:
            dart = ', '.join(where(e) for e in sides['dart'] if not test(e)) or 'none found'
            kotlin = ', '.join(where(e) for e in sides['kotlin']) or 'none found'
            weakest = min((e['confidence'] for e in sides['dart'] + sides['kotlin']), key=rank.index, default='low')
            lines.append(f'- command "{command}" [{sides["status"]}, weakest {weakest}]: Dart {dart}; Kotlin {kotlin}')
        if others:
            lines.append(f'- {sum(others.values())} other command(s) not used by the entry files ('
                         + ', '.join(f'{n} {k}' for k, n in sorted(others.items()))
                         + f'): expand with --expand bridge:{item["name"]}')
        for entry in item['listeners'] + item['producers']:
            if not test(entry):
                role = 'Dart listens' if entry in item['listeners'] else 'Kotlin stream handler'
                lines.append(f'- {role} at {where(entry)} {label(entry)}')
        dynamic = [e for e in item['dynamic'] if not test(e)]
        for entry in dynamic:
            lines.append(f'- dynamic ({entry["side"]}) at {where(entry)}: {entry["detail"]}')
        if item['tests']:
            listed = [where(e) for e in item['tests']]
            lines.append(f'- {len(listed)} test/fixture file(s) mention the name (candidates, '
                         f'{label(item["tests"][0])}): {", ".join(listed[:4])}' + (' ...' if len(listed) > 4 else ''))
        else:
            lines.append('- no test or fixture mentions this channel name')
        for contract in item['contracts']:
            lines.append(f'- declared contract {contract["name"]!r} in change {contract["change"]}')
        lines.append('')
    return '\n'.join(lines).rstrip()


def render_declarations(root: Path, data: dict, paths: set[str], channels: set[str]) -> list[str]:
    declarations, sections = data['declarations'], []
    modules = {m['id']: m for m in declarations['modules']}
    member_ids = sorted({i for p in paths for i in declarations['membership'].get(p, [])})
    lines = []
    for ident in member_ids:
        module = modules[ident]
        lines.append(f'- module {ident} [{module["status"]}, {module["source"]}]: {module.get("responsibility", "")}'
                     + (f'; owns {", ".join(module["owns"])}' if module.get('owns') else '')
                     + (f'; may depend on {", ".join(module["may_depend_on"]) or "nothing"}'
                        if 'may_depend_on' in module else ''))
        for constraint in declarations['constraints']:
            if ident in constraint['applies_to']:
                lines.append(f'  - constraint {constraint["id"]} [{constraint["status"]}]: {constraint["rule"]}')
    for violation in declarations['violations']:
        if violation['from'] in paths or violation.get('to') in paths:
            lines.append(f'- POSSIBLE VIOLATION {violation["from"]}:{violation["line"]} -> '
                         f'{violation.get("to") or violation.get("uri")}: {violation["rule"]} {label(violation)}')
    if not declarations['modules']:
        lines.append(f'- no module declarations yet ({ARCHITECTURE} is empty): ownership and dependency rules are '
                     'not mapped to paths, so none are checked')
    elif not member_ids and paths:
        lines.append('- the entry files belong to no declared module')
    sections.append('## Ownership and constraints (declared; never truncated)\n\n' + '\n'.join(lines))
    lines = []
    for contract in declarations['contracts']:
        if set(contract['files']) & paths or set(contract['channels']) & channels:
            phase, review, confidence = phase_of(root, contract['change'])
            lines.append(f'- contract {contract["name"]!r} in change {contract["change"]} ({review}, phase {phase}) '
                         f'{label({**contract, "confidence": confidence})}')
            for key, value in contract['fields'].items():
                if value:
                    lines.append(f'  - {key}: {value}')
            lines.append(f'  - checks: caller {", ".join(contract["checks"]["caller"]) or "none"}; '
                         f'native {", ".join(contract["checks"]["native"]) or "none"}')
    for port in declarations['ports']:
        if set(port['files']) & paths:
            phase, review, confidence = phase_of(root, port['change'])
            lines.append(f'- port component {port["name"]!r} in change {port["change"]} ({review}, phase {phase}): '
                         f'{port["disposition"]} from {port["source_repo"]}@{str(port["revision"])[:12]}; '
                         f'checks {", ".join(port["checks"]) or "none"} {label({**port, "confidence": confidence})}')
            for need in declarations['prerequisites']:
                if need['change'] == port['change']:
                    lines.append(f'  - prerequisite change {need["requires"]} (phase {phase_of(root, need["requires"])[0]})')
    if lines:
        sections.append('## Contracts and port assurance (declared; never truncated)\n\n' + '\n'.join(lines))
    return sections


def guidance_for(data: dict, paths: set[str], bridges: list[dict]) -> list[str]:
    guides = []
    if bridges:
        guides.append('workflow/work/guides/contracts/playback-bridge.md (bridge contract checklist)')
    if any(re.search(r'database|backup|migration|schema|tag|cue|cover', p, re.I) for p in paths):
        guides.append('workflow/work/guides/contracts/data-compatibility.md (stored data and format compatibility)')
    if any(set(p['files']) & paths for p in data['declarations']['ports']):
        guides += ['workflow/work/guides/port.md', 'workflow/work/guides/migration.md']
    if data['declarations']['membership'] and any(p in data['declarations']['membership'] for p in paths):
        guides.append('workflow/work/guides/architecture.md (direction and ownership)')
    return guides


def excerpt(root: Path, path: str, line: int, size: int) -> str:
    try:
        lines = (root / path).read_text(errors='replace').split('\n')
    except OSError:
        return ''
    start = max(0, line - 2)
    return '\n'.join(f'{start + i + 1:>5}  {text}' for i, text in enumerate(lines[start:start + size]))


def fallback_search(root: Path, task: str, files: list[str], config: dict) -> list[dict]:
    """Bounded case-insensitive text search over corpus files. Not graph evidence."""
    tokens = sorted({t for t in re.findall(r'[A-Za-z_][A-Za-z0-9_]{2,}', task) if t.lower() not in STOPWORDS},
                    key=len, reverse=True)[:8]
    if not tokens:
        return []
    try:
        _tree, listing = snapshot(root, listing=True)
    except Blocked:
        return []
    corpus, _ = corpus_of(listing, config)
    hits, limit = [], config['context']['fallback_hits']
    for path in corpus:
        try:
            raw = (root / path).read_bytes()
        except OSError:
            continue
        if len(raw) > TEXT_LIMIT:
            continue
        per_file = 0
        for number, text in enumerate(raw.decode('utf-8', errors='replace').split('\n'), 1):
            lowered = text.lower()
            found = [t for t in tokens if t.lower() in lowered]
            if found:
                hits.append({'file': path, 'line': number, 'tokens': found, 'text': text.strip()[:140]})
                per_file += 1
                if per_file >= 3 or len(hits) >= limit:
                    break
        if len(hits) >= limit:
            break
    return hits


def render_fallback(hits: list[dict], why: str) -> str:
    lines = [f'## FALLBACK: targeted text search ({why}). NOT graph-verified; matches are text only', '']
    lines += [f'- {h["file"]}:{h["line"]} [{", ".join(h["tokens"])}] {h["text"]}' for h in hits] or ['- no matches']
    return '\n'.join(lines)


def finish(root: Path, header: list[str], critical: list[str], optional: list[tuple[str, list[str], int]],
           notes: list[str], budget: int, data: dict, expand_hint: list[str] = ()) -> dict:
    """Assemble within the token budget (estimate: characters / 4). Critical parts always stay."""
    chars = budget * 4
    head = '\n'.join(header)
    body = [head] + critical
    used = sum(len(part) + 2 for part in body)
    truncated = []
    tail = ['## Uncertainty and coverage', ''] + [f'- {n}' for n in notes] if notes else []
    tail_text = '\n'.join(tail)
    used += len(tail_text) + 200
    for title, items, more in optional:
        kept = []
        for item in items:
            if used + len(item) + 1 > chars:
                break
            kept.append(item)
            used += len(item) + 1
        dropped = len(items) - len(kept) + more
        if kept:
            section = title + '\n\n' + '\n'.join(kept)
            if dropped:
                section += f'\n- ... {dropped} more not shown'
            body.append(section)
            used += len(title) + 2
        if dropped:
            truncated.append(f'{title.lstrip("# ")}: {dropped} item(s)')
    if tail_text:
        body.append(tail_text)
    over = used > chars
    footer = ['## Budget', '',
              f'- about {used // 4} of {budget} tokens (estimate: characters / 4; not a model token count)'
              + ('; critical sections exceed the budget and were kept' if over else '')]
    if truncated:
        footer.append('- truncated: ' + '; '.join(truncated))
        footer += [f'- expand: python3 workflow/scripts/work/{hint}' for hint in expand_hint]
        footer.append('- or raise --budget')
    else:
        footer.append('- nothing truncated')
    body.append('\n'.join(footer))
    text = '\n\n'.join(body) + '\n'
    data.update({'tokens_estimate': len(text) // 4, 'budget': budget, 'truncated': truncated,
                 'critical_over_budget': over})
    out = map_dir(root) / 'context'
    out.mkdir(parents=True, exist_ok=True)
    atomic_write(out / 'latest.md', text)
    atomic_write(out / 'latest.json', json.dumps(data, indent=1, ensure_ascii=False))
    return {'text': text, 'data': data}


def packet_section(root: Path, paths: list[str]) -> str:
    """Map facts for a review packet: freshness plus bridges, declarations and tests of the changed files."""
    try:
        status = ensure_current(root)
    except Blocked as error:
        return f'## Code map\n\nMap could not be refreshed: {error}. Graph-derived facts omitted.\n'
    data = load_map(root)
    if not data:
        return '## Code map\n\nNo map available.\n'
    changed = [p for p in paths if p in data['files']]
    lines = ['## Code map', '', f'Current for this tree (digest {status["digest"][:12]}, structure '
             f'{(status.get("structure") or {}).get("status")}). Facts are labelled extracted, declared or inferred.']
    if not changed:
        return '\n'.join(lines + ['', 'No changed file is in the map corpus.', ''])
    view = Context(root, data, load_config(root), status, None)
    bridges = view.bridges_for(set(changed))
    if bridges:
        lines += ['', render_bridges(bridges, set(changed), data['files'])]
    lines += [''] + render_declarations(root, data, set(changed), {item['name'] for item, _ in bridges})
    tests = [f'- {p}: {t["test"]} {label(t)}' for p in changed for t in data['tests'].get(p, [])[:5]]
    lines += ['', '## Tests linked to changed files', ''] + (tests or ['- none found'])
    return '\n'.join(lines) + '\n'
