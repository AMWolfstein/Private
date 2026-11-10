"""Optional audit: scope selection, tool-proven findings, gaps, keep list and the [AUDIT] task."""
import json

from test_work import Repo, work, PY

audit = work.workaudit


class AuditTests(Repo):
    def setUp(self):
        super().setUp()
        self.write('lib/used.dart', 'used\n')
        self.write('lib/models/thing.g.dart', 'generated\n')
        self.write('third_party/pkg/vendored.dart', 'vendored\n')
        self.write('android/Main.kt', 'kotlin\n')
        self.write('rust_backend/crates/core/src/lib.rs', 'rust\n')
        self.write('README.md', 'not source\n')
        self.commit('sources')

    def configure(self, dart_output='', exit_code=0, keep=(), tool=True):
        script = f'import sys; sys.stdout.write({dart_output!r}); sys.exit({exit_code})'
        config = {'languages': {
            'dart': {'extensions': ['.dart'], 'proven': ['unused_import', 'dead_code'],
                     'tool': {'run': [PY, '-c', script], 'parser': 'dart-machine', 'nonzero_ok': True} if tool else None},
            'kotlin': {'extensions': ['.kt'], 'tool': None},
            'rust': {'extensions': ['.rs'], 'proven': ['dead_code'],
                     'tool': {'run': ['definitely-not-installed-tool'], 'parser': 'cargo-json'}}},
            'protected': ['third_party/*', '*.g.dart'], 'keep': list(keep)}
        self.write('workflow/work/audit.json', json.dumps(config))

    def run_audit(self, **options):
        return audit.audit(self.root, is_record=work.is_record, **options)

    def files(self, result):
        return json.loads((self.root / result['report']).with_suffix('.json').read_text())['file_list']

    def test_a_scope_is_required(self):
        self.configure()
        with self.assertRaises(work.Blocked): self.run_audit()
        with self.assertRaises(work.Blocked): self.run_audit(languages=['cobol'])
        with self.assertRaises(work.Blocked): self.run_audit(paths=['lib/missing.dart'])

    def test_language_and_path_select_files_and_skip_protected_code(self):
        self.configure()
        result = self.run_audit(languages=['dart'])
        self.assertEqual(self.files(result), ['lib/app.dart', 'lib/used.dart'])
        self.assertEqual(result['protected_skipped'], 2)
        self.assertEqual(self.files(self.run_audit(paths=['lib/used.dart'])), ['lib/used.dart'])
        self.assertEqual(self.files(self.run_audit(paths=['android', 'rust_backend'])),
                         ['android/Main.kt', 'rust_backend/crates/core/src/lib.rs'])

    def test_base_limits_the_scope_to_changed_and_new_files(self):
        self.configure(); self.commit('config')
        base = work.git(self.root, 'rev-parse', 'HEAD').strip()
        self.write('lib/app.dart', 'changed\n'); self.write('lib/new.dart', 'new\n')
        self.write('workflow/work/changes/001-x/notes.dart', 'record\n')
        self.assertEqual(self.files(self.run_audit(base=base)), ['lib/app.dart', 'lib/new.dart'])
        self.assertEqual(self.files(self.run_audit(base=base, languages=['kotlin'])), [])
        self.assertEqual(self.run_audit(base=base, languages=['kotlin'])['status'], 'NO_FILES')

    def test_only_configured_codes_inside_the_scope_are_proven(self):
        root = self.root.resolve()
        output = (f'INFO|HINT|UNUSED_IMPORT|{root}/lib/app.dart|3|8|10|Unused import.\n'
                  f'INFO|LINT|PREFER_CONST|{root}/lib/app.dart|9|1|4|Prefer const.\n'
                  f'WARNING|HINT|DEAD_CODE|{root}/lib/used.dart|5|1|4|Dead code.\n'
                  f'INFO|HINT|UNUSED_IMPORT|{root}/third_party/pkg/vendored.dart|1|1|4|Unused import.\n')
        self.configure(output, exit_code=3)
        result = self.run_audit(paths=['lib/app.dart'])
        self.assertEqual((result['status'], result['proven'], result['tools']['dart']['status']), ('PASS', 1, 'RAN'))
        report = (self.root / result['report']).read_text()
        self.assertIn('`lib/app.dart:3` [unused_import]', report)
        self.assertNotIn('prefer_const', report)
        self.assertNotIn('lib/used.dart:5', report)
        self.assertEqual(self.run_audit(languages=['dart'])['proven'], 2)

    def test_keep_list_stops_a_decided_finding_from_returning(self):
        output = f'INFO|HINT|UNUSED_IMPORT|{self.root.resolve()}/lib/app.dart|3|8|10|Unused import.\n'
        self.configure(output, keep=[{'path': 'lib/app.dart', 'code': 'unused_import', 'reason': 'owner keeps it'}])
        result = self.run_audit(languages=['dart'])
        self.assertEqual((result['proven'], result['kept']), (0, 1))
        self.assertIn('owner keeps it', (self.root / result['report']).read_text())
        self.write('workflow/work/audit.json', json.dumps({'languages': {}, 'keep': [{'path': 'lib/*'}]}))
        with self.assertRaises(work.Blocked): self.run_audit(languages=['dart'])

    def test_missing_or_failing_tools_are_gaps_never_clean_results(self):
        self.configure('', exit_code=0)
        result = self.run_audit(paths=['android', 'rust_backend', 'lib'])
        self.assertEqual(result['tools']['kotlin']['status'], 'NO_TOOL')
        self.assertEqual(result['tools']['rust']['status'], 'UNAVAILABLE')
        self.assertEqual(result['gaps'], ['kotlin', 'rust'])
        self.assertIn('Coverage gap', (self.root / result['report']).read_text())
        script = 'import sys; sys.exit(2)'
        config = json.loads((self.root / 'workflow/work/audit.json').read_text())
        config['languages']['dart']['tool'] = {'run': [PY, '-c', script], 'parser': 'dart-machine'}
        self.write('workflow/work/audit.json', json.dumps(config))
        self.assertEqual(self.run_audit(languages=['dart'])['tools']['dart']['status'], 'FAILED')

    def test_cargo_json_diagnostics_resolve_from_the_tool_directory(self):
        message = {'reason': 'compiler-message', 'message': {
            'code': {'code': 'dead_code'}, 'message': 'function `x` is never used',
            'spans': [{'file_name': 'crates/core/src/lib.rs', 'line_start': 7, 'is_primary': True}]}}
        output = '\n'.join([json.dumps(message), json.dumps(message), 'not json', json.dumps({'reason': 'build-finished'})])
        found = audit.parse_cargo_json(output, self.root, {'cwd': 'rust_backend'})
        self.assertEqual(found, [{'path': 'rust_backend/crates/core/src/lib.rs', 'line': 7, 'code': 'dead_code',
                                  'message': 'function `x` is never used'}])

    def test_command_line_scopes_by_change_and_rejects_two_bases(self):
        self.configure(); self.commit('config')
        folder = work.new_change(self.root, 'Audited change', 'small')
        self.write('lib/app.dart', 'changed\n')
        self.assertEqual(work.main(['--root', str(self.root), 'audit', '--change', folder.name]), 0)
        report = json.loads((self.root / '.work/audit').glob('*.json').__next__().read_text())
        self.assertEqual(report['file_list'], ['lib/app.dart'])
        self.assertEqual(work.main(['--root', str(self.root), 'audit', '--change', folder.name, '--base', 'HEAD']), 2)
        self.assertEqual(work.main(['--root', str(self.root), 'audit']), 2)


class AuditTaskTests(Repo):
    def setUp(self):
        super().setUp()
        command = "print('Ran 1 test in 0.01s\\nOK')"
        self.write('workflow/work/checks.json', json.dumps(self.config(
            {'unit': {'run': [PY, '-c', command], 'timeout': 5}}, {'app': ['lib/*']}, {'app': ['unit']})))
        self.commit('fixture checks')
        self.folder = work.new_change(self.root, 'Audited', 'small')
        self.ident = self.folder.name

    def tasks(self, text):
        (self.folder / 'tasks.md').write_text(text)

    def act(self, operation, task=None, **options):
        return work.worktasks.TaskLoop(self.root, work.__dict__).execute(operation, self.ident, task, **options)

    def done(self, task):
        self.assertEqual(self.act('check', task)['status'], 'PASS')
        self.assertEqual(self.act('review', task, result='clean', reviewer='independent-test-reviewer')['status'],
                         'READY_TO_COMMIT')
        work.git(self.root, 'add', '--', 'lib', str(self.folder.relative_to(self.root)))
        work.git(self.root, 'commit', '-m', task)

    def test_audit_task_is_optional_and_only_directly_before_final(self):
        self.tasks('- [ ] T001 Work — check: unit\n- [ ] T002 [FINAL] Review — check: auto\n')
        self.assertEqual(self.act('status')['status'], 'PASS')
        self.tasks('- [ ] T001 [AUDIT] Audit — check: auto\n- [ ] T002 Work — check: unit\n'
                   '- [ ] T003 [FINAL] Review — check: auto\n')
        with self.assertRaises(work.Blocked): self.act('status')
        self.tasks('- [ ] T001 Work — check: unit\n- [ ] T002 [AUDIT] Audit — check: auto\n'
                   '- [ ] T003 [AUDIT] Again — check: auto\n- [ ] T004 [FINAL] Review — check: auto\n')
        with self.assertRaises(work.Blocked): self.act('status')

    def test_audit_task_reports_the_whole_change_and_runs_the_normal_loop(self):
        self.tasks('- [ ] T001 Work — check: unit\n- [ ] T002 [AUDIT] Audit the change — check: auto\n'
                   '- [ ] T003 [FINAL] Review — check: auto\n')
        self.act('start', 'T001'); self.write('lib/app.dart', 'one\n'); self.write('lib/added.dart', 'new\n')
        self.done('T001')
        started = self.act('start', 'T002')
        self.assertEqual(started['audit']['files'], 2)  # both files of the change, not the repository
        report = json.loads((self.root / started['audit']['report']).with_suffix('.json').read_text())
        self.assertEqual(report['file_list'], ['lib/added.dart', 'lib/app.dart'])
        with self.assertRaises(work.Blocked): self.act('add', request='Extra while auditing')
        self.write('lib/app.dart', 'one, cleaned\n')
        self.done('T002')
        self.assertEqual(self.act('add', request='Extra after the audit')['task'], 'TOR001')
        self.assertEqual([r['id'] for r in work.worktasks.rows(self.folder)], ['T001', 'T002', 'TOR001', 'T003'])
        self.assertEqual(self.act('status')['status'], 'PASS')

    def test_audit_task_with_nothing_to_change_still_completes(self):
        self.tasks('- [ ] T001 [AUDIT] Audit the change — check: auto\n- [ ] T002 [FINAL] Review — check: auto\n')
        self.assertEqual(self.act('start', 'T001')['audit']['files'], 0)
        self.assertEqual(self.act('check', 'T001')['checks_status'], 'NOT_REQUIRED')
        self.assertEqual(self.act('review', 'T001', result='clean', reviewer='independent-test-reviewer')['status'],
                         'READY_TO_COMMIT')
