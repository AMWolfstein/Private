"""Tests for work.py: evidence, gates, prove and guards, on throwaway git repositories."""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parent / 'work.py'
PACKAGE = MODULE.parents[2]
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
        shutil.copytree(PACKAGE / 'work', self.root / 'work')
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
        self.write('work/changes/001-x/log.md', 'entry')
        self.assertEqual(before, work.fingerprint(self.root))

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
    def test_scope_uses_paths(self):
        config = work.load_config(self.root)
        self.write('lib/export/report_screen.dart', 'x')
        found = work.domains_for(config, work.changed_paths(self.root))
        self.assertEqual(list(found), ['dart'])
        self.assertEqual(work.high_risk(config, ['lib/export/report_screen.dart']), [])
        self.assertEqual(work.high_risk(config, ['lib/services/native/media_file_bridge.dart']),
                         ['lib/services/native/media_file_bridge.dart'])

    def test_auto_selects_checks_by_path(self):
        config = work.load_config(self.root)
        self.write('android/app/src/main/kotlin/MainActivity.kt', 'x')
        self.assertEqual(work.select_checks(self.root, config, ['auto'], 'HEAD'), ['android-unit'])
        self.write('lib/app.dart', 'changed')
        self.assertEqual(work.select_checks(self.root, config, ['auto'], 'HEAD'),
                         ['analyze', 'dart-tests', 'android-unit'])

    def test_records_alone_select_nothing(self):
        config = work.load_config(self.root)
        self.write('work/changes/001-x/spec.md', 'x')
        with self.assertRaises(work.Blocked):
            work.select_checks(self.root, config, ['auto'], 'HEAD')

    def test_tests_are_recognised(self):
        for path in ('test/a_test.dart', 'android/app/src/test/kotlin/A.kt',
                     'rust_backend/crates/core/tests/cue.rs', 'scripts/test_build.py'):
            self.assertTrue(work.is_test(path), path)
        for path in ('lib/screens/setup/setup_screen_flow.dart', 'android/app/src/main/kotlin/A.kt'):
            self.assertFalse(work.is_test(path), path)


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

    def test_fresh_command(self):
        self.run_config('pass')
        self.assertEqual(work.main(['--root', str(self.root), 'fresh']), 0)
        self.write('lib/app.dart', 'later edit')
        self.assertEqual(work.main(['--root', str(self.root), 'fresh']), 1)


class ProveTests(Repo):
    def setUp(self):
        super().setUp()
        # The "test" fails unless lib/app.dart contains "fixed".
        self.write('test/app_test.py', 'import sys\nsys.exit(0 if "fixed" in open("lib/app.dart").read() else 1)\n')
        self.command = [PY, 'test/app_test.py']

    def test_prove_passes_when_test_fails_without_fix(self):
        self.write('lib/app.dart', 'fixed\n')
        self.write('lib/helper.dart', 'new file\n')
        result = work.prove(self.root, self.command, 30)
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['reverted'], ['lib/app.dart', 'lib/helper.dart'])
        self.assertEqual((self.root / 'lib/app.dart').read_text(), 'fixed\n')
        self.assertEqual((self.root / 'lib/helper.dart').read_text(), 'new file\n')

    def test_prove_fails_when_test_does_not_detect_bug(self):
        self.write('lib/app.dart', 'fixed\n')
        result = work.prove(self.root, [PY, '-c', 'pass'], 30)
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual((self.root / 'lib/app.dart').read_text(), 'fixed\n')

    def test_prove_restores_deleted_files(self):
        self.write('lib/old.dart', 'old\n')
        self.commit('add old')
        (self.root / 'lib/old.dart').unlink()
        self.write('lib/app.dart', 'fixed\n')
        work.prove(self.root, self.command, 30)
        self.assertFalse((self.root / 'lib/old.dart').exists())

    def test_prove_leaves_tool_and_non_code_files_alone(self):
        self.write('lib/app.dart', 'fixed\n')
        self.write('scripts/work/work.py', 'the running tool\n')
        self.write('notes.txt', 'owner notes\n')
        seen = 'import os; print(os.path.exists("scripts/work/work.py"), os.path.exists("notes.txt"))'
        result = work.prove(self.root, [PY, '-c', seen + '; raise SystemExit(1)'], 30)
        self.assertEqual(result['reverted'], ['lib/app.dart'])
        self.assertIn('True True', result['output_tail'])

    def test_prove_timeout_is_inconclusive(self):
        self.write('lib/app.dart', 'fixed\n')
        result = work.prove(self.root, [PY, '-c', 'import time; time.sleep(30)'], 1)
        self.assertEqual(result['status'], 'INCONCLUSIVE')
        self.assertEqual((self.root / 'lib/app.dart').read_text(), 'fixed\n')

    def test_prove_needs_a_non_test_change(self):
        with self.assertRaises(work.Blocked):
            work.prove(self.root, self.command, 30)


class GateTests(Repo):
    def setUp(self):
        super().setUp()
        self.folder = work.new_change(self.root, 'Play CUE tracks', 'feature')
        self.id = self.folder.name[:3]

    def fill(self, name, text):
        (self.folder / name).write_text(text)

    def good_spec(self):
        self.fill('spec.md', '# Spec\n\n- FR-001: The app MUST play.\n\n1. Given a CUE, When tapped, Then it plays.\n')

    def good_plan(self):
        self.fill('plan.md', '# Plan\n\n## Constitution check\n\n- [x] I. ok\n\n## Next\n')

    def good_tasks(self, done=False):
        mark = 'x' if done else ' '
        self.fill('tasks.md', f'- [{mark}] T001 Play clips (FR-001) — check: flutter test test/cue_test.dart\n')

    def test_new_change_uses_templates(self):
        self.assertEqual(self.folder.name, '001-play-cue-tracks')
        self.assertEqual(work.read_state(self.folder)['phase'], 'spec')
        self.assertIn('[FILL', (self.folder / 'spec.md').read_text())

    def test_template_spec_cannot_advance(self):
        with self.assertRaises(work.Blocked):
            work.advance(self.root, self.id, 'plan')

    def test_clarification_marker_blocks_plan(self):
        self.good_spec()
        self.fill('spec.md', (self.folder / 'spec.md').read_text() + '[NEEDS CLARIFICATION: which formats?]\n')
        with self.assertRaises(work.Blocked):
            work.advance(self.root, self.id, 'plan')

    def test_phases_cannot_be_skipped(self):
        self.good_spec()
        with self.assertRaises(work.Blocked):
            work.advance(self.root, self.id, 'tasks')

    def test_requirement_without_task_blocks_build(self):
        self.good_spec()
        self.good_plan()
        self.fill('tasks.md', '- [ ] T001 Something else — check: x\n')
        work.advance(self.root, self.id, 'plan')
        work.advance(self.root, self.id, 'tasks')
        with self.assertRaisesRegex(work.Blocked, 'FR-001'):
            work.advance(self.root, self.id, 'build')

    def test_unchecked_constitution_item_blocks_tasks(self):
        self.good_spec()
        self.fill('plan.md', '## Constitution check\n\n- [ ] I. not yet\n')
        work.advance(self.root, self.id, 'plan')
        with self.assertRaisesRegex(work.Blocked, 'constitution'):
            work.advance(self.root, self.id, 'tasks')

    def walk_to_build(self):
        self.good_spec()
        self.good_plan()
        self.good_tasks()
        for phase in ('plan', 'tasks', 'build'):
            work.advance(self.root, self.id, phase)

    def pass_checks(self, *keys):
        checks = {key: {'run': [PY, '-c', 'pass']} for key in keys}
        work.run_checks(self.root, self.config(checks), list(keys))

    def test_review_needs_done_tasks_and_fresh_evidence(self):
        self.walk_to_build()
        self.write('lib/app.dart', 'feature code\n')
        with self.assertRaisesRegex(work.Blocked, 'unfinished task'):
            work.advance(self.root, self.id, 'review')
        self.good_tasks(done=True)
        with self.assertRaisesRegex(work.Blocked, 'no passing "analyze"'):
            work.advance(self.root, self.id, 'review')
        self.pass_checks('analyze')  # a narrow run does not stand in for the suite
        with self.assertRaisesRegex(work.Blocked, 'no passing "dart-tests"'):
            work.advance(self.root, self.id, 'review')
        self.pass_checks('dart-tests')
        work.advance(self.root, self.id, 'review')
        self.write('lib/app.dart', 'edited after the checks\n')
        self.assertTrue(any('stale' in p for p in work.lint_change(self.root, self.folder, 'review')))

    def test_changes_since_creation_count_after_commit(self):
        self.walk_to_build()
        self.good_tasks(done=True)
        self.write('lib/app.dart', 'feature code\n')
        self.commit('feature')
        with self.assertRaisesRegex(work.Blocked, 'no passing "analyze"'):
            work.advance(self.root, self.id, 'review')

    def test_ship_needs_clean_round_on_final_code(self):
        self.walk_to_build()
        self.good_tasks(done=True)
        self.write('lib/app.dart', 'feature code\n')
        self.pass_checks('analyze', 'dart-tests')
        work.advance(self.root, self.id, 'review')
        with self.assertRaisesRegex(work.Blocked, 'code-review round'):
            work.advance(self.root, self.id, 'ship')
        work.record_round(self.root, self.id, 'code', 'clean', 'code-reviewer')
        self.write('lib/app.dart', 'edited after review')
        with self.assertRaisesRegex(work.Blocked, 'after the last clean review'):
            work.advance(self.root, self.id, 'ship')

    def test_findings_need_evidence_and_block_ship_when_open(self):
        self.fill('findings.md', '### F-001 [code r1] Bug\n- Severity: major\n- Status: fixed\n\n'
                                 '### F-002 [code r1] Other\n- Severity: blocker\n- Status: open\n')
        problems = work.lint_change(self.root, self.folder)
        self.assertTrue(any('F-001 is fixed without Evidence' in p for p in problems))
        self.assertTrue(any('F-002 is an open blocker' in p for p in problems))

    def test_template_example_finding_is_ignored(self):
        self.assertEqual(work.parse_findings((self.folder / 'findings.md').read_text()), [])

    def test_architecture_needs_two_clean_design_rounds(self):
        folder = work.new_change(self.root, 'Kotlin playback service', 'architecture')
        ident = folder.name[:3]
        (folder / 'spec.md').write_text('- FR-001: MUST.\nGiven a, When b, Then c\n')
        (folder / 'plan.md').write_text('## Constitution check\n- [x] ok\n')
        work.advance(self.root, ident, 'plan')
        work.record_round(self.root, ident, 'design', 'clean', 'r')
        with self.assertRaisesRegex(work.Blocked, 'two consecutive clean'):
            work.advance(self.root, ident, 'tasks')
        work.record_round(self.root, ident, 'design', 'clean', 'r')
        (folder / 'plan.md').write_text('## Constitution check\n- [x] ok, edited\n')
        with self.assertRaisesRegex(work.Blocked, 'after the last design review'):
            work.advance(self.root, ident, 'tasks')

    def test_done_needs_close_lines(self):
        problems = work.lint_change(self.root, self.folder, 'done')
        self.assertTrue(any('Drift' in p for p in problems))


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


class CliTests(Repo):
    def test_status_and_remind(self):
        self.assertEqual(work.main(['--root', str(self.root), 'status']), 0)
        self.assertEqual(work.main(['--root', str(self.root), 'remind']), 0)

    def test_invalid_config_blocks(self):
        config = json.loads((self.root / 'work/checks.json').read_text())
        config['checks']['analyze']['requires'] = 'pubspec.yaml'
        (self.root / 'work/checks.json').write_text(json.dumps(config))
        self.assertEqual(work.main(['--root', str(self.root), 'scope']), 2)

    def test_packet_contains_diff_and_new_files(self):
        self.write('lib/app.dart', 'changed\n')
        self.write('lib/added.dart', 'brand new\n')
        self.assertEqual(work.main(['--root', str(self.root), 'packet', '--out', '.work/p.md']), 0)
        text = (self.root / '.work/p.md').read_text()
        self.assertIn('+changed', text)
        self.assertIn('brand new', text)


if __name__ == '__main__':
    unittest.main()
