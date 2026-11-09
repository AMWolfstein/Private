"""Environment lifecycle and strict-integration policy; provisioning itself has a real CI smoke path."""
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
import workflow_env as environment
import run_tests

PACKAGE = Path(__file__).resolve().parents[3]


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='env test ')
        self.addCleanup(temporary.cleanup);self.root = Path(temporary.name)
        shutil.copytree(PACKAGE / 'workflow', self.root / 'workflow', ignore=shutil.ignore_patterns('__pycache__'))
        (self.root / '.gitignore').write_text('.work/\n__pycache__/\n')
        for argv in [['git', 'init', '-q'], ['git', 'config', 'user.name', 'Test'],
                     ['git', 'config', 'user.email', 'test@example.invalid'], ['git', 'add', '.'],
                     ['git', 'commit', '-qm', 'fixture']]:
            subprocess.run(argv, cwd=self.root, check=True, capture_output=True)

    def test_doctor_is_read_only_and_reports_missing_dependencies(self):
        before = subprocess.check_output(['git', 'status', '--porcelain'], cwd=self.root)
        result = environment.doctor(self.root)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertFalse((self.root / '.work').exists())
        self.assertEqual(subprocess.check_output(['git', 'status', '--porcelain'], cwd=self.root), before)
        self.assertTrue(any(c['name'] == 'managed-python' and c['status'] == 'BLOCKED' for c in result['checks']))

    def test_offline_setup_never_installs_missing_dependencies(self):
        with mock.patch.object(environment, 'execute', wraps=environment.execute) as execute:
            report = environment.setup(self.root, offline=True)
        self.assertEqual(report['status'], 'BLOCKED')
        self.assertFalse((self.root / '.work/python').exists())
        self.assertFalse(any('install' in call.args[0] for call in execute.call_args_list))

    def test_healthy_setup_is_reused_without_package_manager_commands(self):
        with mock.patch.object(environment, 'doctor', return_value={'status': 'PASS', 'checks': []}), \
             mock.patch.object(environment, 'execute', wraps=environment.execute) as execute:
            self.assertTrue(environment.setup(self.root)['reused'])
        self.assertFalse(any('install' in call.args[0] for call in execute.call_args_list))

    def test_install_failure_does_not_publish_ready_marker(self):
        interpreter = environment.managed_python(self.root)
        interpreter.parent.mkdir(parents=True);interpreter.write_text('not executed')
        def execute(argv, *args, **kwargs):
            if '-c' in argv: return str(self.root / '.work/python')
            raise environment.Blocked('simulated installer failure')
        with mock.patch.object(environment, 'prerequisites'), \
             mock.patch.object(environment, 'doctor', return_value={'status': 'BLOCKED'}), \
             mock.patch.object(environment, 'execute', side_effect=execute):
            with self.assertRaisesRegex(environment.Blocked, 'installer failure'): environment.setup(self.root)
        self.assertFalse((self.root / '.work/environment.json').exists())

    def test_symlinked_managed_directories_cannot_redirect_installation(self):
        (self.root / '.work/cache').mkdir(parents=True)
        with tempfile.TemporaryDirectory() as outside:
            (self.root / '.work/cache/npm').symlink_to(outside, target_is_directory=True)
            with self.assertRaises(environment.Blocked): environment.confined(self.root)

    def test_managed_engine_discovery_preserves_explicit_commands(self):
        local = environment.managed_codegraph(self.root);local.parent.mkdir(parents=True);local.write_text('fixture')
        self.assertEqual(environment.resolve_command(self.root, ['codegraph']), [str(local)])
        self.assertEqual(environment.resolve_command(self.root, ['/custom/codegraph']), ['/custom/codegraph'])
        self.assertEqual(environment.resolve_command(self.root, ['tools/engine']), [str(self.root / 'tools/engine')])

    def test_invalid_configuration_blocks_doctor_without_a_traceback(self):
        (self.root / 'workflow/work/map.json').write_text('[]')
        self.assertEqual(environment.doctor(self.root)['status'], 'BLOCKED')

    def test_linux_target_is_enforced_before_installation(self):
        with mock.patch.object(environment.platform, 'system', return_value='Windows'):
            with self.assertRaisesRegex(environment.Blocked, 'Linux'): environment.setup(self.root)
        self.assertFalse((self.root / '.work').exists())

    def test_requirements_changes_invalidate_the_environment_specification(self):
        marker = self.root / '.work/environment.json';marker.parent.mkdir()
        marker.write_text(json.dumps({'requirements_sha256': environment.requirements_digest(self.root), 'codegraph': '1.6.2'}))
        requirements = self.root / 'workflow/scripts/work/requirements.txt'
        requirements.write_text(requirements.read_text() + '\n# dependency specification change\n')
        report = environment.doctor(self.root)
        spec = next(c for c in report['checks'] if c['name'] == 'dependency-specification')
        self.assertEqual(spec['status'], 'BLOCKED')
        self.assertIn('requirements changed', spec['detail'])

    def test_malformed_ready_marker_is_blocked_instead_of_crashing(self):
        marker = self.root / '.work/environment.json';marker.parent.mkdir();marker.write_text('[]')
        report = environment.doctor(self.root)
        check = next(c for c in report['checks'] if c['name'] == 'dependency-specification')
        self.assertEqual(check['status'], 'BLOCKED')
        self.assertIn('invalid environment.json', check['detail'])

    def test_ignore_rules_cover_installed_tools_and_reject_tracked_runtime_files(self):
        (self.root / '.gitignore').write_text('.work/*\n!.work/tools/\n')
        with self.assertRaises(environment.Blocked): environment.prerequisites(self.root)
        (self.root / '.gitignore').write_text('.work/\n')
        tracked = self.root / '.work/accidental.json';tracked.parent.mkdir();tracked.write_text('{}')
        subprocess.run(['git', 'add', '-f', str(tracked)], cwd=self.root, check=True, capture_output=True)
        with self.assertRaisesRegex(environment.Blocked, 'tracked'): environment.prerequisites(self.root)

    def test_log_metadata_and_foreign_engine_symlinks_are_rejected(self):
        base = self.root / '.work';base.mkdir()
        with tempfile.TemporaryDirectory() as temporary:
            outside = Path(temporary) / 'file';outside.write_text('preserve')
            for name in ('setup.log', 'setup.lock', 'environment.json'):
                link = base / name;link.symlink_to(outside)
                with self.assertRaises(environment.Blocked): environment.confined(self.root)
                link.unlink()
            engine = environment.managed_codegraph(self.root);engine.parent.mkdir(parents=True);engine.symlink_to(outside)
            with self.assertRaises(environment.Blocked): environment.resolve_command(self.root, ['codegraph'])
            self.assertEqual(outside.read_text(), 'preserve')

    def test_pip_config_cannot_redirect_installation_outside_managed_environment(self):
        # A real local wheel and real pip; no network and no third-party fixture dependency.
        import sys
        prefix = environment.managed_python(self.root).parent.parent
        subprocess.run([sys.executable, '-m', 'venv', str(prefix)], check=True, capture_output=True)
        wheel = self.root / 'workflow_probe-0.0.1-py3-none-any.whl'
        files = {'workflow_probe/__init__.py': 'VALUE = 1\n',
                 'workflow_probe-0.0.1.dist-info/METADATA': 'Metadata-Version: 2.1\nName: workflow-probe\nVersion: 0.0.1\n',
                 'workflow_probe-0.0.1.dist-info/WHEEL': 'Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n'}
        files['workflow_probe-0.0.1.dist-info/RECORD'] = ''.join(name + ',,\n' for name in files)
        with zipfile.ZipFile(wheel, 'w') as archive:
            for name, content in files.items(): archive.writestr(name, content)
        pip_config = self.root / 'pip.ini'
        real_execute = environment.execute
        def execute(argv, *args, **kwargs):
            if '-r' in argv:
                index = argv.index('-r');argv = argv[:index] + argv[index + 2:] + ['--no-index', '--force-reinstall', str(wheel)]
            return real_execute(argv, *args, **kwargs)
        for option in ('target', 'root', 'report', 'log'):
            with self.subTest(option=option):
                outside = self.root / ('outside-' + option)
                pip_config.write_text('[global]\n' + option + '=' + str(outside) + '\n')
                with mock.patch.dict(os.environ, {'PIP_CONFIG_FILE': str(pip_config)}), \
                     mock.patch.object(environment, 'doctor', return_value={'status': 'BLOCKED'}), \
                     mock.patch.object(environment.shutil, 'which', return_value=None), \
                     mock.patch.object(environment, 'execute', side_effect=execute):
                    with self.assertRaises(environment.Blocked): environment.setup(self.root)
                self.assertFalse(outside.exists(), 'pip configuration wrote outside .work')
                self.assertFalse((self.root / '.work/environment.json').exists())

    def test_destination_environment_is_neutralized_but_network_variables_are_preserved(self):
        with mock.patch.dict(os.environ, {'PIP_ROOT': '/outside', 'PIP_LOG': '/outside/log',
                                         'PIP_REPORT': '/outside/report', 'PIP_INDEX_URL': 'https://example.invalid/simple'}):
            env = environment.clean_environment()
        self.assertNotIn('PIP_ROOT', env)
        self.assertNotIn('PIP_LOG', env)
        self.assertNotIn('PIP_REPORT', env)
        self.assertEqual(env['PIP_CONFIG_FILE'], os.devnull)
        self.assertEqual(env['PIP_INDEX_URL'], 'https://example.invalid/simple')


class StrictIntegrationTests(unittest.TestCase):
    def result(self, skipped=(), seen=None):
        if seen is None: seen = {prefix + 'test_probe' for prefix in run_tests.REQUIRED}
        return SimpleNamespace(seen=seen, skipped=[(SimpleNamespace(id=lambda ident=ident: ident), reason) for ident, reason in skipped])

    def test_real_parser_or_engine_skip_is_a_ci_failure(self):
        result = self.result([('test_resource_index.BashTests.test_probe', 'parser unavailable')])
        self.assertTrue(run_tests.integration_problems(result))

    def test_discovery_cannot_silently_omit_real_integration_classes(self):
        self.assertEqual(len(run_tests.integration_problems(self.result(seen=set()))), len(run_tests.REQUIRED))

    def test_only_the_exact_optional_namespace_skip_is_allowed(self):
        allowed = self.result([(run_tests.OPTIONAL, 'cannot create a network namespace here')])
        self.assertFalse(run_tests.integration_problems(allowed))
        self.assertTrue(run_tests.integration_problems(self.result([(run_tests.OPTIONAL, 'unexpected failure')])) )


if __name__ == '__main__': unittest.main()
