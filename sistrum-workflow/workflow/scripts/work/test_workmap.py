"""Tests for the code map and task context (workmap.py) on throwaway git repositories.

MockedAdapter* classes use fixtures/fake_graphify_adapter.py (no Graphify needed).
RealGraphify* classes run the pinned Graphify and are skipped when it is not installed.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parents[2]
FAKE = HERE / 'fixtures/fake_graphify_adapter.py'
MOCK_ENV = {'WORK_MAP_ADAPTER': str(FAKE), 'WORK_GRAPHIFY_PYTHON': sys.executable, 'WORK_MAP_LOCK_TIMEOUT': '5'}
os.environ.update(MOCK_ENV)  # every test in this process uses the mock unless it says otherwise
for name in ('FAKE_GRAPHIFY', 'FAKE_GRAPHIFY_VERSION', 'WORK_MAP_STRUCTURE'):
    os.environ.pop(name, None)

spec = importlib.util.spec_from_file_location('work', HERE / 'work.py')
work = importlib.util.module_from_spec(spec)
spec.loader.exec_module(work)
workmap = sys.modules['workmap']
Blocked = work.Blocked

PLAYER_DART = """import 'package:flutter/services.dart';
import 'queue.dart';

const _channel = MethodChannel('com.example/player');

class PlayerBridge {
  PlayerBridge(this.queue);
  final Queue queue;

  Future<void> play(String id) async {
    queue.add(id);
    await _channel.invokeMethod<void>('play', {'id': id});
  }

  Future<void> pause() => _channel.invokeMethod('pause');

  Future<void> raw(String name) => _channel.invokeMethod(name);
}
"""
QUEUE_DART = """class Queue {
  final items = <String>[];
  void add(String id) {
    items.add(id);
  }
}
"""
NATIVE_DART = """import 'package:flutter/services.dart';

const nativeBackendChannel = MethodChannel('com.example/backend');

Future<Object?> nativeInvoke(String method, [Object? args]) =>
    nativeBackendChannel.invokeMethod(method, args);
"""
LIBRARY_DART = """import 'native_channel.dart';

Future<void> scan() => nativeInvoke('scanLibrary');
"""
EVENTS_DART = """import 'package:flutter/services.dart';

class Progress {
  Progress({EventChannel? events}) : _events = events ?? const EventChannel('com.example/progress');
  final EventChannel _events;
  Stream<dynamic> watch() => _events.receiveBroadcastStream();
}
"""
PLUGIN_KT = """package com.example.app

import io.flutter.plugin.common.MethodChannel
import com.example.app.engine.Engine

class PlayerPlugin(private val engine: Engine) {
    private val CHANNEL = "com.example/player"

    fun attach(messenger: Any) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> { engine.start(); result.success(null) }
                "seek", "stop" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
"""
ENGINE_KT = """package com.example.app.engine

class Engine {
    fun start() { prepare() }
    private fun prepare() {}
}
"""
BACKEND_KT = """package com.example.app

import io.flutter.plugin.common.MethodChannel

class Backend {
    fun attach(messenger: Any) {
        MethodChannel(messenger, "com.example/backend").setMethodCallHandler { call, result ->
            if (call.method == "scanLibrary") result.success(null) else dispatchOther(call, result)
        }
    }
}
"""
EVENTS_KT = """package com.example.app

import io.flutter.plugin.common.EventChannel

class ProgressStream {
    fun attach(messenger: Any) {
        val events = EventChannel(messenger, "com.example/progress")
        events.setStreamHandler(null)
    }
}
"""
AMBIGUOUS_KT = """package com.example.app

import io.flutter.plugin.common.MethodChannel

class Twins {
    fun attach(messenger: Any) {
        val a = MethodChannel(messenger, "com.example/a")
        val b = MethodChannel(messenger, nameFor())
    }
    fun handle(call: MethodCall) {
        if (call.method == "ping") return
    }
}
"""
PLAYER_TEST = """import 'package:fixture/player/player_bridge.dart';
import 'package:fixture/player/queue.dart';

void main() { PlayerBridge(Queue()).play('a'); }
"""
ENGINE_TEST = """package com.example.app.engine

import com.example.app.engine.Engine

class EngineTest {
    fun startsPrepared() { Engine().start() }
}
"""
FIXTURE = {
    'pubspec.yaml': 'name: fixture\n',
    'lib/player/player_bridge.dart': PLAYER_DART,
    'lib/player/queue.dart': QUEUE_DART,
    'lib/native/native_channel.dart': NATIVE_DART,
    'lib/native/library_bridge.dart': LIBRARY_DART,
    'lib/progress/progress.dart': EVENTS_DART,
    'android/app/src/main/kotlin/com/example/app/PlayerPlugin.kt': PLUGIN_KT,
    'android/app/src/main/kotlin/com/example/app/engine/Engine.kt': ENGINE_KT,
    'android/app/src/main/kotlin/com/example/app/Backend.kt': BACKEND_KT,
    'android/app/src/main/kotlin/com/example/app/ProgressStream.kt': EVENTS_KT,
    'android/app/src/main/kotlin/com/example/app/Twins.kt': AMBIGUOUS_KT,
    'test/player/player_bridge_test.dart': PLAYER_TEST,
    'android/app/src/test/kotlin/com/example/app/engine/EngineTest.kt': ENGINE_TEST,
    'lib/core/generated.g.dart': 'class Generated {}\n',
    'test/fixtures/backend_calls.json': '{"channel": "com.example/backend", "method": "scanLibrary"}\n',
}
ENGINE = 'android/app/src/main/kotlin/com/example/app/engine/Engine.kt'
PLUGIN = 'android/app/src/main/kotlin/com/example/app/PlayerPlugin.kt'


def sh(root, *argv):
    return subprocess.run(argv, cwd=root, check=True, capture_output=True, text=True).stdout


def install(target: Path):
    """Copy the package as the README says: AGENTS.md and workflow/ into the repository root."""
    shutil.copy2(PACKAGE / 'AGENTS.md', target / 'AGENTS.md')
    shutil.copy2(PACKAGE / '.gitignore', target / '.gitignore')
    shutil.copytree(PACKAGE / 'workflow', target / 'workflow',
                    ignore=shutil.ignore_patterns('__pycache__', '.work'))


class Repo(unittest.TestCase):
    files = FIXTURE
    structure_on = True  # Graphify is off by default; the adapter tests switch it on in their repo

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='map test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        sh(self.root, 'git', 'init', '-q')
        sh(self.root, 'git', 'config', 'user.email', 't@example.com')
        sh(self.root, 'git', 'config', 'user.name', 't')
        install(self.root)
        if self.structure_on:
            config_path = self.root / 'workflow/work/map.json'
            data = json.loads(config_path.read_text())
            data['extractor']['enabled'] = True
            config_path.write_text(json.dumps(data, indent=2))
        for path, text in self.files.items():
            self.write(path, text)
        self.commit('base')
        patcher = mock.patch.dict(os.environ, MOCK_ENV)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ('FAKE_GRAPHIFY', 'FAKE_GRAPHIFY_VERSION', 'WORK_MAP_STRUCTURE'):
            os.environ.pop(name, None)

    def write(self, path, text):
        full = self.root / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(text)

    def commit(self, message):
        sh(self.root, 'git', 'add', '--all')
        sh(self.root, 'git', 'commit', '-q', '-m', message)

    def update(self, **kwargs):
        return workmap.update(self.root, **kwargs)

    def data(self):
        return workmap.load_map(self.root)

    def state(self):
        return workmap.map_status(self.root)['state']

    def config(self, change):
        path = self.root / 'workflow/work/map.json'
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data, indent=2))


class DefaultOffTests(Repo):
    """The shipped configuration: no Graphify, no adapter, the map still builds and says so."""
    structure_on = False

    def test_default_config_disables_graphify_and_builds_without_it(self):
        self.assertFalse(json.loads((self.root / 'workflow/work/map.json').read_text())['extractor']['enabled'])
        result = self.update()
        self.assertEqual(result['structure']['status'], 'disabled')
        self.assertEqual(self.state(), 'current')
        data = self.data()
        self.assertTrue(data['symbols'], 'Dart and Kotlin declarations come from the pattern scan')
        self.assertTrue(all(s['via'].endswith('-declaration') for s in data['symbols']))
        self.assertTrue(data['deps'], 'Dart and Kotlin imports still come from the pattern scans')
        self.assertFalse((self.root / '.work/map/graphify').exists())

    def test_type_qualified_calls_attribute_only_to_the_declared_owner(self):
        self.write('lib/b/store.dart', "class Store {\n  static Store open() {\n    return Store();\n  }\n"
                   "  void save() {}\n}\nclass Other {\n  void save() {}\n}\n")
        self.write('lib/b/use.dart', "import 'store.dart';\n\nvoid run(Store value) {\n  Store.open();\n"
                   "  value.save();\n}\n")
        self.update()
        edges = [e for e in self.data()['edges'] if e['file'] == 'lib/b/use.dart'
                 and e['via'] == 'adapter:dart-name-call (qualified)']
        by_id = {s['id']: s for s in self.data()['symbols']}
        self.assertEqual([(by_id[e['source']]['name'], by_id[e['target']]['name'], by_id[e['target']]['owner'])
                          for e in edges], [('run', 'open', 'Store')])
        self.assertEqual(edges[0]['line'], 4)
        self.assertFalse([e for e in self.data()['edges'] if e['file'] == 'lib/b/use.dart'
                          and e['line'] == 5 and e['via'].startswith('adapter:dart-name-call')])

    def test_blast_radius_ranks_callers_and_reaches_tests(self):
        self.write('lib/a/core.dart', "class Core {\n  void work() {}\n}\n")
        self.write('lib/a/caller.dart', "import 'core.dart';\n\nvoid go1() {\n  work();\n  work();\n}\n")
        self.write('test/a/caller_test.dart', "import '../../lib/a/caller.dart';\n\nvoid main() {\n  go1();\n}\n")
        self.update()
        data = self.data()
        context = workmap.Context(self.root, data, workmap.load_config(self.root), workmap.map_status(self.root), None)
        symbol = next(s for s in data['symbols'] if s['name'] == 'work')
        text = '\n'.join(context.blast_radius(symbol))
        self.assertIn('2 call site(s) from 1 file(s)', text)
        self.assertIn('called by go1 at lib/a/caller.dart:4 (2 call site(s))', text)
        self.assertIn('test/a/caller_test.dart', text)

    def test_rust_python_and_swift_declarations_come_from_the_pattern_scan(self):
        self.write('rust/src/engine.rs', "pub struct Engine {\n    x: u8,\n}\nimpl Engine {\n    pub fn start(&self) -> u8 {\n"
                   "        1\n    }\n}\npub fn free() {}\n")
        self.write('py/player.py', "class Player:\n    def play(self, track):\n        pass\n\ndef helper():\n    return 1\n")
        self.write('ios/Store.swift', "public final class Store {\n    func save() {}\n}\nfunc top() {}\n")
        self.update()
        symbols = {(s['file'], s['name']): s for s in self.data()['symbols']}
        self.assertEqual(symbols[('rust/src/engine.rs', 'start')]['owner'], 'Engine')
        self.assertEqual(symbols[('py/player.py', 'play')]['owner'], 'Player')
        self.assertEqual(symbols[('ios/Store.swift', 'save')]['owner'], 'Store')
        self.assertIsNone(symbols[('py/player.py', 'helper')].get('owner'))
        self.assertTrue(all(s['via'].endswith('-declaration') for s in symbols.values()
                            if s['file'].split('.')[-1] in ('rs', 'py', 'swift')))

    def test_pattern_declarations_include_multi_line_signatures(self):
        self.write('lib/a/wide.dart', "class Wide {\n  void report(\n    Object error,\n    int code,\n  ) {\n"
                   "    print(error);\n  }\n  void call(Object x) => report(x, 1);\n}\n")
        self.write('lib/a/wide_call.dart', "void drive() {\n  when(() {\n    x();\n  });\n}\n")
        self.update()
        names = {(s['file'], s['name']) for s in self.data()['symbols']}
        self.assertIn(('lib/a/wide.dart', 'report'), names)
        self.assertIn(('lib/a/wide.dart', 'call'), names)
        self.assertIn(('lib/a/wide.dart', 'Wide'), names)
        self.assertNotIn(('lib/a/wide_call.dart', 'when'), names)

    def test_name_calls_resolve_in_scope_before_the_corpus(self):
        self.write('lib/a/one.dart', "class One {\n  void run() {\n    helper();\n  }\n  void helper() {}\n}\n")
        self.write('lib/b/two.dart', "class Two {\n  void helper() {}\n}\n")
        self.update()
        calls = [e for e in self.data()['edges'] if e['via'] == 'adapter:dart-name-call (same file)'
                 and e['file'] == 'lib/a/one.dart']
        by_id = {s['id']: s for s in self.data()['symbols']}
        self.assertTrue(calls)
        self.assertEqual({by_id[e['target']]['file'] for e in calls}, {'lib/a/one.dart'})
        self.assertFalse([e for e in self.data()['edges'] if e['via'].startswith('adapter:dart-name-call')
                          and e['file'] == 'lib/a/one.dart' and e['target_file'] == 'lib/b/two.dart'])


class MockedAdapterFreshnessTests(Repo):
    def test_missing_map_is_reported_then_built(self):
        self.assertEqual(self.state(), 'missing')
        result = self.update()
        self.assertTrue(result['rebuilt'])
        self.assertEqual(self.state(), 'current')
        self.assertEqual(self.data()['meta']['structure']['status'], 'graphify')

    def test_current_map_is_not_rebuilt(self):
        log = self.root.parent / f'{self.root.name}.log'
        os.environ['FAKE_GRAPHIFY_LOG'] = str(log)
        self.addCleanup(os.environ.pop, 'FAKE_GRAPHIFY_LOG', None)
        self.update()
        self.assertFalse(self.update()['rebuilt'])
        self.assertEqual(log.read_text().count('extract'), 1)
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        self.assertTrue(self.update()['rebuilt'])
        self.assertEqual(log.read_text().count('extract'), 2)

    def test_edits_additions_renames_and_deletions_make_the_map_stale(self):
        self.update()
        cases = [
            (lambda: self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n'), 'modified'),
            (lambda: self.write('lib/player/extra.dart', 'class Extra {}\n'), 'added'),
            (lambda: sh(self.root, 'git', 'mv', ENGINE, ENGINE.replace('Engine.kt', 'AudioEngine.kt')), 'removed'),
            (lambda: (self.root / 'lib/player/extra.dart').unlink(), 'removed'),
        ]
        for change, kind in cases:
            with self.subTest(kind=kind):
                change()
                status = workmap.map_status(self.root)
                self.assertEqual(status['state'], 'stale')
                self.assertTrue(status['changed'][kind])
                self.update()
                self.assertEqual(self.state(), 'current')

    def test_committing_does_not_make_the_map_stale(self):
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        self.update()
        self.commit('edit')
        self.assertEqual(self.state(), 'current')

    def test_generated_ignored_and_workflow_files_are_not_indexed(self):
        self.write('build/out.dart', 'class Built {}\n')
        (self.root / '.gitignore').write_text((self.root / '.gitignore').read_text() + 'build/\n')
        self.update()
        files = self.data()['files']
        self.assertNotIn('lib/core/generated.g.dart', files)
        self.assertNotIn('build/out.dart', files)
        self.assertFalse(any(p.startswith(('workflow/', '.work/')) for p in files))
        before = workmap.map_status(self.root)['digest']
        (self.root / '.work/map/extra.txt').write_text('generated output never feeds the map')
        self.assertEqual(before, workmap.map_status(self.root)['digest'])

    def test_exception_includes_an_excluded_path(self):
        self.config(lambda c: c['corpus'].update(exceptions=['lib/core/generated.g.dart']))
        self.update()
        self.assertIn('lib/core/generated.g.dart', self.data()['files'])

    def test_configuration_changes_make_the_map_stale(self):
        self.update()
        self.config(lambda c: c['corpus']['exclude'].append('lib/native/*'))
        status = workmap.map_status(self.root)
        self.assertEqual(status['state'], 'stale')
        self.assertTrue(any('map.json' in reason for reason in status['reasons']))
        self.update()
        self.assertNotIn('lib/native/native_channel.dart', self.data()['files'])

    def test_extractor_version_change_makes_the_map_stale_and_unverified_versions_are_not_used(self):
        self.update()
        os.environ['FAKE_GRAPHIFY_VERSION'] = '0.9.99'
        status = workmap.map_status(self.root)
        self.assertEqual(status['state'], 'stale')
        self.assertIn('extractor availability or version changed', status['reasons'])
        self.update()
        data = self.data()
        self.assertEqual(data['meta']['structure']['status'], 'unverified')
        self.assertEqual([s for s in data['symbols'] if s['via'].startswith('graphify')], [])
        self.config(lambda c: c['extractor'].update(allow_unverified=True))
        self.update()
        self.assertTrue(self.data()['symbols'])

    def test_missing_extractor_still_builds_a_labelled_companion_map(self):
        os.environ['FAKE_GRAPHIFY'] = 'missing'
        self.update()
        data = self.data()
        self.assertEqual(data['meta']['structure']['status'], 'unavailable')
        self.assertEqual([s for s in data['symbols'] if s['via'].startswith('graphify')], [])
        self.assertIn('com.example/player', data['bridges']['channels'])
        self.assertTrue(data['deps'])
        text = workmap.context(self.root, 'player bridge play')['text']
        self.assertIn('Graphify not used', text)

    def test_disabled_structure_is_explicit(self):
        os.environ['WORK_MAP_STRUCTURE'] = 'off'
        self.update()
        self.assertEqual(self.data()['meta']['structure']['status'], 'disabled')

    def test_empty_repository_is_supported(self):
        for path in FIXTURE:
            (self.root / path).unlink()
        self.update()
        data = self.data()
        self.assertEqual(data['meta']['structure']['status'], 'empty')
        self.assertEqual((data['symbols'], data['deps'], data['bridges']['channels']), ([], [], {}))
        text = workmap.context(self.root, 'anything at all')['text']
        self.assertIn('FALLBACK', text)


class MockedAdapterPublicationTests(Repo):
    def test_failed_update_keeps_the_last_map_and_marks_it_stale(self):
        self.update()
        published = (self.root / '.work/map/map.json').read_bytes()
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        os.environ['FAKE_GRAPHIFY'] = 'fail'
        with self.assertRaisesRegex(Blocked, 'graphify extraction failed'):
            self.update()
        self.assertEqual(published, (self.root / '.work/map/map.json').read_bytes())
        status = workmap.map_status(self.root)
        self.assertEqual(status['state'], 'stale')
        self.assertIn('crashed', status['last_failure']['reason'])
        self.assertTrue(any('last map update failed' in p for p in workmap.gate_problems(self.root)))
        text = workmap.context(self.root, 'queue add')['text']
        self.assertIn('STALE', text)
        self.assertIn('Map update FAILED', text)
        self.assertIn('lib/player/queue.dart', text)
        os.environ.pop('FAKE_GRAPHIFY')
        self.update()
        self.assertIsNone(workmap.map_status(self.root).get('last_failure'))

    def test_malformed_extractor_output_is_rejected(self):
        os.environ['FAKE_GRAPHIFY'] = 'garbage'
        with self.assertRaisesRegex(Blocked, 'schema'):
            self.update()
        self.assertEqual(self.state(), 'missing')

    def test_timeout_is_a_failure(self):
        os.environ['FAKE_GRAPHIFY'] = 'hang'
        self.config(lambda c: c['extractor'].update(timeout=1))
        with self.assertRaisesRegex(Blocked, 'timed out'):
            self.update()
        self.assertEqual(self.state(), 'missing')

    def test_sources_changed_during_update_are_not_published(self):
        os.environ['FAKE_GRAPHIFY'] = 'touch'
        os.environ['FAKE_GRAPHIFY_TOUCH'] = 'lib/player/queue.dart'
        self.addCleanup(os.environ.pop, 'FAKE_GRAPHIFY_TOUCH', None)
        with self.assertRaisesRegex(Blocked, 'changed while the map was being built'):
            self.update()
        self.assertEqual(self.state(), 'missing')

    def test_a_held_lock_refuses_a_concurrent_update(self):
        with workmap.map_lock(self.root, 1):
            with self.assertRaisesRegex(Blocked, 'another map update'):
                self.update(timeout=0.3)
        self.update(timeout=1)
        self.assertEqual(self.state(), 'current')

    def test_map_and_state_must_match(self):
        self.update()
        path = self.root / '.work/map/map.json'
        path.write_bytes(path.read_bytes() + b' ')
        self.assertEqual(self.state(), 'invalid')
        self.assertIsNone(self.data())


class MockedAdapterGraphTests(Repo):
    def test_deleted_and_renamed_code_leaves_no_stale_nodes_or_edges(self):
        self.update()
        old = self.data()
        self.assertTrue(any(s['file'] == ENGINE for s in old['symbols']))
        self.assertTrue(any(e['relation'] == 'calls' for e in old['edges']))
        renamed = ENGINE.replace('Engine.kt', 'AudioEngine.kt')
        sh(self.root, 'git', 'mv', ENGINE, renamed)
        self.update()
        data = self.data()
        ids = {s['id'] for s in data['symbols']}
        self.assertFalse(any(s['file'] == ENGINE for s in data['symbols']))
        self.assertTrue(any(s['file'] == renamed for s in data['symbols']))
        self.assertTrue(all(e['target'] is None or e['target'] in ids or e['target'].startswith('file:')
                            for e in data['edges']))
        self.assertFalse(any(ENGINE in json.dumps(e) for e in data['edges'] + data['deps']))
        (self.root / renamed).unlink()
        self.update()
        self.assertFalse(any(s['file'] == renamed for s in self.data()['symbols']))

    def test_dart_imports_are_resolved_to_files(self):
        self.update()
        deps = {(d['from'], d['to'], d['target']) for d in self.data()['deps']}
        self.assertIn(('lib/player/player_bridge.dart', 'lib/player/queue.dart', 'in_corpus'), deps)
        self.assertIn(('test/player/player_bridge_test.dart', 'lib/player/player_bridge.dart', 'in_corpus'), deps)
        self.assertIn(('lib/player/player_bridge.dart', None, 'external'), deps)

    def test_kotlin_imports_resolve_by_package(self):
        self.update()
        deps = [d for d in self.data()['deps'] if d['from'] == PLUGIN and d['to']]
        self.assertEqual([d['to'] for d in deps], [ENGINE])

    def test_tests_are_linked_with_provenance(self):
        self.update()
        tests = self.data()['tests']
        linked = {t['test']: t for t in tests['lib/player/player_bridge.dart']}
        self.assertEqual(linked['test/player/player_bridge_test.dart']['fact'], 'extracted')
        engine = {t['test']: t for t in tests[ENGINE]}
        self.assertIn('android/app/src/test/kotlin/com/example/app/engine/EngineTest.kt', engine)

    def test_part_files_inherit_their_library_tests(self):
        self.write('lib/player/queue_ops.dart', "part of 'queue.dart';\n\nvoid helper() {}\n")
        self.write('lib/player/queue.dart', "part 'queue_ops.dart';\n\n" + QUEUE_DART)
        self.update()
        tests = self.data()['tests']['lib/player/queue_ops.dart']
        self.assertTrue(any('via library lib/player/queue.dart' in t['via'] for t in tests))


class MockedAdapterBridgeTests(Repo):
    def channels(self):
        self.update()
        return self.data()['bridges']

    def test_both_sides_and_commands_are_linked(self):
        player = self.channels()['channels']['com.example/player']
        self.assertEqual(player['status'], 'linked')
        self.assertEqual([e['file'] for e in player['dart']], ['lib/player/player_bridge.dart'])
        self.assertEqual([e['file'] for e in player['kotlin']], [PLUGIN])
        self.assertEqual(player['kotlin'][0]['resolved_by'], 'constant in file')
        commands = player['commands']
        self.assertEqual(commands['play']['status'], 'linked')
        self.assertEqual(commands['pause']['status'], 'no_kotlin_handler_found')
        self.assertEqual(commands['seek']['status'], 'no_dart_caller_found')
        self.assertIn('stop', commands)
        self.assertNotIn('else', commands)
        self.assertTrue(any('command name is' in d['detail'] for d in player['dynamic']))
        self.assertEqual(player['tests'], [])  # no test names the channel: reported, not invented
        backend = self.channels()['channels']['com.example/backend']
        self.assertEqual([t['file'] for t in backend['tests']], ['test/fixtures/backend_calls.json'])
        self.assertEqual(backend['tests'][0]['fact'], 'inferred')

    def test_dynamic_and_ambiguous_names_are_reported_not_guessed(self):
        bridges = self.channels()
        unresolved = [u['detail'] for u in bridges['unresolved']]
        self.assertTrue(any("'nameFor'" in d for d in unresolved), unresolved)
        self.assertTrue(any('"ping"' in d and 'candidates' in d for d in unresolved) or
                        bridges['channels']['com.example/a']['commands']['ping']['kotlin'][0]['fact'] == 'inferred')
        backend = bridges['channels']['com.example/backend']
        self.assertTrue(any('dispatchOther' in d['detail'] for d in backend['dynamic']))

    def test_interpolated_names_are_low_confidence(self):
        self.write('lib/player/dynamic.dart', "import 'package:flutter/services.dart';\n"
                   "MethodChannel forId(int id) => MethodChannel('com.example/events/$id');\n")
        entry = self.channels()['channels']['com.example/events/$id']['dart'][0]
        self.assertEqual(entry['confidence'], 'low')

    def test_wrappers_are_declared_in_configuration(self):
        backend = self.channels()['channels']['com.example/backend']
        self.assertEqual(backend['commands']['scanLibrary']['status'], 'no_dart_caller_found')
        self.config(lambda c: c['bridges'].update(dart_wrappers=[{'function': 'nativeInvoke',
                                                                  'channel': 'com.example/backend'}]))
        command = self.channels()['channels']['com.example/backend']['commands']['scanLibrary']
        self.assertEqual(command['status'], 'linked')
        self.assertIn('map.json', command['dart'][0]['via'])

    def test_event_channels_link_listener_and_producer(self):
        progress = self.channels()['channels']['com.example/progress']
        self.assertEqual(progress['kind'], 'event')
        self.assertEqual(progress['status'], 'linked')
        self.assertEqual([e['file'] for e in progress['listeners']], ['lib/progress/progress.dart'])
        self.assertEqual(progress['producers'], [])  # setStreamHandler(null) removes, it does not produce


class MockedAdapterDeclarationTests(Repo):
    ARCH = {'version': 1, 'modules': [
        {'id': 'player', 'paths': ['lib/player/*'], 'responsibility': 'Dart playback client', 'owns': ['queue'],
         'may_depend_on': [], 'status': 'reviewed', 'source': 'owner, 2026-10-31'},
        {'id': 'native', 'paths': ['lib/native/*'], 'responsibility': 'channel adapter', 'status': 'proposed',
         'source': 'draft'}],
        'constraints': [{'id': 'C1', 'rule': 'player code does not use platform services directly',
                         'applies_to': ['player'], 'forbid_imports': ['package:flutter/services.dart'],
                         'status': 'reviewed', 'source': 'workflow/work/guides/architecture.md'}]}

    def test_reviewed_declarations_survive_rebuilds_and_are_never_written(self):
        path = self.root / workmap.ARCHITECTURE
        path.write_text(json.dumps(self.ARCH, indent=2))
        before = path.read_bytes()
        self.update()
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        self.update(force=True)
        self.assertEqual(before, path.read_bytes())
        declarations = self.data()['declarations']
        self.assertEqual(declarations['membership']['lib/player/queue.dart'], ['player'])
        rules = [v['rule'] for v in declarations['violations']]
        self.assertTrue(any(r.startswith('C1') for r in rules), rules)
        text = workmap.context(self.root, '', files=['lib/player/player_bridge.dart'])['text']
        self.assertIn('module player [reviewed, owner, 2026-10-31]', text)
        self.assertIn('POSSIBLE VIOLATION', text)

    def test_a_module_whose_files_are_gone_is_kept_and_reported(self):
        arch = json.loads(json.dumps(self.ARCH))
        arch['modules'][1]['paths'] = ['lib/removed/*']
        (self.root / workmap.ARCHITECTURE).write_text(json.dumps(arch))
        self.update()
        data = self.data()
        self.assertIn('native', [m['id'] for m in data['declarations']['modules']])
        self.assertTrue(any('module native matches no corpus file' in p for p in data['problems']))

    def test_invalid_declarations_block_the_update(self):
        arch = json.loads(json.dumps(self.ARCH))
        arch['modules'][0]['status'] = 'approved-ish'
        (self.root / workmap.ARCHITECTURE).write_text(json.dumps(arch))
        with self.assertRaisesRegex(Blocked, 'status'):
            self.update()

    def test_bridge_contract_from_a_change_record_is_attached(self):
        folder = work.new_change(self.root, 'Player bridge', 'architecture')
        assurance = json.loads((folder / 'assurance.json').read_text())
        assurance['bridge'] = {'applies': True, 'reason': 'player commands', 'contracts': [{
            'name': 'com.example/player commands', 'caller': 'lib/player/player_bridge.dart PlayerBridge.play',
            'implementation': f'{PLUGIN} PlayerPlugin.attach', 'payload': 'id: String, required',
            'ordering': 'play after pause wins', 'ownership': 'PlayerPlugin', 'cancellation': 'none',
            'reconnect': 'snapshot on attach', 'errors': 'unknown id -> not_found',
            'caller_checks': ['dart-tests'], 'native_checks': ['android-unit']}]}
        (folder / 'assurance.json').write_text(json.dumps(assurance))
        self.update()
        contract = self.data()['declarations']['contracts'][0]
        self.assertEqual(contract['channels'], ['com.example/player'])
        self.assertEqual(contract['files'], sorted(['lib/player/player_bridge.dart', PLUGIN]))
        self.assertEqual(contract['fact'], 'declared')
        text = workmap.context(self.root, '', files=[PLUGIN])['text']
        self.assertIn("contract 'com.example/player commands'", text)
        self.assertIn('draft (plan not accepted)', text)
        self.assertIn('reconnect: snapshot on attach', text)
        state = work.read_state(folder)
        state['phase'] = 'tasks'
        work.write_state(folder, state)
        self.assertEqual(self.state(), 'current')  # a phase change is read live, not rebuilt
        self.assertIn('accepted plan', workmap.context(self.root, '', files=[PLUGIN])['text'])


class MockedAdapterContextTests(Repo):
    def test_both_bridge_sides_survive_a_tiny_budget(self):
        result = workmap.context(self.root, 'play command of the player bridge', budget=40)
        text = result['text']
        self.assertIn('lib/player/player_bridge.dart', text)
        self.assertIn(PLUGIN, text)
        self.assertIn('command "play"', text)
        self.assertTrue(result['data']['critical_over_budget'])

    def test_optional_sections_are_truncated_with_expansion_hints(self):
        for index in range(30):
            self.write(f'lib/player/user_{index}.dart', "import 'queue.dart';\nvoid use() {}\n")
        result = workmap.context(self.root, '', files=['lib/player/queue.dart'], budget=300)
        self.assertTrue(result['data']['truncated'])
        self.assertIn('--expand file:lib/player/queue.dart', result['text'])
        expanded = workmap.context(self.root, '', expand='file:lib/player/queue.dart', budget=6000)
        self.assertGreater(expanded['text'].count('imported by'), result['text'].count('imported by'))

    def test_expand_bridge_lists_every_command(self):
        text = workmap.context(self.root, '', expand='bridge:com.example/player')['text']
        for command in ('play', 'pause', 'seek', 'stop'):
            self.assertIn(f'command "{command}"', text)

    def test_ambiguous_symbols_are_listed_not_resolved(self):
        self.write('lib/other/engine.kt.dart', 'class Other {\n  void start() {}\n}\n')
        self.write('android/app/src/main/kotlin/com/example/app/Second.kt',
                   'package com.example.app\n\nclass Second {\n    fun start() {}\n}\n')
        result = workmap.context(self.root, '', symbols=['start'])
        self.assertIn("symbol 'start' is ambiguous", result['text'])
        self.assertGreaterEqual(len(result['data']['entries']), 2)

    def test_lexical_entries_are_labelled_and_paths_are_relative(self):
        text = workmap.context(self.root, 'queue add')['text']
        self.assertIn('lexical matches', text)
        self.assertNotIn(str(self.root), text)
        self.assertIn('lib/player/queue.dart', text)

    def test_unknown_words_fall_back_to_labelled_text_search(self):
        text = workmap.context(self.root, 'zzunknownword PlayerBridge')['text']
        self.assertIn('lib/player/player_bridge.dart', text)
        text = workmap.context(self.root, 'zzunknownword')['text']
        self.assertIn('FALLBACK', text)
        self.assertIn('NOT graph-verified', text)

    def test_without_a_map_and_without_refresh_the_fallback_is_explicit(self):
        result = workmap.context(self.root, 'PlayerBridge play', refresh=False)
        self.assertIn('Map: MISSING', result['text'])
        self.assertIn('FALLBACK', result['text'])
        self.assertTrue(result['data']['fallback'])

    def test_stale_map_is_labelled_when_not_refreshed(self):
        self.update()
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        text = workmap.context(self.root, 'queue add', refresh=False)['text']
        self.assertIn('STALE', text)
        self.assertIn('modified: lib/player/queue.dart', text)

    def test_context_refreshes_a_stale_map(self):
        self.update()
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        workmap.context(self.root, 'queue add')
        self.assertEqual(self.state(), 'current')

    def test_cli_context_and_map_commands(self):
        script = self.root / 'workflow/scripts/work/work.py'
        done = subprocess.run([sys.executable, str(script), 'map', 'update'], cwd=self.root, capture_output=True,
                              text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        done = subprocess.run([sys.executable, str(script), 'context', 'player bridge play', '--budget', '800'],
                              cwd=self.root, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn('## Bridges touched', done.stdout)
        self.assertTrue((self.root / '.work/map/context/latest.md').is_file())
        done = subprocess.run([sys.executable, str(script), 'context', '--json', '--symbol', 'Queue'], cwd=self.root,
                              capture_output=True, text=True)
        self.assertEqual(json.loads(done.stdout)['entries'][0]['file'], 'lib/player/queue.dart')


class MockedAdapterGapTests(Repo):
    """Behaviour added to close the known gaps: synonyms, critical tests and users, Dart name calls."""

    def test_synonyms_and_inflections_match_the_same_family(self):
        self.assertEqual(workmap.words('playbackFailure'), ['playback', 'error'])
        self.assertEqual(workmap.words('songs'), ['song'])
        self.assertIn('error', workmap.words('onErrorRetry'))

    def test_tests_of_entry_files_survive_a_tiny_budget(self):
        self.write('lib/player/extra_test_target.dart', 'class ExtraTarget {}\n')
        for index in range(4):
            self.write(f'test/player/extra_{index}_test.dart',
                       "import '../../lib/player/extra_test_target.dart';\nvoid main() {}\n")
        self.update()
        text = workmap.context(self.root, '', files=['lib/player/extra_test_target.dart'], budget=40)['text']
        self.assertIn('## Tests and checks (linked; first three per file, never cut)', text)
        self.assertEqual(text.count('- lib/player/extra_test_target.dart: test/player/extra_'), 3)

    def test_direct_users_of_an_entry_file_are_always_listed(self):
        text = workmap.context(self.root, '', files=['lib/player/queue.dart'], budget=40)['text']
        self.assertIn('lib/player/queue.dart is used by', text)
        self.assertIn('lib/player/player_bridge.dart:2 imports lib/player/queue.dart', text)

    def test_dart_calls_are_inferred_for_unqualified_calls_only(self):
        self.write('lib/player/caller.dart', "class Caller {\n  void drive() {\n    scheduleTrack();\n"
                   "    Other.scheduleTrack();\n  }\n  void scheduleTrack() {}\n}\n")
        self.update()
        calls = [e for e in self.data()['edges'] if e['via'].startswith('adapter:dart-name-call')
                 and e['file'] == 'lib/player/caller.dart']
        self.assertEqual(len(calls), 1, calls)
        self.assertEqual(calls[0]['line'], 3)
        self.assertEqual(calls[0]['fact'], 'inferred')
        self.assertEqual(calls[0]['via'], 'adapter:dart-name-call (same file)')
        symbols = {s['id']: s for s in self.data()['symbols']}
        self.assertEqual(symbols[calls[0]['source']]['name'], 'drive')
        self.assertEqual(symbols[calls[0]['source']]['lang'], 'dart')
        self.assertEqual(symbols[calls[0]['target']]['name'], 'scheduleTrack')


class MockedAdapterGateTests(Repo):
    def setUp(self):
        super().setUp()
        self.folder = work.new_change(self.root, 'Gate', 'feature')
        state = work.read_state(self.folder)
        state['phase'] = 'build'
        work.write_state(self.folder, state)

    def test_review_gate_reports_a_stale_map(self):
        self.update()
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        problems = work.lint_change(self.root, self.folder, 'review')
        self.assertTrue(any('code map is stale' in p for p in problems), problems)

    def test_advance_refreshes_the_map_and_fails_when_it_cannot(self):
        os.environ['FAKE_GRAPHIFY'] = 'fail'
        with self.assertRaisesRegex(Blocked, 'code map could not be refreshed'):
            work.advance(self.root, self.folder.name, 'review')
        os.environ.pop('FAKE_GRAPHIFY')
        with self.assertRaises(Blocked) as caught:  # other gate problems remain, the map one is gone
            work.advance(self.root, self.folder.name, 'review')
        self.assertNotIn('code map', str(caught.exception))
        self.assertEqual(self.state(), 'current')

    def test_clean_code_round_records_the_map_and_ship_checks_it(self):
        work.record_round(self.root, self.folder.name, 'code', 'clean', 'code-reviewer')
        entry = work.read_state(self.folder)['rounds'][-1]
        self.assertEqual(entry['map']['corpus'], workmap.map_status(self.root)['components']['corpus'])
        state = work.read_state(self.folder)
        del state['rounds'][-1]['map']
        work.write_state(self.folder, state)
        problems = work.lint_change(self.root, self.folder, 'ship')
        self.assertTrue(any('not recorded against the current code map' in p for p in problems), problems)

    def test_clean_round_cannot_be_recorded_without_a_current_map(self):
        os.environ['FAKE_GRAPHIFY'] = 'fail'
        with self.assertRaises(Blocked):
            work.record_round(self.root, self.folder.name, 'code', 'clean', 'code-reviewer')
        self.assertEqual(work.read_state(self.folder)['rounds'], [])
        work.record_round(self.root, self.folder.name, 'code', 'dirty', 'code-reviewer')  # findings need no map

    def test_check_run_refreshes_the_map_without_changing_its_verdict(self):
        config = work.load_config(self.root)
        config['checks'] = {'ok': {'run': [sys.executable, '-c', 'pass']}}
        report = work.run_checks(self.root, config, ['ok'])
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['map']['state'], 'current')
        os.environ['FAKE_GRAPHIFY'] = 'fail'
        self.write('lib/player/queue.dart', QUEUE_DART + '// edit\n')
        report = work.run_checks(self.root, config, ['ok'])
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['map']['state'], 'not current')

    def test_fresh_requires_current_checks_and_map(self):
        script = self.root / 'workflow/scripts/work/work.py'
        config = work.load_config(self.root)
        config['checks'] = {'ok': {'run': [sys.executable, '-c', 'pass']}}
        work.run_checks(self.root, config, ['ok'])
        fresh = lambda: json.loads(subprocess.run([sys.executable, str(script), 'fresh'], cwd=self.root,
                                                  capture_output=True, text=True).stdout)
        self.assertEqual(fresh()['status'], 'PASS')
        (self.root / '.work/map/state.json').unlink()
        self.assertEqual(fresh(), {'status': 'STALE_OR_INCOMPLETE', 'checks': 'fresh', 'map': 'missing'})

    def test_packet_includes_map_facts_for_changed_files(self):
        self.write(PLUGIN, PLUGIN_KT + '// edit\n')
        work.packet(self.root, 'HEAD', None, None, '.work/review/p.md')
        text = (self.root / '.work/review/p.md').read_text()
        self.assertIn('## Code map', text)
        self.assertIn('com.example/player', text)

    def test_status_shows_the_map(self):
        self.update()
        self.assertIn('Code map: current', work.status(self.root, True))


class MockedAdapterInstallTests(unittest.TestCase):
    def test_copying_agents_and_workflow_into_a_new_repository(self):
        with tempfile.TemporaryDirectory(prefix='install ') as temp:
            root = Path(temp)
            sh(root, 'git', 'init', '-q')
            install(root)
            (root / 'lib').mkdir()
            (root / 'lib/main.dart').write_text("void main() {}\n")
            sh(root, 'git', 'add', 'AGENTS.md', '.gitignore', 'workflow', 'lib')
            sh(root, 'git', '-c', 'user.email=t@e', '-c', 'user.name=t', 'commit', '-qm', 'install')
            script = ['python3' if shutil.which('python3') else sys.executable, 'workflow/scripts/work/work.py']
            env = {**os.environ, **MOCK_ENV}
            for argv in (['status'], ['map', 'update'], ['map', 'status'], ['context', 'main'], ['fresh']):
                done = subprocess.run(script + argv, cwd=root, capture_output=True, text=True, env=env)
                expected = (0, 1) if argv == ['fresh'] else (0,)
                self.assertIn(done.returncode, expected, f'{argv}: {done.stdout}{done.stderr}')
            self.assertIn('Code map: current', subprocess.run(script + ['status'], cwd=root, capture_output=True,
                                                              text=True, env=env).stdout)
            leftovers = sh(root, 'git', 'status', '--porcelain')
            self.assertEqual(leftovers, '', 'map commands must only write ignored .work/ files')


def real_graphify() -> str | None:
    """Reason to skip, or None when the pinned Graphify can run here."""
    pinned = json.loads((PACKAGE / 'workflow/work/map.json').read_text())['extractor']['version']
    with mock.patch.dict(os.environ, {}, clear=False):
        for name in MOCK_ENV:
            os.environ.pop(name, None)
        argv, _how = workmap.interpreter()
        if argv is None:
            return 'graphify is not installed'
        done = subprocess.run([*argv, str(workmap.ADAPTER), 'version'], capture_output=True, text=True)
    try:
        info = json.loads(done.stdout)
    except ValueError:
        return 'graphify adapter version check failed'
    if not info.get('available') or info.get('version') != pinned:
        return f'pinned graphifyy {pinned} not available ({info.get("version") or info.get("reason")})'
    return None


SKIP_REAL = real_graphify()


@unittest.skipIf(SKIP_REAL, SKIP_REAL or '')
class RealGraphifySmokeTests(Repo):
    """Runs the pinned Graphify through the real adapter: integration, not a mock."""

    def setUp(self):
        super().setUp()
        for name in ('WORK_MAP_ADAPTER', 'WORK_GRAPHIFY_PYTHON'):
            os.environ.pop(name, None)

    def test_real_extraction_of_dart_and_kotlin(self):
        result = self.update()
        self.assertEqual(result['structure']['status'], 'graphify')
        data = self.data()
        self.assertEqual(data['meta']['tool']['version'], json.loads(
            (self.root / 'workflow/work/map.json').read_text())['extractor']['version'])
        names = {(s['file'], s['name']) for s in data['symbols']}
        self.assertIn(('lib/player/player_bridge.dart', 'PlayerBridge'), names)
        self.assertIn((ENGINE, 'prepare'), names)
        calls = [e for e in data['edges'] if e['relation'] == 'calls' and e['via'] == 'graphify:kotlin-ast']
        by_id = {s['id']: s for s in data['symbols']}
        self.assertIn(('start', 'prepare'), {(by_id[e['source']]['name'], by_id[e['target']]['name'])
                                             for e in calls if e['source'] in by_id and e.get('target') in by_id})
        graphify_dart_calls = [e for e in data['edges'] if e['relation'] == 'calls' and e['file'].endswith('.dart')
                               and e['via'] == 'graphify:dart-regex']
        self.assertEqual(graphify_dart_calls, [], 'Graphify 0.9.97 emits no Dart call edges; update the docs if this changes')
        self.assertTrue((self.root / '.work/map/graphify/cache').is_dir())
        ignored = sh(self.root, 'git', 'status', '--porcelain', '--ignored')
        self.assertEqual(ignored.strip(), '!! .work/', 'Graphify must write only under .work/map/graphify')

    def test_real_update_removes_deleted_symbols(self):
        self.update()
        (self.root / ENGINE).unlink()
        self.update()
        data = self.data()
        self.assertFalse(any(s['file'] == ENGINE for s in data['symbols']))
        self.assertFalse(any(e['file'] == ENGINE for e in data['edges']))

    def test_real_extraction_needs_no_network(self):
        if not shutil.which('unshare') or subprocess.run(['unshare', '-n', 'true'], capture_output=True).returncode:
            self.skipTest('cannot create a network namespace here')
        argv, _how = workmap.interpreter()
        os.environ['WORK_GRAPHIFY_PYTHON'] = ' '.join(['unshare', '-n', *argv])
        self.assertEqual(self.update()['structure']['status'], 'graphify')


if __name__ == '__main__':
    unittest.main()
