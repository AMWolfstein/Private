"""Optional cleanup audit: dead code, simplification and rewrite candidates.

The command only reads. It resolves a scope (language, path, files changed since a
base), runs the configured language tools, and writes a report for the agent and the
code-auditor reviewer. A finding is "proven" only when a configured tool reports one
of the configured codes; everything else is a candidate for the reviewer and owner.
"""
from __future__ import annotations

import fnmatch
import json
import re
import subprocess
from pathlib import Path

from worklib import Blocked, git, now

CONFIG = 'workflow/work/audit.json'


def load_config(root: Path) -> dict:
    path = root / CONFIG
    if not path.is_file():
        raise Blocked(f'{CONFIG} is missing')
    config = json.loads(path.read_text())
    for name, language in config['languages'].items():
        if not language.get('extensions'):
            raise Blocked(f'audit language {name}: "extensions" is required')
        tool = language.get('tool')
        if tool and (not isinstance(tool.get('run'), list) or tool.get('parser') not in PARSERS):
            raise Blocked(f'audit language {name}: tool needs an argv "run" list and a known "parser"')
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


def scope(root: Path, config: dict, languages, paths, base, is_record) -> tuple[list[str], dict]:
    """Existing, unprotected source files selected by every given filter."""
    unknown = set(languages) - set(config['languages'])
    if unknown:
        raise Blocked(f'unknown language {", ".join(sorted(unknown))}; known: {", ".join(config["languages"])}')
    if base:
        tracked = git(root, 'diff', '--name-only', '-z', base).split('\0')
    else:
        tracked = git(root, 'ls-files', '-z').split('\0')
    untracked = git(root, 'ls-files', '-z', '--others', '--exclude-standard').split('\0')
    prefixes = []
    for given in paths:
        target = (root / given).resolve()
        if not target.exists() or not target.is_relative_to(root.resolve()):
            raise Blocked(f'audit path does not exist in this repository: {given}')
        prefixes.append(target.relative_to(root.resolve()).as_posix())
    selected, skipped = [], {'protected': 0}
    for path in sorted({p for p in tracked + untracked if p}):
        language = language_of(config, path)
        if language is None or is_record(path) or not (root / path).is_file():
            continue
        if languages and language not in languages:
            continue
        if prefixes and not any(path == p or p == '.' or path.startswith(p + '/') for p in prefixes):
            continue
        if matches(path, config.get('protected', [])):
            skipped['protected'] += 1
            continue
        selected.append(path)
    return selected, skipped


# ----------------------------------------------------------------- parsers

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


def run_tool(root: Path, name: str, language: dict, files: list[str], log: Path) -> tuple[list[dict], dict]:
    tool = language.get('tool')
    if not tool:
        return [], {'status': 'NO_TOOL', 'reason': 'no tool is configured; candidates come from the auditor only'}
    missing = [p for p in tool.get('requires', []) if not (root / p).exists()]
    if missing:
        return [], {'status': 'BLOCKED', 'reason': f'missing {missing}'}
    argv = list(tool['run'])
    if tool.get('accepts_paths') and len(files) <= tool.get('max_paths', 40):
        argv += files
    try:
        done = subprocess.run(argv, cwd=root / tool.get('cwd', '.'), capture_output=True, text=True, errors='replace',
                              stdin=subprocess.DEVNULL, timeout=tool.get('timeout', 1800))
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
          is_record=lambda path: False, label: str | None = None) -> dict:
    if not (languages or paths or base):
        raise Blocked('name a scope: --lang LANG, --path PATH, --base REV or --change ID (combine to narrow)')
    config = load_config(root)
    files, skipped = scope(root, config, list(languages), list(paths), base, is_record)
    name = label or re.sub(r'[^A-Za-z0-9.]+', '-', '-'.join([*languages, *paths, base or ''])).strip('-')[:60] or 'audit'
    out = out or f'.work/audit/{name}.md'
    target = root / out
    target.parent.mkdir(parents=True, exist_ok=True)
    by_language: dict[str, list[str]] = {}
    for path in files:
        by_language.setdefault(language_of(config, path), []).append(path)
    selected, proven, skipped_kept, tools = set(files), [], [], {}
    for language, members in by_language.items():
        settings = config['languages'][language]
        found, tools[language] = run_tool(root, language, settings, members, target.with_suffix(f'.{language}.log'))
        codes = set(settings.get('proven', []))
        for finding in found:
            if finding['path'] not in selected or finding['code'] not in codes:
                continue
            entry = kept(config, finding)
            if entry:
                skipped_kept.append({**finding, 'reason': entry['reason']})
            else:
                proven.append({'language': language, **finding})
    proven.sort(key=lambda f: (f['path'], f['line'], f['code']))
    gaps = {language: tool for language, tool in tools.items() if tool['status'] != 'RAN'}
    result = {'status': 'PASS' if files else 'NO_FILES', 'at': now(), 'report': out,
              'scope': {'languages': list(languages), 'paths': list(paths), 'base': base},
              'files': len(files), 'by_language': {k: len(v) for k, v in by_language.items()},
              'proven': len(proven), 'kept': len(skipped_kept), 'protected_skipped': skipped['protected'],
              'tools': tools, 'gaps': sorted(gaps)}
    target.with_suffix('.json').write_text(json.dumps(
        {**result, 'file_list': files, 'findings': proven, 'kept_findings': skipped_kept}, indent=2) + '\n')
    target.write_text(render(result, files, proven, skipped_kept, config))
    return result


def render(result: dict, files: list[str], proven: list[dict], skipped_kept: list[dict], config: dict) -> str:
    scope_now = result['scope']
    lines = ['# Audit report', '',
             f'Scope: languages {scope_now["languages"] or "any"}; paths {scope_now["paths"] or "any"}; '
             f'changed since {scope_now["base"] or "n/a (all files in scope)"}.',
             f'Files: {result["files"]} ({", ".join(f"{k} {v}" for k, v in result["by_language"].items()) or "none"}); '
             f'{result["protected_skipped"]} protected files left out.', '',
             '## Tools', '']
    for language, tool in result['tools'].items():
        detail = f'{tool["diagnostics"]} diagnostics, log {tool["log"]}' if tool['status'] == 'RAN' else tool['reason']
        lines.append(f'- {language}: {tool["status"]} ({detail})')
    if result['gaps']:
        lines += ['', f'Coverage gap: no tool evidence for {", ".join(result["gaps"])}. '
                  'Nothing in those languages is proven; report candidates only.']
    lines += ['', f'## Proven by a tool ({len(proven)})', '',
              'Apply these without asking: each is reported by the language tool inside the scope. '
              'One kind per commit; rerun the checks; a red check means it was not dead: revert it.', '']
    lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] {f["message"]}' for f in proven] or ['None.']
    if skipped_kept:
        lines += ['', f'## Kept on purpose ({len(skipped_kept)})', '']
        lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] kept: {f["reason"]}' for f in skipped_kept]
    if config.get('keep'):
        lines += ['', '## Keep list (do not report these again)', '']
        lines += [f'- `{e["path"]}`' + (f' [{e["code"]}]' if e.get('code') else '') + f': {e["reason"]}'
                  for e in config['keep']]
    lines += ['', '## Files in scope', '']
    lines += [f'- {path}' for path in files[:400]]
    if len(files) > 400:
        lines.append(f'- … {len(files) - 400} more in {Path(result["report"]).with_suffix(".json").as_posix()}')
    lines += ['', '## Candidates', '',
              'Give this report to `workflow/.agents/reviewers/code-auditor.md` in a fresh read-only context. '
              'Its findings are candidates for the owner, not proven.', '']
    return '\n'.join(lines)
