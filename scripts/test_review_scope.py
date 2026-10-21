#!/usr/bin/env python3
"""Regression tests run in disposable Git fixtures, never the project checkout."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent


class ReviewScopeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='review-scope-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Review fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        for name in ('review_scope.sh', 'review_scope.py'):
            self.write('scripts/' + name, (SOURCE / name).read_text())
        self.write('lib/providers/keep.dart', 'keep\n')
        self.commit()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def scope(self, *args, success=True):
        result = subprocess.run(['bash', 'scripts/review_scope.sh', *args, '--json'],
                                cwd=self.root, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('No reviewable changes', result.stderr)
        return result

    def coverage(self, unit, sha, status='reviewed'):
        self.write('reviews/coverage.md',
                   f'| {unit} | Name | {status} | {sha} | notes | IDs |\n')

    def test_deleted_file_invalidates_subsystem(self):
        self.write('lib/providers/deleted.dart', 'delete\n')
        sha = self.commit()
        self.coverage('state', sha)
        (self.root / 'lib/providers/deleted.dart').unlink()
        self.commit()
        data = self.scope('--subsystem', 'state')
        self.assertEqual(data['status'], 'stale')
        self.assertIn('lib/providers/deleted.dart', data['changed'])
        self.assertIn('lib/providers/deleted.dart', data['deleted'])

    def test_untracked_and_staged_and_unstaged(self):
        self.write('lib/providers/new.dart', 'new\n')
        self.write('lib/providers/staged.dart', 'staged\n')
        self.git('add', 'lib/providers/staged.dart')
        self.write('lib/providers/keep.dart', 'changed\n')
        data = self.scope('--worktree')
        for name in ('new', 'staged', 'keep'):
            self.assertIn(f'lib/providers/{name}.dart', data['files'])

    def test_invalid_revision_fails(self):
        self.scope('nonexistent..HEAD', success=False)

    def test_vendor_patch_not_skipped(self):
        sha = self.git('rev-parse', 'HEAD')
        self.coverage('build', sha)
        path = 'third_party/plugin/android/Plugin.kt'
        self.write(path, 'patched\n')
        self.commit()
        data = self.scope(sha + '..HEAD')
        self.assertIn(path, data['files'])
        self.assertIn('security-auditor', data['suggested_reviewers'])
        self.assertIn('dependency-auditor', data['suggested_reviewers'])
        self.assertIn(path, self.scope('--subsystem', 'build')['files'])

    def test_build_includes_ci_resource_and_nested_manifest(self):
        names = ('.github/workflows/check.yml', 'android/app/src/main/res/xml/backup_rules.xml',
                 'rust_backend/crates/core/Cargo.toml', 'android/app/src/main/cpp/CMakeLists.txt')
        for name in names:
            self.write(name, 'configuration\n')
        self.commit()
        data = self.scope('--subsystem', 'build')
        self.assertTrue(set(names) <= set(data['files']))

    def test_rename_both_domains_and_unusual_paths(self):
        old = 'lib/providers/old name.dart'
        new = 'lib/screens/new\tname\nأ.dart'
        self.write(old, 'same\n')
        sha = self.commit()
        (self.root / 'lib/screens').mkdir(parents=True)
        self.git('mv', old, new)
        self.commit()
        data = self.scope(sha + '..HEAD')
        self.assertIn(old, data['files'])
        self.assertIn(new, data['files'])
        self.assertIn('flutter-dart-auditor', data['suggested_reviewers'])
        self.assertIn('bug-hunter', data['suggested_reviewers'])

    def test_security_not_drowned_by_other_domains(self):
        for path in ('lib/screens/a.dart', 'lib/providers/a.dart', 'rust_backend/a.rs',
                     'android/app/src/main/AndroidManifest.xml'):
            self.write(path, 'line\n' * 200)
        data = self.scope('--worktree')
        self.assertIn('security-auditor', data['suggested_reviewers'])
        self.assertLessEqual(len(data['suggested_reviewers']), 3)
        self.assertTrue(data['split_required'])
        self.assertTrue(data['pending_reviewers'])

    def test_untracked_marks_graph_stale(self):
        sha = self.git('rev-parse', 'HEAD')
        self.write('graphify-out/graph.json', '{}')
        self.write('graphify-out/GRAPH_REPORT.md', f'- Built from commit: `{sha}`\n')
        self.write('lib/providers/new.dart', 'new\n')
        self.assertTrue(self.scope('--worktree')['graph'].startswith('stale'))

    def test_missing_baseline_fails_not_current(self):
        self.coverage('state', 'abcdef123456')
        self.scope('--subsystem', 'state', success=False)

    def test_unchanged_vendor_exclusion_disclosed(self):
        self.write('third_party/plugin/lib/plugin.dart', 'body\n')
        self.write('third_party/plugin/pubspec.yaml', 'manifest\n')
        self.commit()
        data = self.scope('--subsystem', 'build')
        self.assertEqual(data['excluded_vendor_bodies'], 1)
        self.assertIn('third_party/plugin/pubspec.yaml', data['files'])

    def test_partial_not_promoted_to_reviewed(self):
        sha = self.git('rev-parse', 'HEAD')
        self.coverage('state', sha, 'partial')
        self.assertEqual(self.scope('--subsystem', 'state')['status'], 'partial')

    def test_coverage_status_all_subsystems(self):
        self.assertEqual(len(self.scope('--coverage-status')), 10)

    def test_tracked_changes_and_deletion_mark_graph_stale(self):
        sha = self.git('rev-parse', 'HEAD')
        self.write('graphify-out/graph.json', '{}')
        self.write('graphify-out/GRAPH_REPORT.md', f'- Built from commit: `{sha}`\n')
        (self.root / 'lib/providers/keep.dart').unlink()
        self.assertTrue(self.scope('--worktree')['graph'].startswith('stale'))

    def test_binary_patch_and_ignored_untracked(self):
        self.write('.gitignore', 'ignored.dart\n')
        self.commit()
        self.write('lib/providers/ignored.dart', 'ignored\n')
        path = self.root / 'android/app/src/main/res/drawable/icon.png'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'\x00\x01binary')
        self.git('add', str(path.relative_to(self.root)))
        data = self.scope('--worktree')
        self.assertIn(str(path.relative_to(self.root)), data['files'])
        self.assertNotIn('lib/providers/ignored.dart', data['files'])

    def test_no_test_churn_hint(self):
        self.write('lib/providers/keep.dart', 'change\n' * 120)
        self.assertTrue(self.scope('--worktree')['NO_TEST_CHANGES'])

    def test_empty_worktree(self):
        self.assertEqual(self.scope('--worktree')['files'], [])


if __name__ == '__main__':
    unittest.main()
