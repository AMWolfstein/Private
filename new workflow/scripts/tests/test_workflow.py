"""Fault injection for workflow evidence, not application tests."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'workflow.py'
spec = importlib.util.spec_from_file_location('workflow', MODULE)
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='workflow test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'source.dart').write_text('original')

    def config(self, code='print("ok")', timeout=5):
        return {'checks': {'probe': {'command': [sys.executable, '-c', code],
                'cwd': '.', 'requires': ['source.dart'], 'timeout_seconds': timeout}},
                'profiles': {'test': ['probe']}}

    def test_success_records_exit_and_log(self):
        result = workflow.run_checks(self.root, self.config(), 'test')
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['checks'][0]['exit_code'], 0)
        self.assertEqual(result['finished_fingerprint'], workflow.fingerprint(self.root))
        self.assertIn('ok', (self.root / result['checks'][0]['log']).read_text())

    def test_failure_is_not_pass(self):
        result = workflow.run_checks(self.root, self.config('raise SystemExit(7)'), 'test')
        self.assertEqual(result['status'], 'INCOMPLETE')
        self.assertEqual(result['checks'][0]['exit_code'], 7)

    def test_absent_tool_is_blocked(self):
        config = self.config()
        config['checks']['probe']['command'] = ['/not/a/real/tool']
        self.assertEqual(workflow.run_checks(self.root, config, 'test')['checks'][0]['status'], 'BLOCKED')

    def test_missing_prerequisite_does_not_execute(self):
        config = self.config('raise SystemExit(88)')
        config['checks']['probe']['requires'] = ['missing']
        result = workflow.run_checks(self.root, config, 'test')['checks'][0]
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertIsNone(result['exit_code'])

    def test_unconfigured_contract_is_not_pass(self):
        config = self.config()
        config['checks']['probe']['command'] = []
        self.assertEqual(workflow.run_checks(self.root, config, 'test')['status'], 'INCOMPLETE')

    def test_timeout(self):
        result = workflow.run_checks(self.root, self.config('import time; time.sleep(60)', 1), 'test')
        self.assertEqual(result['checks'][0]['status'], 'TIMEOUT')

    def test_source_mutation_invalidates_success(self):
        code = 'from pathlib import Path; Path("source.dart").write_text("changed")'
        result = workflow.run_checks(self.root, self.config(code), 'test')
        self.assertEqual(result['checks'][0]['status'], 'PASS')
        self.assertEqual(result['status'], 'INCOMPLETE')
        self.assertTrue(result['source_changed_during_run'])

    def test_same_length_change_detected(self):
        before = workflow.fingerprint(self.root)
        (self.root / 'source.dart').write_text('modified')
        self.assertNotEqual(before, workflow.fingerprint(self.root))

    def test_untracked_and_deleted_inputs_detected(self):
        before = workflow.fingerprint(self.root)
        fixture = self.root / 'corpus.bin'
        fixture.write_bytes(b'fixture')
        self.assertNotEqual(before, workflow.fingerprint(self.root))
        fixture.unlink()
        self.assertEqual(before, workflow.fingerprint(self.root))
        (self.root / 'source.dart').unlink()
        self.assertNotEqual(before, workflow.fingerprint(self.root))

    def test_generated_artifacts_excluded(self):
        before = workflow.fingerprint(self.root)
        for folder in ('.workflow-runs', 'build', '__pycache__'):
            (self.root / folder).mkdir()
            (self.root / folder / 'output').write_text('generated')
        self.assertEqual(before, workflow.fingerprint(self.root))

    def test_cwd_escape_rejected(self):
        with self.assertRaises(ValueError):
            workflow.local_path(self.root, '../elsewhere')

    def test_arabic_routing(self):
        result = workflow.route('انقل ال bridge إلى Kotlin', ['lib/client.dart'])
        self.assertEqual(result['mode'], 'migration')
        self.assertIn('android', result['domains'])
        self.assertIn('flutter', result['domains'])
        self.assertTrue(result['advisory_only'])

    def test_fresh_cli_rejects_later_edit(self):
        workflow.run_checks(self.root, self.config(), 'test')
        command = [sys.executable, str(MODULE), '--root', str(self.root),
                   'fresh', '.workflow-runs/latest.json']
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        (self.root / 'source.dart').write_text('later edit')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('STALE_OR_INCOMPLETE', result.stdout)

    def test_failed_evidence_is_never_fresh_pass(self):
        workflow.run_checks(self.root, self.config('raise SystemExit(2)'), 'test')
        result = subprocess.run([sys.executable, str(MODULE), '--root', str(self.root),
                                 'fresh', '.workflow-runs/latest.json'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)

    def test_portable_package(self):
        target = self.root / 'new repository'
        shutil.copytree(MODULE.parents[1], target, ignore=shutil.ignore_patterns('.workflow-runs', '__pycache__'))
        self.assertEqual(workflow.validate(target)['status'], 'PASS')
        config = workflow.load_config(target)
        self.assertEqual(config['checks']['bridge-contracts']['command'], [])


if __name__ == '__main__':
    unittest.main()
