"""Task-loop behavior on real disposable Git repositories; no app toolchains."""
import json
from pathlib import Path
from unittest.mock import patch

from test_work import Repo, work, PY


class TaskLoopTests(Repo):
    def setUp(self):
        super().setUp()
        command = "from pathlib import Path; assert Path('lib/app.dart').read_text() != 'bad'; print('Ran 1 test in 0.01s\\nOK')"
        self.write('workflow/work/checks.json', json.dumps(self.config(
            {'unit': {'run': [PY, '-c', command], 'timeout': 5}},
            {'app': ['lib/*']}, {'app': ['unit']})))
        self.commit('fixture checks')
        self.folder = work.new_change(self.root, 'Task loop', 'small')
        (self.folder / 'tasks.md').write_text(
            '- [ ] T000 [MAP] Map — check: map status\n'
            '- [ ] T001 Change one — check: unit\n'
            '- [ ] T002 Change two — check: unit\n'
            '- [ ] T003 [FINAL] Cumulative review — check: auto\n')
        self.ident = self.folder.name

    def act(self, operation, task=None, **options):
        return work.worktasks.TaskLoop(self.root, work.__dict__).execute(operation, self.ident, task, **options)

    def ready(self, task, result='clean'):
        self.assertEqual(self.act('check', task)['status'], 'PASS')
        self.act('packet', task)
        return self.act('review', task, result=result, reviewer='independent-test-reviewer', note='review evidence')

    def finish(self, task):
        self.assertEqual(self.act('complete', task)['status'], 'READY_TO_COMMIT')
        work.git(self.root, 'add', '--', 'lib/app.dart', str(self.folder.relative_to(self.root)))
        work.git(self.root, 'commit', '-m', task)
        return self.act('status')

    def initial_map(self):
        self.act('start', 'T000'); self.ready('T000'); self.finish('T000')

    def test_map_first_and_no_manual_completion_or_skipped_queue(self):
        with self.assertRaises(work.Blocked): self.act('start', 'T001')
        self.initial_map()
        self.act('start', 'T001')
        with self.assertRaises(work.Blocked): self.act('start', 'T002')
        with self.assertRaises(work.Blocked): self.act('complete', 'T001')

    def test_fixes_and_three_reviews_produce_one_actual_task_commit(self):
        self.initial_map(); self.act('start', 'T001')
        base = work.git(self.root, 'rev-parse', 'HEAD').strip()
        for version, verdict in [('one', 'dirty'), ('two', 'dirty'), ('three', 'clean')]:
            self.write('lib/app.dart', version)
            result = self.ready('T001', verdict)
            self.assertEqual(result['status'], 'PASS')
        self.finish('T001')
        self.assertEqual(work.git(self.root, 'rev-list', '--count', f'{base}..HEAD').strip(), '1')
        state = work.read_state(self.folder)
        self.assertEqual(len(state['execution']['tasks']['T001']['reviews']), 3)

    def test_third_dirty_stops_fourth_commit_and_next_task_until_owner_resume(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        for _ in range(3): result = self.ready('T001', 'dirty')
        self.assertEqual(result['status'], 'BLOCKED')
        for operation, task in [('packet', 'T001'), ('complete', 'T001'), ('start', 'T002')]:
            with self.assertRaises(work.Blocked): self.act(operation, task)
        with self.assertRaises(work.Blocked): self.act('resume', 'T001')
        self.act('resume', 'T001', owner_instruction='Owner explicitly requested another approach')
        self.ready('T001'); self.finish('T001')
        item = work.read_state(self.folder)['execution']['tasks']['T001']
        self.assertEqual(len(item['reviews']), 4)
        self.assertEqual(item['cycle'], 2)

    def test_stale_source_and_requirement_evidence_cannot_be_reused(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'first')
        self.ready('T001')
        self.write('lib/app.dart', 'second')
        with self.assertRaises(work.Blocked): self.act('complete', 'T001')
        self.act('check', 'T001')
        path = self.folder / 'tasks.md'
        path.write_text(path.read_text().replace('T001 Change one', 'T001 Clarified requirement'))
        with self.assertRaises(work.Blocked): self.act('packet', 'T001')

    def test_requirement_changed_during_check_marks_task_evidence_incomplete(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        original = work.run_checks
        def changed(*args):
            result = original(*args)
            path = self.folder / 'tasks.md'
            path.write_text(path.read_text().replace('T001 Change one', 'T001 Changed requirement'))
            return result
        with patch.object(work, 'run_checks', side_effect=changed):
            self.assertEqual(self.act('check', 'T001')['status'], 'INCOMPLETE')
        with self.assertRaises(work.Blocked): self.act('packet', 'T001')

    def test_reports_and_progress_do_not_invalidate_code_checks(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        self.ready('T001')
        self.write('reports/task.md', 'human report')
        with (self.folder / 'log.md').open('a') as out: out.write('\nprogress\n')
        self.finish('T001')

    def test_dirty_tracked_and_preexisting_untracked_work_is_protected(self):
        self.initial_map(); self.write('lib/app.dart', 'unrelated edit')
        with self.assertRaises(work.Blocked): self.act('start', 'T001')
        self.write('lib/app.dart', 'original\n')
        self.write('owner-notes.txt', 'keep this')
        self.act('start', 'T001'); self.write('lib/app.dart', 'task edit')
        self.ready('T001'); self.finish('T001')
        self.assertEqual((self.root / 'owner-notes.txt').read_text(), 'keep this')
        self.assertEqual(work.git(self.root, 'ls-files', 'owner-notes.txt').strip(), '')

    def test_completion_waits_for_git_and_handles_lost_commit_acknowledgement(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        self.ready('T001'); self.act('complete', 'T001')
        self.assertEqual(self.act('status')['waiting_for_git_commit'], ['T001'])
        with self.assertRaises(work.Blocked): self.act('start', 'T002')
        self.commit('commit completed before process interruption')
        self.assertEqual(self.act('status')['waiting_for_git_commit'], [])
        self.act('start', 'T002')

    def test_committed_code_must_match_reviewed_code(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'reviewed')
        self.ready('T001'); self.act('complete', 'T001')
        self.write('lib/app.dart', 'not reviewed')
        self.commit('unexpected post-review change')
        with self.assertRaises(work.Blocked): self.act('status')

    def test_tor_queue_and_cumulative_final_check_cover_previous_commits(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'one')
        self.ready('T001'); self.finish('T001')
        self.assertEqual(self.act('add', request='Owner extra request')['task'], 'TOR001')
        self.assertEqual(self.act('add', request='Second extra request')['task'], 'TOR002')
        self.assertEqual([r['id'] for r in work.worktasks.rows(self.folder)], ['T000', 'T001', 'TOR001', 'TOR002', 'T002', 'T003'])
        for task in ['TOR001', 'TOR002', 'T002']:
            self.act('start', task); self.write('lib/app.dart', task); self.ready(task); self.finish(task)
        self.act('start', 'T003')
        result = self.act('check', 'T003')
        self.assertEqual(result['checks'], ['unit'])
        self.act('packet', 'T003'); self.act('review', 'T003', result='clean', reviewer='final-reviewer')
        self.finish('T003')
        self.assertEqual(work.read_state(self.folder)['phase'], 'done')

    def test_small_skips_planning_and_new_records_reject_old_execution_phases(self):
        self.assertFalse((self.folder / 'plan.md').exists())
        self.assertEqual(work.read_state(self.folder)['workflow_version'], 2)
        for phase in ['build', 'review', 'ship']:
            with self.assertRaises(work.Blocked): work.advance(self.root, self.ident, phase)

    def planned(self):
        self.folder = work.new_change(self.root, 'Planned work', 'feature')
        self.ident = self.folder.name
        (self.folder / 'spec.md').write_text('FR-001: Preserve behavior. Given a change When applied Then tests pass.\n')
        (self.folder / 'plan.md').write_text('## Constitution check\n- [x] All applicable articles\n')
        (self.folder / 'tasks.md').write_text('- [ ] T000 [MAP] Map — check: map status\n- [ ] T001 Work (FR-001) — check: unit\n- [ ] T002 [FINAL] All work (FR-001) — check: unit\n')
        (self.folder / 'assurance.json').write_text(json.dumps({'version': 1,
            'port': {'applies': False, 'reason': 'No port'}, 'bridge': {'applies': False, 'reason': 'No bridge'},
            'prerequisites': [], 'device_checks': []}))
        state = work.read_state(self.folder); state['phase'] = 'plan'; work.write_state(self.folder, state)
        self.act('planning-commit')

    def test_partial_planning_commit_cannot_start_execution(self):
        self.planned()
        work.git(self.root, 'add', '--', str((self.folder / 'log.md').relative_to(self.root)))
        work.git(self.root, 'commit', '-m', 'incomplete planning')
        with self.assertRaises(work.Blocked): self.act('start', 'T000')

    def test_complete_planning_checkpoint_starts_normally(self):
        self.planned()
        work.git(self.root, 'add', '--', str(self.folder.relative_to(self.root)))
        work.git(self.root, 'commit', '-m', 'all planning in one commit')
        self.act('start', 'T000')

    def test_task_commit_must_include_its_completion_and_evidence_records(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        self.ready('T001'); self.act('complete', 'T001')
        work.git(self.root, 'add', '--', 'lib/app.dart', str((self.folder / 'state.json').relative_to(self.root)))
        work.git(self.root, 'commit', '-m', 'source and state only')
        with self.assertRaises(work.Blocked): self.act('status')

    def test_missing_cache_does_not_permit_two_active_changes(self):
        self.initial_map(); self.act('start', 'T001')
        (self.root / '.work/active-task.json').unlink()
        other = work.new_change(self.root, 'Other request', 'small')
        with self.assertRaises(work.Blocked):
            work.worktasks.TaskLoop(self.root, work.__dict__).execute('start', other.name, 'T000')

    def test_map_task_waiting_for_commit_blocks_other_changes(self):
        self.act('start', 'T000'); self.ready('T000'); self.act('complete', 'T000')
        other = work.new_change(self.root, 'Other map request', 'small')
        with self.assertRaises(work.Blocked):
            work.worktasks.TaskLoop(self.root, work.__dict__).execute('start', other.name, 'T000')

    def test_unrelated_records_staged_late_cannot_enter_task_commit(self):
        self.initial_map(); self.act('start', 'T001'); self.write('lib/app.dart', 'changed')
        self.ready('T001')
        other = 'workflow/work/changes/999-owner/log.md'
        self.write(other, 'unrelated owner work')
        work.git(self.root, 'add', '--', other)
        with self.assertRaises(work.Blocked): self.act('complete', 'T001')
        work.git(self.root, 'reset', '-q', 'HEAD', '--', other)
        self.act('complete', 'T001')
        work.git(self.root, 'add', '--', 'lib/app.dart', str(self.folder.relative_to(self.root)), other)
        work.git(self.root, 'commit', '-m', 'unexpected unrelated records')
        with self.assertRaises(work.Blocked): self.act('status')
