"""Optional audit of a named scope. The command only reads.

Kinds: code (dead code, simpler or better-written code), tests (redundant or empty
tests), gaps (code without tests), leaks (unreleased resources) and security (secrets,
vulnerable dependencies). A finding is "proven" only when a configured tool reports a
configured code inside the scope. Detectors in this file give "leads": mechanical
hints that must be verified by reading before anything changes. Everything else comes
from the code-auditor reviewer.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from worklib import Blocked, git, now

CONFIG = 'workflow/work/audit.json'
OSV = 'https://api.osv.dev/v1/querybatch'


def load_config(root: Path) -> dict:
    path = root / CONFIG
    if not path.is_file():
        raise Blocked(f'{CONFIG} is missing')
    config = json.loads(path.read_text())
    for name, language in config['languages'].items():
        if not language.get('extensions'):
            raise Blocked(f'audit language {name}: "extensions" is required')
    for kind, settings in config['kinds'].items():
        for language, tool in (settings.get('tools') or {}).items():
            if tool and (not isinstance(tool.get('run'), list) or tool.get('parser') not in PARSERS):
                raise Blocked(f'audit {kind}/{language}: tool needs an argv "run" list and a known "parser"')
        unknown = set(settings.get('detectors', [])) - set(DETECTORS)
        if unknown:
            raise Blocked(f'audit {kind}: unknown detector {", ".join(sorted(unknown))}')
    for entry in config.get('keep', []):
        if not entry.get('path') or not entry.get('reason'):
            raise Blocked('every audit keep entry needs "path" and "reason"')
    return config


def matches(path: str, patterns) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def language_of(config: dict, path: str) -> str | None:
    for name, language in config['languages'].items():
        if path.endswith(tuple(language['extensions'])):
            return name
    return None


def is_test(config: dict, path: str) -> bool:
    language = language_of(config, path)
    return bool(language) and matches(path, config['languages'][language].get('tests', []))


def scope(root: Path, config: dict, kind: str, languages, paths, base, is_record) -> tuple[list[str], int]:
    """Existing, unprotected files of this kind selected by every given filter."""
    unknown = set(languages) - set(config['languages'])
    if unknown:
        raise Blocked(f'unknown language {", ".join(sorted(unknown))}; known: {", ".join(config["languages"])}')
    tracked = git(root, 'diff', '--name-only', '-z', base) if base else git(root, 'ls-files', '-z')
    untracked = git(root, 'ls-files', '-z', '--others', '--exclude-standard')
    prefixes = []
    for given in paths:
        target = (root / given).resolve()
        if not target.exists() or not target.is_relative_to(root.resolve()):
            raise Blocked(f'audit path does not exist in this repository: {given}')
        prefixes.append(target.relative_to(root.resolve()).as_posix())
    wanted = config['kinds'][kind].get('files', 'source')
    selected, protected = [], 0
    for path in sorted({p for p in (tracked + '\0' + untracked).split('\0') if p}):
        language = language_of(config, path)
        if is_record(path) or not (root / path).is_file():
            continue
        if wanted != 'all' and (language is None or (wanted == 'tests') != is_test(config, path)):
            continue
        if languages and language not in languages:
            continue
        if prefixes and not any(path == p or p == '.' or path.startswith(p + '/') for p in prefixes):
            continue
        if matches(path, config.get('protected', [])):
            protected += 1
            continue
        selected.append(path)
    return selected, protected


# ------------------------------------------------------------ tool parsers

def parse_dart_machine(output: str, root: Path, tool: dict) -> list[dict]:
    """dart analyze --format=machine: SEVERITY|TYPE|CODE|path|line|column|length|message."""
    found = []
    for line in output.splitlines():
        parts = line.split('|', 7)
        if len(parts) != 8 or not parts[4].isdigit():
            continue
        path = Path(parts[3])
        try:
            relative = path.resolve().relative_to(root.resolve()).as_posix() if path.is_absolute() else path.as_posix()
        except ValueError:
            continue
        found.append({'path': relative, 'line': int(parts[4]), 'code': parts[2].lower(), 'message': parts[7]})
    return found


def parse_cargo_json(output: str, root: Path, tool: dict) -> list[dict]:
    """cargo --message-format=json: one compiler-message object per diagnostic."""
    base = (root / tool.get('cwd', '.')).resolve()
    found, seen = [], set()
    for line in output.splitlines():
        if not line.startswith('{'):
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get('message') or {}
        code = (message.get('code') or {}).get('code')
        span = next((s for s in message.get('spans', []) if s.get('is_primary')), None)
        if entry.get('reason') != 'compiler-message' or not code or not span:
            continue
        path = Path(span['file_name'])
        try:
            relative = (path if path.is_absolute() else base / path).resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        key = (relative, span['line_start'], code, message.get('message'))
        if key not in seen:  # the same diagnostic repeats for each target that compiles the file
            seen.add(key)
            found.append({'path': relative, 'line': span['line_start'], 'code': code,
                          'message': message.get('message', '')})
    return found


PARSERS = {'dart-machine': parse_dart_machine, 'cargo-json': parse_cargo_json}


def run_tool(root: Path, tool: dict | None, files: list[str], log: Path) -> tuple[list[dict], dict]:
    if not tool:
        return [], {'status': 'NO_TOOL', 'reason': 'no tool is configured; candidates come from the auditor only'}
    missing = [p for p in tool.get('requires', []) if not (root / p).exists()]
    if missing:
        return [], {'status': 'BLOCKED', 'reason': f'missing {missing}'}
    argv = list(tool['run'])
    if tool.get('accepts_paths') and len(files) <= tool.get('max_paths', 40):
        argv += files
    try:
        done = subprocess.run(argv, cwd=root / tool.get('cwd', '.'), capture_output=True, text=True,
                              errors='replace', stdin=subprocess.DEVNULL, timeout=tool.get('timeout', 1800))
    except FileNotFoundError:
        return [], {'status': 'UNAVAILABLE', 'reason': f'{argv[0]} is not installed or not on PATH'}
    except subprocess.TimeoutExpired:
        return [], {'status': 'TIMEOUT', 'reason': f'{argv[0]} did not finish in {tool.get("timeout", 1800)} s'}
    log.write_text(done.stdout + '\n--- stderr ---\n' + done.stderr)
    found = PARSERS[tool['parser']](done.stdout, root, tool)
    if done.returncode != 0 and not found and not tool.get('nonzero_ok'):
        return [], {'status': 'FAILED', 'reason': f'{argv[0]} exited {done.returncode} without diagnostics',
                    'log': log.relative_to(root).as_posix()}
    return found, {'status': 'RAN', 'command': argv, 'diagnostics': len(found),
                   'log': log.relative_to(root).as_posix()}


# --------------------------------------------------------------- detectors
# Each returns (leads, status). A lead is a hint to verify, never proof.

TEST_START = {
    'dart': re.compile(r'^[ \t]*(?:test|testWidgets)\(\s*(?P<name>\'[^\'\n]*\'|"[^"\n]*")', re.M),
    'kotlin': re.compile(r'@Test\b[^\n]*\n(?:[ \t]*@[^\n]*\n)*[ \t]*(?:suspend\s+)?fun\s+(?P<name>`[^`\n]+`|\w+)\s*\(', re.M),
    'rust': re.compile(r'#\[(?:tokio::)?test[^\]]*\]\s*(?:#\[[^\]]*\]\s*)*(?:async\s+)?fn\s+(?P<name>\w+)\s*\(', re.M),
}
ASSERTS = re.compile(r'(?<![A-Za-z0-9])_*(?:expect|verify|assert|throws|check|must|ensure)\w*|\b(?:fail|panic|unreachable)\b', re.I)


def balanced_end(text: str, start: int, opening: str, closing: str, language: str = 'dart') -> int | None:
    """Index after the bracket that closes the one at `start`, ignoring strings, characters and comments."""
    depth, index, size = 0, start, len(text)
    quotes = '\'"' if language in ('dart', 'kotlin') else '"'
    while index < size:
        char = text[index]
        if text.startswith('//', index):
            index = text.find('\n', index)
            index = size if index == -1 else index
            continue
        if text.startswith('/*', index):
            index = text.find('*/', index + 2)
            index = size if index == -1 else index + 2
            continue
        if char == "'" and language == 'rust':  # a character literal, otherwise a lifetime
            if text[index + 1:index + 2] == '\\':
                index = text.find("'", index + 2) + 1 or size
            elif text[index + 2:index + 3] == "'":
                index += 3
            else:
                index += 1
            continue
        if char == "'" and language == 'kotlin':
            index = text.find("'", index + (3 if text[index + 1:index + 2] == '\\' else 2)) + 1 or size
            continue
        if char in quotes:
            raw = language == 'dart' and text[index - 1:index] == 'r' or language == 'rust' and text[index - 1:index] in ('r', '#')
            triple = text.startswith(char * 3, index) and language != 'rust'
            index += 3 if triple else 1
            while index < size:
                if not raw and text[index] == '\\':
                    index += 2
                    continue
                if text.startswith(char * 3, index) if triple else text[index] == char:
                    index += 3 if triple else 1
                    break
                index += 1
            continue
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return None


def test_blocks(config: dict, path: str, text: str) -> list[dict]:
    language = language_of(config, path)
    pattern = TEST_START.get(language)
    blocks = []
    for found in pattern.finditer(text) if pattern else ():
        if language == 'dart':
            end = balanced_end(text, text.index('(', found.start()), '(', ')', language)
            body_from = found.end()
        else:
            brace = text.find('{', found.end())
            end = balanced_end(text, brace, '{', '}', language) if brace != -1 else None
            body_from = brace
        if end is None:
            continue
        body = text[body_from:end]
        blocks.append({'path': path, 'line': text.count('\n', 0, found.start()) + 1,
                       'name': found['name'].strip('\'"`'), 'body': body, 'head': text[found.start():body_from],
                       'digest': hashlib.sha256(re.sub(r'\s+', '', body).encode()).hexdigest()})
    return blocks


def detect_tests(root: Path, config: dict, files: list[str], run: dict) -> tuple[list[dict], dict]:
    leads, first, total = [], {}, 0
    for path in files:
        for block in test_blocks(config, path, (root / path).read_text(errors='replace')):
            total += 1
            if not ASSERTS.search(block['body']) and not re.search(r'expected\s*=|should_panic', block['head']):
                leads.append({**_at(block), 'code': 'assertion_free',
                              'message': f'test "{block["name"]}" has no assertion; confirm what failure it can detect'})
            same = first.setdefault(block['digest'], block)
            if same is not block and len(re.sub(r'\s+', '', block['body'])) > 40:
                where = 'this file' if same['path'] == path else same['path']
                leads.append({**_at(block), 'code': 'same_body',
                              'message': f'test "{block["name"]}" has the same body as "{same["name"]}" '
                                         f'({where}:{same["line"]}); confirm the setup is the same before merging'})
    return leads, {'status': 'RAN', 'diagnostics': len(leads), 'tests_read': total}


def _at(block: dict) -> dict:
    return {'path': block['path'], 'line': block['line']}


def detect_untested(root: Path, config: dict, files: list[str], run: dict) -> tuple[list[dict], dict]:
    """Source files no test names. Coverage through a higher-level test is invisible here."""
    listing = (git(root, 'ls-files', '-z') + git(root, 'ls-files', '-z', '--others', '--exclude-standard')).split('\0')
    tests = {p: (root / p).read_text(errors='replace') for p in listing
             if p and is_test(config, p) and (root / p).is_file()}
    corpus = '\n'.join(tests.values())
    leads = []
    for path in files:
        language, stem = language_of(config, path), Path(path).stem
        own = (root / path).read_text(errors='replace')
        if language == 'rust' and re.search(r'#\[(?:cfg\(test\)|(?:tokio::)?test)', own):
            continue
        if language == 'dart':
            named = f'/{Path(path).name}\'' in corpus or f'/{Path(path).name}"' in corpus
        else:
            named = bool(re.search(r'\b' + re.escape(stem) + r'\b', corpus))
        if not named:
            risk = 'high risk' if matches(path, run.get('high_risk', [])) else 'normal'
            leads.append({'path': path, 'line': 1, 'code': 'no_direct_test', 'risk': risk,
                          'message': f'no test file names this {language} file ({risk}); '
                                     'check for indirect coverage before writing a test'})
    leads.sort(key=lambda lead: (lead['risk'] != 'high risk', lead['path']))
    return leads, {'status': 'RAN', 'diagnostics': len(leads), 'test_files_read': len(tests)}


def detect_lcov(root: Path, config: dict, files: list[str], run: dict) -> tuple[list[dict], dict]:
    leads, read, missing = [], [], []
    for language, coverage in (run['settings'].get('coverage') or {}).items():
        report = root / coverage['lcov']
        if not report.is_file():
            if any(language_of(config, p) == language for p in files):
                missing.append(f'{language}: {coverage["lcov"]} not found; produce it with: {coverage["produce"]}')
            continue
        base = (root / coverage.get('cwd', '.')).resolve()
        read.append(f'{coverage["lcov"]} written {datetime.fromtimestamp(report.stat().st_mtime, timezone.utc):%Y-%m-%d %H:%M}Z')
        current, lines = None, {}
        for line in report.read_text(errors='replace').splitlines():
            if line.startswith('SF:'):
                source = Path(line[3:])
                try:
                    current = (source if source.is_absolute() else base / source).resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    current = None
            elif line.startswith('DA:') and current:
                number, hits = line[3:].split(',')[:2]
                lines.setdefault(current, {})[int(number)] = int(hits)
        for path in files:
            if language_of(config, path) != language:
                continue
            if path not in lines:
                leads.append({'path': path, 'line': 1, 'code': 'not_in_coverage',
                              'message': 'no test in the coverage run loaded this file'})
                continue
            missed = sorted(n for n, hits in lines[path].items() if hits == 0)
            if missed:
                leads.append({'path': path, 'line': missed[0], 'code': 'uncovered_lines',
                              'message': f'{len(missed)} of {len(lines[path])} lines never ran '
                                         f'(first lines {", ".join(map(str, missed[:8]))}); decide which behaviour is untested'})
    if missing and not read:
        return leads, {'status': 'UNAVAILABLE', 'reason': '; '.join(missing)}
    return leads, {'status': 'RAN', 'diagnostics': len(leads), 'coverage': read, 'missing': missing}


def detect_secrets(root: Path, config: dict, files: list[str], run: dict) -> tuple[list[dict], dict]:
    """detect-secrets reports the file, line and type; the secret itself is never written."""
    leads = []
    files = [p for p in files if not matches(p, run['settings'].get('secrets_skip', []))]
    for start in range(0, len(files), 400):
        try:
            done = subprocess.run([sys.executable, '-m', 'detect_secrets', 'scan', *files[start:start + 400]],
                                  cwd=root, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=900)
            results = json.loads(done.stdout)['results']
        except (subprocess.TimeoutExpired, ValueError, KeyError):
            return [], {'status': 'UNAVAILABLE',
                        'reason': 'detect-secrets is not installed in this Python; run work.py setup'}
        for path, items in results.items():
            leads += [{'path': path, 'line': item['line_number'], 'code': 'possible_secret',
                       'message': f'{item["type"]}; value not shown. Confirm it is real before reporting it'}
                      for item in items]
    return leads, {'status': 'RAN', 'diagnostics': len(leads), 'scope': 'working tree only, not Git history'}


def locked_packages(root: Path, lockfile: str) -> list[tuple[str, str, str]]:
    text = (root / lockfile).read_text(errors='replace')
    if lockfile.endswith('Cargo.lock'):
        blocks = re.findall(r'\[\[package\]\]\n(.*?)(?=\n\[\[|\Z)', text, re.S)
        return [('crates.io', name[1], version[1]) for block in blocks
                if 'registry+' in block and (name := re.search(r'^name = "([^"]+)"', block, re.M))
                and (version := re.search(r'^version = "([^"]+)"', block, re.M))]
    blocks = re.findall(r'^  ([\w-]+):\n((?:    .*\n?)+)', text, re.M)
    return [('Pub', name, version[1]) for name, block in blocks
            if 'source: hosted' in block and (version := re.search(r'^    version: "([^"]+)"', block, re.M))]


def detect_dependencies(root: Path, config: dict, files: list[str], run: dict) -> tuple[list[dict], dict]:
    leads, checked = [], 0
    for lockfile in run['settings'].get('lockfiles', []):
        if not (root / lockfile).is_file():
            continue
        packages = locked_packages(root, lockfile)
        for start in range(0, len(packages), 500):
            batch = packages[start:start + 500]
            body = json.dumps({'queries': [{'package': {'name': name, 'ecosystem': ecosystem}, 'version': version}
                                           for ecosystem, name, version in batch]}).encode()
            request = urllib.request.Request(run.get('osv', OSV), body, {'Content-Type': 'application/json'})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    results = json.load(response)['results']
            except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
                return [], {'status': 'UNAVAILABLE', 'reason': f'cannot reach the OSV database: {error}'}
            checked += len(batch)
            for (ecosystem, name, version), result in zip(batch, results):
                ids = [v['id'] for v in result.get('vulns', [])]
                if ids:
                    leads.append({'path': lockfile, 'line': 1, 'code': 'known_vulnerability',
                                  'message': f'{ecosystem} {name} {version}: {", ".join(ids[:6])}; '
                                             'check whether the affected code path is used'})
    return leads, {'status': 'RAN', 'diagnostics': len(leads), 'packages_checked': checked,
                   'not_covered': 'Gradle dependencies (no lockfile)'}


DETECTORS = {'tests': detect_tests, 'untested': detect_untested, 'lcov': detect_lcov,
             'secrets': detect_secrets, 'dependencies': detect_dependencies}


# ------------------------------------------------------------------ report

def kept(config: dict, finding: dict) -> dict | None:
    for entry in config.get('keep', []):
        if not fnmatch.fnmatchcase(finding['path'], entry['path']):
            continue
        if entry.get('code') and entry['code'] != finding.get('code'):
            continue
        if entry.get('contains') and entry['contains'] not in finding.get('message', ''):
            continue
        return entry
    return None


def audit(root: Path, languages=(), paths=(), base: str | None = None, out: str | None = None,
          is_record=lambda path: False, label: str | None = None, kind: str = 'code', high_risk=()) -> dict:
    if not (languages or paths or base):
        raise Blocked('name a scope: --lang LANG, --path PATH, --base REV or --change ID (combine to narrow)')
    config = load_config(root)
    if kind not in config['kinds']:
        raise Blocked(f'unknown audit kind {kind}; known: {", ".join(config["kinds"])}')
    settings = config['kinds'][kind]
    files, protected = scope(root, config, kind, list(languages), list(paths), base, is_record)
    name = label or re.sub(r'[^A-Za-z0-9.]+', '-', '-'.join([*languages, *paths, base or ''])).strip('-')[:60] or 'audit'
    out = out or f'.work/audit/{name}-{kind}.md'
    target = root / out
    target.parent.mkdir(parents=True, exist_ok=True)
    by_language: dict[str, list[str]] = {}
    for path in files:
        by_language.setdefault(language_of(config, path) or 'other', []).append(path)
    selected, proven, leads, skipped_kept, tools = set(files), [], [], [], {}

    def accept(found, into, codes=None):
        for finding in found:
            if finding['path'] not in selected and not finding['path'].endswith(('.lock',)):
                continue
            if codes is not None and finding['code'] not in codes:
                continue
            entry = kept(config, finding)
            (skipped_kept if entry else into).append({**finding, 'reason': entry['reason']} if entry else finding)

    if 'tools' in settings:
        for language, members in by_language.items():
            tool = settings['tools'].get(language)
            found, tools[language] = run_tool(root, tool, members, target.with_suffix(f'.{language}.log'))
            accept(found, proven, set((tool or {}).get('proven', [])))
    for detector in settings.get('detectors', []) if files or settings.get('files') == 'all' else []:
        found, tools[detector] = DETECTORS[detector](root, config, files, {'settings': settings, 'high_risk': high_risk})
        accept(found, leads)
    proven.sort(key=lambda f: (f['path'], f['line'], f['code']))
    gaps = sorted(name for name, tool in tools.items() if tool['status'] != 'RAN')
    result = {'status': 'PASS' if files else 'NO_FILES', 'kind': kind, 'at': now(), 'report': out,
              'scope': {'languages': list(languages), 'paths': list(paths), 'base': base},
              'files': len(files), 'by_language': {k: len(v) for k, v in by_language.items()},
              'proven': len(proven), 'leads': len(leads), 'kept': len(skipped_kept),
              'protected_skipped': protected, 'tools': tools, 'gaps': gaps}
    target.with_suffix('.json').write_text(json.dumps(
        {**result, 'file_list': files, 'findings': proven, 'lead_list': leads, 'kept_findings': skipped_kept},
        indent=2) + '\n')
    target.write_text(render(result, files, proven, leads, skipped_kept, config, settings))
    return result


def render(result, files, proven, leads, skipped_kept, config, settings) -> str:
    scope_now, automatic = result['scope'], settings.get('apply', 'proven') == 'proven'
    lines = [f'# Audit report: {result["kind"]}', '', settings.get('about', ''), '',
             f'Scope: languages {scope_now["languages"] or "any"}; paths {scope_now["paths"] or "any"}; '
             f'changed since {scope_now["base"] or "n/a (all files in scope)"}.',
             f'Files: {result["files"]} ({", ".join(f"{k} {v}" for k, v in result["by_language"].items()) or "none"}); '
             f'{result["protected_skipped"]} protected files left out.', '', '## Tools', '']
    for name, tool in result['tools'].items():
        detail = ', '.join(f'{k} {v}' for k, v in tool.items() if k not in ('status', 'command')) or 'no detail'
        lines.append(f'- {name}: {tool["status"]} ({detail})')
    if result['gaps']:
        lines += ['', f'Coverage gap: no tool evidence for {", ".join(result["gaps"])}. '
                  'Nothing there is proven or cleared; say so in the report to the owner.']
    if 'tools' in settings:
        lines += ['', f'## Proven by a tool ({len(proven)})', '',
                  'Apply these without asking: each is reported by the language tool inside the scope. '
                  'One kind per commit; rerun the checks; a red check means it was not dead: revert it.'
                  if automatic else 'Report these to the owner. Do not change code for them here.', '']
        lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] {f["message"]}' for f in proven] or ['None.']
    if 'detectors' in settings:
        lines += ['', f'## Leads to verify ({len(leads)})', '',
                  'Mechanical hints, not proof. Read the code and confirm each one is a real problem before '
                  'changing anything; drop the ones that are not.', '']
        lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] {f["message"]}' for f in leads[:300]] or ['None.']
        if len(leads) > 300:
            lines.append(f'- … {len(leads) - 300} more in {Path(result["report"]).with_suffix(".json").as_posix()}')
    if skipped_kept:
        lines += ['', f'## Kept on purpose ({len(skipped_kept)})', '']
        lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] kept: {f["reason"]}' for f in skipped_kept]
    if config.get('keep'):
        lines += ['', '## Keep list (do not report these again)', '']
        lines += [f'- `{e["path"]}`' + (f' [{e["code"]}]' if e.get('code') else '') + f': {e["reason"]}'
                  for e in config['keep']]
    lines += ['', '## Files in scope', ''] + [f'- {path}' for path in files[:400]]
    if len(files) > 400:
        lines.append(f'- … {len(files) - 400} more in {Path(result["report"]).with_suffix(".json").as_posix()}')
    lines += ['', '## Candidates', '',
              f'Give this report to `workflow/.agents/reviewers/code-auditor.md` (section "{result["kind"]}") in a '
              'fresh read-only context. Its findings are candidates: verify each before acting on it.', '']
    return '\n'.join(lines)
