"""Tests for work.py: evidence, gates, prove and guards, on throwaway git repositories."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parent / 'work.py'
PACKAGE = MODULE.parents[2]
# Map refreshes inside these tests use the mock extractor (test_workmap.py covers the real one).
os.environ.update({'WORK_MAP_ADAPTER': str(MODULE.parent / 'fixtures/fake_codegraph_adapter.py'),
                   'WORK_MAP_PYTHON': sys.executable, 'WORK_MAP_LOCK_TIMEOUT': '5'})
spec = importlib.util.spec_from_file_location('work', MODULE)
work = importlib.util.module_from_spec(spec)
spec.loader.exec_module(work)

PY = sys.executable


def sh(root, *argv):
    subprocess.run(argv, cwd=root, check=True, capture_output=True)


class Repo(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='work test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        sh(self.root, 'git', 'init', '-q')
        sh(self.root, 'git', 'config', 'user.email', 't@example.com')
        sh(self.root, 'git', 'config', 'user.name', 't')
        shutil.copytree(PACKAGE / 'work', self.root / 'workflow/work',
                        ignore=shutil.ignore_patterns('changes'))
        (self.root / '.gitignore').write_text('build/\n.work/\n')
        (self.root / 'lib').mkdir()
        (self.root / 'lib/app.dart').write_text('original\n')
        self.commit('base')

    def commit(self, message):
        sh(self.root, 'git', 'add', '--all')
        sh(self.root, 'git', 'commit', '-q', '-m', message)

    def write(self, path, text):
        full = self.root / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(text)

    def config(self, checks, domains=None, domain_checks=None):
        return {'checks': checks, 'domains': domains or {}, 'domain_checks': domain_checks or {}}


class FingerprintTests(Repo):
    def test_content_change_is_detected(self):
        before = work.fingerprint(self.root)
        self.write('lib/app.dart', 'changed\n')
        self.assertNotEqual(before, work.fingerprint(self.root))

    def test_untracked_and_deleted_files_count(self):
        before = work.fingerprint(self.root)
        self.write('lib/new.dart', 'x')
        self.assertNotEqual(before, work.fingerprint(self.root))
        (self.root / 'lib/new.dart').unlink()
        self.assertEqual(before, work.fingerprint(self.root))
        (self.root / 'lib/app.dart').unlink()
        self.assertNotEqual(before, work.fingerprint(self.root))

    def test_ignored_output_does_not_change_fingerprint(self):
        before = work.fingerprint(self.root)
        self.write('build/output.bin', 'generated')
        self.write('.work/runs/latest.json', '{}')
        self.assertEqual(before, work.fingerprint(self.root))

    def test_records_do_not_change_fingerprint(self):
        before = work.fingerprint(self.root)
        self.write('workflow/work/changes/001-x/log.md', 'entry')
        self.assertEqual(before, work.fingerprint(self.root))

    def test_check_configuration_changes_invalidate_fingerprint(self):
        before = work.fingerprint(self.root)
        config = json.loads((self.root / 'workflow/work/checks.json').read_text())
        config['checks']['analyze']['run'] = [PY, '-c', 'pass']
        self.write('workflow/work/checks.json', json.dumps(config))
        self.assertNotEqual(before, work.fingerprint(self.root))

    def test_check_configuration_deletion_invalidates_fingerprint(self):
        before = work.fingerprint(self.root)
        (self.root / 'workflow/work/checks.json').unlink()
        self.assertNotEqual(before, work.fingerprint(self.root))

    def test_committing_keeps_the_same_fingerprint(self):
        self.write('lib/app.dart', 'changed\n')
        before = work.fingerprint(self.root)
        self.commit('change')
        self.assertEqual(before, work.fingerprint(self.root))

    def test_real_index_is_untouched(self):
        self.write('lib/new.dart', 'x')
        work.fingerprint(self.root)
        status = subprocess.run(['git', 'status', '--porcelain'], cwd=self.root,
                                capture_output=True, text=True).stdout
        self.assertIn('?? lib/new.dart', status)


class ScopeTests(Repo):

    def test_auto_selects_checks_by_path(self):
        config = work.load_config(self.root)
        self.write('android/app/src/main/kotlin/MainActivity.kt', 'x')
        self.assertEqual(work.select_checks(self.root, config, ['auto'], 'HEAD'), ['android-unit'])
        self.write('lib/app.dart', 'changed')
        self.assertEqual(work.select_checks(self.root, config, ['auto'], 'HEAD'),
                         ['analyze', 'dart-tests', 'android-unit'])



    def test_invalid_base_cannot_hide_changed_paths(self):
        with self.assertRaises(work.Blocked):
            work.changed_paths(self.root, 'not-a-real-revision')



class CheckTests(Repo):
    def run_config(self, code, **extra):
        check = {'run': [PY, '-c', code], 'requires': ['lib/app.dart'], 'timeout': 20, **extra}
        return work.run_checks(self.root, self.config({'probe': check}), ['probe'])

    def test_success_records_counts_and_fingerprint(self):
        report = self.run_config('print("00:01 +3 ~1: All tests passed!")')
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['tests'], {'passed': 3, 'skipped': 1, 'failed': 0})
        self.assertEqual(report['fingerprint'], work.fingerprint(self.root))

    def test_failure_is_not_pass(self):
        report = self.run_config('raise SystemExit(3)')
        self.assertEqual(report['status'], 'INCOMPLETE')
        self.assertEqual(report['checks'][0]['exit_code'], 3)

    def test_missing_prerequisite_blocks(self):
        check = {'run': [PY, '-c', 'pass'], 'requires': ['missing']}
        report = work.run_checks(self.root, self.config({'probe': check}), ['probe'])
        self.assertEqual(report['checks'][0]['status'], 'BLOCKED')
        self.assertEqual(report['status'], 'INCOMPLETE')

    def test_missing_tool_blocks(self):
        check = {'run': ['/no/such/tool'], 'requires': []}
        report = work.run_checks(self.root, self.config({'probe': check}), ['probe'])
        self.assertEqual(report['checks'][0]['status'], 'BLOCKED')

    def test_timeout(self):
        report = self.run_config('import time; time.sleep(30)', timeout=1)
        self.assertEqual(report['checks'][0]['status'], 'TIMEOUT')

    def test_stall_is_retried_then_reported(self):
        report = self.run_config('import time; print("+1: started", flush=True); time.sleep(30)', stall=1)
        item = report['checks'][0]
        self.assertEqual(item['status'], 'STALLED')
        self.assertTrue(item['retried_after_stall'])
        self.assertEqual(report['status'], 'INCOMPLETE')

    def test_source_change_during_run_is_not_pass(self):
        report = self.run_config('open("lib/app.dart", "w").write("edited")')
        self.assertTrue(report['source_changed_during_run'])
        self.assertEqual(report['status'], 'INCOMPLETE')

    def test_split_runs_each_test_folder_and_skips_helpers(self):
        self.write('test/a/one_test.dart', 'x')
        self.write('test/b/two_test.dart', 'x')
        self.write('test/support/helper.dart', 'x')
        self.write('test/top_test.dart', 'x')
        self.assertEqual(work.test_targets(self.root, 'test'), ['test/a', 'test/b', 'test/top_test.dart'])
        check = {'run': [PY, '-c', 'import sys; print("+1: ok", sys.argv[1:])'], 'split': 'test'}
        report = work.run_checks(self.root, self.config({'t': check}), ['t'])
        self.assertEqual([c['id'] for c in report['checks']], ['t:test/a', 't:test/b', 't:test/top_test.dart'])
        self.assertEqual(report['tests']['passed'], 3)











class GuardTests(unittest.TestCase):
    def check(self, command):
        return work.hook_bash(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': command}}))[0]

    def test_guard_blocks_pkill_full(self):
        self.assertEqual(self.check('pkill -f "flutter test"'), 2)
        self.assertEqual(self.check('pkill -9 --full dartvm'), 2)
        self.assertEqual(self.check('pkill dartvm'), 0)

    def test_guard_blocks_broad_staging_and_history_rewrites(self):
        for command in ('git add -A', 'git add .', 'git add --all', 'git add lib/a.dart .',
                        'git push --force origin main', 'git push -f', 'git push origin +main',
                        'git push --force-with-lease', 'git commit --no-verify -m x',
                        'git reset --hard HEAD~1', 'git clean -fd', 'git checkout -- .', 'git restore .'):
            self.assertEqual(self.check(command), 2, command)

    def test_guard_allows_normal_commands(self):
        for command in ('git add lib/a.dart test/a_test.dart', 'git add ./lib/a.dart', 'git add -u lib',
                        'git push -u origin feature', 'git status', 'flutter test test/ui',
                        'git commit -m "fix: keep folder choice"'):
            self.assertEqual(self.check(command), 0, command)

    def test_guard_ignores_bad_input(self):
        self.assertEqual(work.hook_bash('not json')[0], 0)




if __name__ == '__main__':
    unittest.main()
