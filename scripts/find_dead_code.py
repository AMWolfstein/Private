#!/usr/bin/env python3
"""Report Dart code in lib/ that production code cannot reach from main().

Why reachability instead of "unused": an "unused" scan only finds the outer
layer of a dead chain. Delete it and the next scan finds the layer underneath.
Walking from main() marks every live declaration in one pass, so a whole dead
chain is reported at once, and a reference from test/ never counts as a use.

Resolution is by name (tree-sitter syntax, no Dart SDK needed). A reference to
`foo` keeps every live-container member called `foo` alive, so a dead member
that shares a busy name can be missed, but a reported declaration really has no
reachable reference. Private names (`_x`) resolve only inside their library
(the file plus its `part` files).

Also reported:
  * ARB keys in the template file that no reachable code reads.
  * Kotlin method-channel handlers whose method name never appears as a string
    in reachable Dart code (dead cross-layer chains Dart tools cannot see).

Usage:
  python3 scripts/find_dead_code.py                # human report
  python3 scripts/find_dead_code.py --json         # machine report
  python3 scripts/find_dead_code.py --check        # exit 1 on findings not in
                                                   # scripts/dead_code_allowlist.txt
Requires: pip install tree-sitter==0.26.0 tree-sitter-language-pack==1.22.1
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
from pathlib import Path
import re
import sys

try:
    from tree_sitter_language_pack import get_parser
except ImportError:  # pragma: no cover - environment guard
    sys.exit('Missing parser: pip install tree-sitter==0.26.0 '
             'tree-sitter-language-pack==1.22.1')

ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST = Path(__file__).resolve().parent / 'dead_code_allowlist.txt'

IDENT_TYPES = {'identifier', 'type_identifier', 'identifier_dollar_escaped'}
CONTAINER_TYPES = {
    'class_definition': 'class',
    'mixin_declaration': 'mixin',
    'enum_declaration': 'enum',
    'extension_declaration': 'extension',
}
BODY_TYPES = {'class_body', 'enum_body', 'extension_body'}
# Called by the runtime or by dart:convert without a source-level reference.
IMPLICIT_MEMBERS = {'toString', 'hashCode', 'noSuchMethod', 'call', 'toJson'}
GENERATED_SUFFIXES = ('.g.dart', '.freezed.dart', '.gr.dart', '.mocks.dart')


@dataclass
class Decl:
    file: str
    library: str
    name: str
    kind: str
    line: int
    container: 'Decl | None' = None
    refs: set[str] = field(default_factory=set)
    strings: set[str] = field(default_factory=set)
    # Initializer refs that run whenever the container is constructed.
    init_refs: set[str] = field(default_factory=set)
    with_container: bool = False  # live whenever its container is live
    visible_for_testing: bool = False
    generated: bool = False
    root: bool = False
    members: list['Decl'] = field(default_factory=list)

    @property
    def key(self) -> str:
        if self.container is not None:
            return f'{self.file}::{self.container.name}.{self.name}'
        return f'{self.file}::{self.name}'


class Parser:
    def __init__(self) -> None:
        self.parser = get_parser('dart')

    def parse(self, path: Path, rel: str, library: str) -> tuple[list[Decl], str | None, list[str]]:
        source = path.read_bytes()
        tree = self.parser.parse(source)
        generated = rel.endswith(GENERATED_SUFFIXES)
        decls: list[Decl] = []
        part_of: str | None = None
        parts: list[str] = []
        for node in tree.root_node.children:
            if node.type == 'part_of_directive':
                literal = _descendant(node, 'string_literal')
                if literal is not None:
                    part_of = _unquote(literal.text.decode())
            elif node.type == 'part_directive':
                literal = _descendant(node, 'string_literal')
                if literal is not None:
                    parts.append(_unquote(literal.text.decode()))
        self._scope(tree.root_node.children, rel, library, None, generated, decls)
        return decls, part_of, parts

    def _scope(self, children, rel, library, container, generated, out):
        annotations: list = []
        prefix: list = []
        children = list(children)
        index = 0
        while index < len(children):
            node = children[index]
            kind = node.type
            if kind == 'annotation':
                annotations.append(node)
            elif kind in ('documentation_comment', 'comment', '{', '}', ','):
                pass
            elif kind in ('import_or_export', 'part_directive',
                          'part_of_directive', 'library_name'):
                annotations, prefix = [], []
            elif kind == ';':
                annotations, prefix = [], []
            elif kind in CONTAINER_TYPES or kind == 'type_alias':
                out.append(self._container(node, rel, library, container,
                                           generated, annotations))
                annotations, prefix = [], []
            elif kind == 'enum_constant':
                annotations = []
            elif kind in ('function_signature', 'getter_signature',
                          'setter_signature', 'method_signature'):
                body = None
                if index + 1 < len(children) and children[index + 1].type == 'function_body':
                    body = children[index + 1]
                    index += 1
                out.append(self._callable(node, body, rel, library, container,
                                          generated, annotations))
                annotations, prefix = [], []
            elif kind == 'declaration':
                out.extend(self._declaration(node, rel, library, container,
                                             generated, annotations))
                annotations, prefix = [], []
            elif kind in ('static_final_declaration_list', 'initialized_identifier_list'):
                out.extend(self._variables(node, prefix, rel, library, container,
                                           generated, annotations))
                annotations, prefix = [], []
            else:
                prefix.append(node)
            index += 1

    def _new(self, rel, library, name, kind, node, container, generated, annotations):
        decl = Decl(rel, library, name, kind, node.start_point[0] + 1,
                    container=container, generated=generated)
        for annotation in annotations:
            decl.refs |= _idents(annotation)
            text = annotation.text.decode()
            if text.startswith('@override'):
                decl.with_container = True
            if 'vm:entry-point' in text:
                decl.root = True
            if text.startswith('@visibleForTesting'):
                decl.visible_for_testing = True
        if container is not None and name in IMPLICIT_MEMBERS:
            decl.with_container = True
        if container is not None:
            container.members.append(decl)
        return decl

    def _container(self, node, rel, library, container, generated, annotations):
        kind = CONTAINER_TYPES.get(node.type, 'typedef')
        name_node = node.child_by_field_name('name')
        if name_node is None:
            name_node = _first(node, 'identifier') if kind != 'typedef' else _first(node, 'type_identifier')
        if kind == 'extension' and (name_node is None or node.children.index(name_node) > 2):
            name_node = None
        name = name_node.text.decode() if name_node is not None else '<unnamed extension>'
        decl = self._new(rel, library, name, kind, node, container, generated, annotations)
        for child in node.children:
            if child.type in BODY_TYPES:
                self._scope(child.children, rel, library, decl, generated, [])
            elif child is not name_node:
                decl.refs |= _idents(child)
                decl.strings |= _strings(child)
        return decl

    def _callable(self, signature, body, rel, library, container, generated, annotations):
        inner = signature
        if signature.type == 'method_signature':
            inner = next((c for c in signature.children if c.is_named), signature)
        names = [c for c in inner.children if c.type == 'identifier']
        kind = {
            'getter_signature': 'getter', 'setter_signature': 'setter',
            'operator_signature': 'operator',
            'factory_constructor_signature': 'constructor',
            'constructor_signature': 'constructor',
            'constant_constructor_signature': 'constructor',
        }.get(inner.type, 'function' if container is None else 'method')
        name_node = inner.child_by_field_name('name')
        if kind == 'constructor':
            name_node = names[1] if len(names) > 1 else None
        elif name_node is None and names:
            name_node = names[0]
        name = name_node.text.decode() if name_node is not None else (
            'operator' if kind == 'operator' else '<constructor>')
        decl = self._new(rel, library, name, kind, signature, container,
                         generated, annotations)
        if kind == 'operator' or (kind == 'constructor' and name_node is None):
            decl.with_container = True
        if container is None and name == 'main' and rel == 'lib/main.dart':
            decl.root = True
        for part in (signature, body):
            if part is None:
                continue
            decl.refs |= _idents(part, skip=name_node)
            decl.strings |= _strings(part)
        if container is not None and names and kind == 'constructor':
            decl.refs.discard(names[0].text.decode())
        return decl

    def _declaration(self, node, rel, library, container, generated, annotations):
        named = [c for c in node.children if c.is_named]
        if named and named[0].type.endswith(('constructor_signature',)) or any(
                c.type in ('constructor_signature', 'constant_constructor_signature',
                           'factory_constructor_signature', 'redirecting_factory_constructor_signature')
                for c in named):
            sig = next(c for c in named if c.type.endswith('constructor_signature'))
            decl = self._callable(sig, None, rel, library, container, generated, annotations)
            for c in named:
                if c is not sig:
                    decl.refs |= _idents(c)
                    decl.strings |= _strings(c)
            return [decl]
        for c in named:
            if c.type in ('function_signature', 'getter_signature', 'setter_signature',
                          'operator_signature'):
                return [self._callable(c, None, rel, library, container, generated, annotations)]
        lists = [c for c in named if c.type in ('static_final_declaration_list',
                                                 'initialized_identifier_list')]
        prefix = [c for c in named if c not in lists]
        out = []
        for lst in lists:
            out.extend(self._variables(lst, prefix, rel, library, container,
                                       generated, annotations))
        return out

    def _variables(self, lst, prefix, rel, library, container, generated, annotations):
        type_refs: set[str] = set()
        for p in prefix:
            type_refs |= _idents(p)
        out = []
        for item in lst.children:
            if not item.is_named:
                continue
            name_node = _first(item, 'identifier')
            if name_node is None:
                continue
            kind = 'field' if container is not None else 'variable'
            decl = self._new(rel, library, name_node.text.decode(), kind, item,
                             container, generated, annotations)
            init = _idents(item, skip=name_node)
            decl.refs |= type_refs | init
            decl.strings |= _strings(item)
            if container is not None:
                decl.init_refs = init
            out.append(decl)
        return out


def _first(node, kind):
    for child in node.children:
        if child.type == kind:
            return child
    return None


def _descendant(node, kind):
    stack = [node]
    while stack:
        current = stack.pop()
        if current.type == kind:
            return current
        stack.extend(reversed(current.children))
    return None


def _idents(node, skip=None) -> set[str]:
    found: set[str] = set()
    stack = [node]
    while stack:
        current = stack.pop()
        if current is skip:
            continue
        if current.type in IDENT_TYPES:
            found.add(current.text.decode())
            continue
        if current.type in ('documentation_comment', 'comment'):
            continue
        stack.extend(current.children)
    return found


_PLAIN_STRING = re.compile(r"""^r?(['"]{1,3})([A-Za-z_][A-Za-z0-9_]*)\1$""")


def _strings(node) -> set[str]:
    found: set[str] = set()
    stack = [node]
    while stack:
        current = stack.pop()
        if current.type == 'string_literal':
            match = _PLAIN_STRING.match(current.text.decode())
            if match:
                found.add(match.group(2))
        stack.extend(current.children)
    return found


def _unquote(text: str) -> str:
    return text.strip().strip('\'"')


def _resolve_relative(rel: str, target: str) -> str:
    if target.startswith('package:'):
        _, _, rest = target.partition('/')
        return 'lib/' + rest
    return str((Path(rel).parent / target)).replace('\\', '/')


class Analysis:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.decls: list[Decl] = []
        self.by_name: dict[str, list[Decl]] = {}
        self.files: list[str] = []

    def load(self) -> None:
        parser = Parser()
        lib = self.root / 'lib'
        parsed = {}
        for path in sorted(lib.rglob('*.dart')):
            rel = path.relative_to(self.root).as_posix()
            if rel.startswith('lib/l10n/app_localizations'):
                continue  # generated from ARB; keys are checked separately
            parsed[rel] = parser.parse(path, rel, rel)
        owner: dict[str, str] = {}
        for rel, (_, part_of, parts) in parsed.items():
            for part in parts:
                owner[_resolve_relative(rel, part)] = rel
        for rel, (decls, part_of, _) in parsed.items():
            library = owner.get(rel) or (
                _resolve_relative(rel, part_of) if part_of and part_of.endswith('.dart') else rel)
            self.files.append(rel)
            for decl in _walk(decls):
                decl.library = library
                self.decls.append(decl)
        for decl in self.decls:
            self.by_name.setdefault(decl.name, []).append(decl)

    def solve(self) -> set[int]:
        live: set[int] = set()
        used: set[tuple[str, str]] = set()  # (name, library or '*')
        queue: list[Decl] = []

        def is_used(decl: Decl) -> bool:
            scope = decl.library if decl.name.startswith('_') else '*'
            return (decl.name, scope) in used

        def container_live(decl: Decl) -> bool:
            c = decl.container
            return c is None or c.kind == 'extension' or id(c) in live

        def mark(decl: Decl) -> None:
            if id(decl) in live:
                return
            live.add(id(decl))
            queue.append(decl)

        for decl in self.decls:
            if decl.root:
                mark(decl)
        while queue:
            decl = queue.pop()
            for name in decl.refs:
                scope = decl.library if name.startswith('_') else '*'
                if (name, scope) in used:
                    continue
                used.add((name, scope))
                for target in self.by_name.get(name, ()):
                    if scope != '*' and target.library != decl.library:
                        continue
                    if container_live(target):
                        mark(target)
            if decl.container is not None and decl.container.kind == 'extension':
                mark(decl.container)
            if decl.kind in ('class', 'mixin', 'enum', 'extension'):
                for member in decl.members:
                    if member.with_container or is_used(member):
                        mark(member)
                    elif member.init_refs:
                        # Field initializers run on construction even if the
                        # field is never read.
                        carrier = Decl(member.file, member.library, '<init>', 'init',
                                       member.line, refs=set(member.init_refs))
                        mark(carrier)
        return live


def _walk(decls):
    for decl in decls:
        yield decl
        yield from _walk(decl.members)


def _test_identifiers(root: Path) -> set[str]:
    parser = get_parser('dart')
    names: set[str] = set()
    for folder in ('test', 'integration_test'):
        for path in sorted((root / folder).rglob('*.dart')) if (root / folder).exists() else ():
            names |= _idents(parser.parse(path.read_bytes()).root_node)
    return names


def find_dead(root: Path) -> dict:
    analysis = Analysis(root)
    analysis.load()
    live = analysis.solve()
    test_names = _test_identifiers(root)

    live_strings: set[str] = set()
    live_names: set[str] = set()
    for decl in analysis.decls:
        if id(decl) in live:
            live_strings |= decl.strings
            live_names |= decl.refs

    findings = []
    files: dict[str, list[Decl]] = {}
    for decl in analysis.decls:
        files.setdefault(decl.file, []).append(decl)
    dead_files = []
    for rel in sorted(files):
        top = [d for d in files[rel] if d.container is None]
        if top and not any(id(d) in live for d in top) and not rel.endswith(GENERATED_SUFFIXES):
            dead_files.append(rel)
    for decl in analysis.decls:
        if id(decl) in live or decl.generated or decl.file in dead_files:
            continue
        if decl.kind == 'extension' and decl.name.startswith('<'):
            continue
        if decl.container is not None:
            c = decl.container
            if c.kind != 'extension' and id(c) not in live:
                continue  # reported through its container
            if c.kind == 'extension' and id(c) not in live and not c.name.startswith('<'):
                continue
            if decl.with_container:
                continue
        if decl.kind == 'constructor' and decl.name == '_':
            continue  # private constructor that blocks instantiation
        findings.append({
            'key': decl.key,
            'file': decl.file,
            'line': decl.line,
            'kind': decl.kind,
            'name': decl.name if decl.container is None else f'{decl.container.name}.{decl.name}',
            'tests_only': decl.name in test_names,
            'test_hook': _is_test_hook(decl),
        })

    arb = root / 'lib/l10n/arb/app_en.arb'
    unused_keys = []
    if arb.exists():
        for key in json.loads(arb.read_text(encoding='utf-8')):
            if not key.startswith('@') and key not in live_names:
                unused_keys.append(key)

    channel = _channel_report(root, live_strings)
    return {
        'dead_files': dead_files,
        'declarations': findings,
        'unused_l10n_keys': sorted(unused_keys),
        'channel_handlers_without_dart_caller': channel,
    }


_WHEN = re.compile(r'when\s*\(\s*(?:call\.)?method\s*\)\s*\{')
_BRANCH = re.compile(r'^\s*((?:"[A-Za-z_]\w*"\s*,\s*)*"[A-Za-z_]\w*")\s*->', re.M)
_COMPARE = re.compile(r'(?:call\.)?method\s*[!=]=\s*"([A-Za-z_]\w*)"|"([A-Za-z_]\w*)"\s*[!=]=\s*(?:call\.)?method')


def _is_test_hook(decl: Decl) -> bool:
    """A seam that exists for tests on purpose, reported apart from dead code."""
    return (decl.visible_for_testing or decl.name.endswith('ForTesting')
            or (decl.name.startswith('debug') and decl.name[5:6].isupper()))


def _channel_report(root: Path, dart_strings: set[str]) -> list[dict]:
    handlers: dict[str, tuple[str, int]] = {}
    src = root / 'android/app/src'
    if not src.exists():
        return []
    for path in sorted(src.rglob('*.kt')):
        rel = path.relative_to(root).as_posix()
        if '/test/' in rel or '/androidTest/' in rel:
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        for match in _WHEN.finditer(text):
            start = match.end()
            depth, end = 1, start
            while end < len(text) and depth:
                depth += {'{': 1, '}': -1}.get(text[end], 0)
                end += 1
            block = text[start:end]
            # Only top-level branches of this when block.
            level = 0
            for line_start, line in _lines(block, start):
                if level == 0:
                    m = _BRANCH.match(line)
                    if m:
                        for name in re.findall(r'"(\w+)"', m.group(1)):
                            handlers.setdefault(name, (rel, text.count('\n', 0, line_start) + 1))
                level += line.count('{') - line.count('}')
        for m in _COMPARE.finditer(text):
            name = m.group(1) or m.group(2)
            handlers.setdefault(name, (rel, text.count('\n', 0, m.start()) + 1))
    return [
        {'method': name, 'file': rel, 'line': line}
        for name, (rel, line) in sorted(handlers.items())
        if name not in dart_strings
    ]


def _lines(block: str, offset: int):
    position = 0
    for line in block.split('\n'):
        yield offset + position, line
        position += len(line) + 1


def _allowlist() -> set[str]:
    if not ALLOWLIST.exists():
        return set()
    return {
        line.split('#', 1)[0].strip()
        for line in ALLOWLIST.read_text().splitlines()
        if line.split('#', 1)[0].strip()
    }


def _ids(report: dict) -> list[str]:
    return ([f'file:{f}' for f in report['dead_files']] +
            [f'decl:{d["key"]}' for d in report['declarations'] if not d['test_hook']] +
            [f'l10n:{k}' for k in report['unused_l10n_keys']] +
            [f'channel:{c["method"]}' for c in report['channel_handlers_without_dart_caller']])


def _print(report: dict) -> None:
    decls = report['declarations']
    print(f'Dead files ({len(report["dead_files"])}):')
    for f in report['dead_files']:
        print(f'  {f}')
    dead = [d for d in decls if not d['test_hook']]
    hooks = [d for d in decls if d['test_hook']]
    for title, rows in ((f'Unreachable declarations ({len(dead)}):', dead),
                        (f'Test hooks production never calls ({len(hooks)}), '
                         'not counted by --check:', hooks)):
        print('\n' + title)
        current = None
        for d in sorted(rows, key=lambda d: (d['file'], d['line'])):
            if d['file'] != current:
                current = d['file']
                print(f'  {current}')
            mark = '  [used by tests]' if d['tests_only'] and not d['test_hook'] else ''
            print(f'    {d["line"]:>5}  {d["kind"]:<11} {d["name"]}{mark}')
    keys = report['unused_l10n_keys']
    print(f'\nUnused ARB keys ({len(keys)}):')
    for k in keys:
        print(f'  {k}')
    ch = report['channel_handlers_without_dart_caller']
    print(f'\nKotlin channel handlers with no reachable Dart caller ({len(ch)}):')
    for c in ch:
        print(f'  {c["method"]:<40} {c["file"]}:{c["line"]}')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--check', action='store_true',
                        help='exit 1 when a finding is not in the allowlist')
    args = parser.parse_args(argv)
    report = find_dead(args.root.resolve())
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        _print(report)
    if args.check:
        new = [i for i in _ids(report) if i not in _allowlist()]
        if new:
            print(f'\n{len(new)} finding(s) not in {ALLOWLIST.name}:', file=sys.stderr)
            for i in new:
                print(f'  {i}', file=sys.stderr)
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
