#!/usr/bin/env python3
"""Regression tests for find_dead_code.py, run on disposable fixture projects."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import find_dead_code  # noqa: E402

MAIN = """
import 'package:app/live.dart';
part 'main_part.dart';

void main() {
  final service = LiveService();
  service.run();
  _helper();
}
"""

MAIN_PART = """
part of 'main.dart';

void _helper() => const _Private().go();

class _Private {
  const _Private();
  void go() {}
}
"""

LIVE = """
class LiveService {
  LiveService();
  void run() {
    print('value ${label}');
    channel.invokeMethod('ping');
    context.l10n.used;
  }
  String get label => 'x';
  void deadLeaf() => deadChainMiddle();
  @override
  String toString() => 'LiveService';
  @visibleForTesting
  void resetForTesting() {}
}

class Widget extends Base {
  @override
  void build() {}
}

void deadChainTop() => deadChainMiddle();
void deadChainMiddle() => deadChainBottom();
void deadChainBottom() {}

class TestOnly {
  void call2() {}
}

extension LiveExtension on String {
  String get shout => toUpperCase();
}
"""

DEAD_FILE = """
class Orphan {}
void orphanFunction() => Orphan();
"""

TEST = """
import 'package:app/live.dart';
void main() { TestOnly(); deadChainTop(); }
"""

KOTLIN = """
class MainActivity {
  fun handle(call: MethodCall) {
    when (call.method) {
      "ping" -> one()
      "orphanA", "orphanB" -> two()
      else -> {
        when (x) {
          "nested" -> three()
        }
      }
    }
    if (call.method == "compared") return
  }
}
"""

ARB = {'used': 'Used', '@used': {}, 'neverRead': 'Never'}


class FindDeadCodeTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='dead-code-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.write('lib/main.dart', MAIN)
        self.write('lib/main_part.dart', MAIN_PART)
        self.write('lib/live.dart', LIVE)
        self.write('lib/dead_file.dart', DEAD_FILE)
        self.write('test/live_test.dart', TEST)
        self.write('lib/l10n/arb/app_en.arb', json.dumps(ARB))
        self.write('android/app/src/main/kotlin/MainActivity.kt', KOTLIN)
        self.report = find_dead_code.find_dead(self.root)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def names(self):
        return {d['name'] for d in self.report['declarations']}

    def test_whole_dead_chain_is_reported_in_one_pass(self):
        self.assertTrue({'deadChainTop', 'deadChainMiddle', 'deadChainBottom'}
                        <= self.names())

    def test_dead_member_of_live_class_is_reported(self):
        self.assertIn('LiveService.deadLeaf', self.names())

    def test_live_code_is_not_reported(self):
        names = self.names()
        for live in ('LiveService', 'LiveService.run', 'LiveService.label',
                     'LiveService.toString', '_helper', '_Private', '_Private.go'):
            self.assertNotIn(live, names)

    def test_test_references_do_not_keep_code_alive(self):
        rows = {d['name']: d for d in self.report['declarations']}
        self.assertIn('TestOnly', rows)
        self.assertTrue(rows['TestOnly']['tests_only'])

    def test_test_hooks_are_separated(self):
        rows = {d['name']: d for d in self.report['declarations']}
        self.assertTrue(rows['LiveService.resetForTesting']['test_hook'])

    def test_override_of_dead_class_follows_its_class(self):
        names = self.names()
        self.assertIn('Widget', names)
        self.assertNotIn('Widget.build', names)  # reported through Widget

    def test_extension_without_live_members_is_reported_once(self):
        names = self.names()
        self.assertIn('LiveExtension', names)
        self.assertNotIn('LiveExtension.shout', names)

    def test_dead_file(self):
        self.assertEqual(self.report['dead_files'], ['lib/dead_file.dart'])

    def test_unused_arb_key(self):
        self.assertEqual(self.report['unused_l10n_keys'], ['neverRead'])

    def test_channel_handlers_without_dart_caller(self):
        methods = {c['method'] for c in
                   self.report['channel_handlers_without_dart_caller']}
        self.assertEqual(methods, {'orphanA', 'orphanB', 'compared'})


if __name__ == '__main__':
    unittest.main()
