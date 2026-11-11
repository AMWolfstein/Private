import datetime as dt
import importlib.util
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]

def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

watch = module('watch')
publish = module('publish')


class FakeGitHub:
    def __init__(self, versions, commits):
        self.versions = versions
        self.commits = commits
        self.reads = []

    def head(self, repository, branch):
        return self.commits[repository]

    def tree(self, repository, commit):
        return {p: watch.blob_hash(data) for p, data in self.versions[(repository, commit)].items()}

    def file(self, repository, commit, path):
        self.reads.append((repository, commit, path))
        return self.versions[(repository, commit)][path]


def config():
    return {'anchor_monday': '2026-11-09', 'interval_days': 14, 'target_branch': 'extension-system',
            'sources': [{'id': 'extensions', 'repository': 'owner/source', 'branch': 'main',
                         'paths': ['LICENSE'], 'prefixes': ['sources/apple-music/']}]}


class WatchTests(unittest.TestCase):
    def test_alternating_mondays_and_year_boundary(self):
        for offset in [0, 14, 28, 56, 364]:
            self.assertTrue(watch.due(config(), dt.date(2026, 11, 9) + dt.timedelta(days=offset)))
        for offset in [-14, 1, 7, 21, 35]:
            self.assertFalse(watch.due(config(), dt.date(2026, 11, 9) + dt.timedelta(days=offset)))

    def test_unsafe_path_is_rejected(self):
        for value in ['../lib/main.dart', '/etc/passwd', 'sources/../../a', 'sources/a\ncommand']:
            with self.assertRaises(ValueError):
                watch.safe_path(value)

    def test_only_selected_sources_are_compared_and_upstream_code_is_not_executed(self):
        old = {'sources/apple-music/index.js': b'original\n', 'LICENSE': b'license',
               'sources/jellyfin/index.js': b'old jellyfin'}
        new = {'sources/apple-music/index.js': b'throw new Error("must never execute");\n',
               'sources/apple-music/helper.js': b'new helper\n', 'LICENSE': b'license',
               'sources/jellyfin/index.js': b'new jellyfin', 'lib/main.dart': b'unrelated'}
        client = FakeGitHub({('owner/source', 'old'): old, ('owner/source', 'new'): new}, {'owner/source': 'new'})
        changes, proposed = watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)
        paths = [c['path'] for c in changes[0]['changes']]
        self.assertEqual(paths, ['sources/apple-music/helper.js', 'sources/apple-music/index.js'])
        self.assertNotIn('sources/jellyfin/index.js', [p for _, _, p in client.reads])
        self.assertEqual(proposed['sources']['extensions']['reviewed_commit'], 'new')
        self.assertIn('+throw new Error', changes[0]['changes'][1]['patch'])

    def test_no_changes_do_not_create_state_churn_or_pr_artifacts(self):
        data = {'sources/apple-music/index.js': b'unchanged'}
        client = FakeGitHub({('owner/source', 'old'): data, ('owner/source', 'new'): data}, {'owner/source': 'new'})
        changes, state = watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(watch.prepare(Path(tmp), changes, state, config()))
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_native_initial_baseline_uses_verified_local_content(self):
        old, new = b'old native lyrics\n', b'new native lyrics\n'
        client = FakeGitHub({('owner/source', 'new'): {'sources/apple-music/index.js': new}}, {'owner/source': 'new'})
        state = {'sources': {'extensions': {'reviewed_commit': None,
                 'files': {'sources/apple-music/index.js': watch.blob_hash(old)}}}}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sources/apple-music/index.js'
            path.parent.mkdir(parents=True)
            path.write_bytes(old)
            updates, _ = watch.scan(config(), state, client, Path(tmp))
        self.assertIn('-old native lyrics', updates[0]['changes'][0]['patch'])

    def test_missing_or_modified_local_baseline_is_not_fabricated(self):
        old, new = b'old', b'new'
        client = FakeGitHub({('owner/source', 'new'): {'sources/apple-music/index.js': new}}, {'owner/source': 'new'})
        state = {'sources': {'extensions': {'reviewed_commit': None,
                 'files': {'sources/apple-music/index.js': watch.blob_hash(old)}}}}
        with tempfile.TemporaryDirectory() as tmp:
            updates, _ = watch.scan(config(), state, client, Path(tmp))
        self.assertIsNone(updates[0]['changes'][0]['patch'])
        self.assertFalse(updates[0]['changes'][0]['baseline_available'])

    def test_removed_file_produces_a_deletion_diff(self):
        old = {'sources/apple-music/index.js': b'old\n'}
        client = FakeGitHub({('owner/source', 'old'): old, ('owner/source', 'new'): {}}, {'owner/source': 'new'})
        updates, _ = watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)
        self.assertIsNone(updates[0]['changes'][0]['after'])
        self.assertIn('-old', updates[0]['changes'][0]['patch'])

    def test_blob_mismatch_aborts_before_any_proposal_is_written(self):
        client = FakeGitHub({('owner/source', 'old'): {}, ('owner/source', 'new'): {'sources/apple-music/index.js': b'new'}}, {'owner/source': 'new'})
        client.file = lambda *args: b'tampered'
        with self.assertRaisesRegex(ValueError, 'blob mismatch'):
            watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)

    def test_partial_api_tree_cannot_imply_deleted_sources(self):
        client = watch.GitHub()
        client.read = lambda url: b'{"truncated":true,"tree":[]}'
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            client.tree('owner/source', 'a' * 40)

    def test_proposal_only_writes_under_extensions_updates(self):
        client = FakeGitHub({('owner/source', 'old'): {}, ('owner/source', 'new'): {'sources/apple-music/index.js': b'new\n'}}, {'owner/source': 'new'})
        changes, state = watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            root.joinpath('lib').mkdir()
            app = root / 'lib/main.dart'
            app.write_text('unchanged')
            proposal = watch.prepare(root, changes, state, config())
            self.assertEqual(app.read_text(), 'unchanged')
            self.assertTrue(proposal['branch'].startswith('automation/extension-updates-'))
            report = (root / proposal['body_file']).read_text()
            self.assertIn('No provider implementation was updated', report)
            self.assertIn('manual adaptation', report)
            self.assertTrue((root / 'extensions/updates/patches/extensions/sources/apple-music/index.js.patch').exists())

    def test_diff_without_final_newlines_is_valid_git_patch_data(self):
        old = {'sources/apple-music/index.js': b'old without newline'}
        new = {'sources/apple-music/index.js': b'new without newline'}
        client = FakeGitHub({('owner/source', 'old'): old, ('owner/source', 'new'): new}, {'owner/source': 'new'})
        updates, _ = watch.scan(config(), {'sources': {'extensions': {'reviewed_commit': 'old'}}}, client)
        diff = updates[0]['changes'][0]['patch']
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'sources/apple-music/index.js'
            file.parent.mkdir(parents=True)
            file.write_bytes(old['sources/apple-music/index.js'])
            result = subprocess.run(['git', 'apply', '--check', '-'], input=diff, text=True,
                                    cwd=tmp, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_actual_config_has_no_jellyfin_or_download_provider_scope(self):
        settings = watch.read_json(HERE / 'watch.json')
        self.assertEqual([s['repository'] for s in settings['sources']], ['mornyeapp/Mornye-Extension', 'mornyeapp/Mornye'])
        self.assertFalse(any('jellyfin' in p for s in settings['sources'] for p in s['paths'] + s['prefixes']))
        self.assertEqual(settings['target_branch'], 'extension-system-rust-json')


class PublishTests(unittest.TestCase):
    def setup_root(self, tmp):
        root = Path(tmp)
        folder = root / 'extensions/updates'
        (folder / '.cache').mkdir(parents=True)
        (folder / '.cache/proposal.json').write_text(json.dumps({'base': 'extension-system',
            'branch': 'automation/extension-updates-' + 'a' * 16,
            'title': 'Review', 'body_file': 'extensions/updates/reports/latest.md'}))
        (folder / 'watch.json').write_text(json.dumps({'target_branch': 'extension-system'}))
        return root

    def test_existing_review_prevents_duplicate_pr_and_any_push(self):
        calls = []
        def fake(*args):
            calls.append(args)
            return '[{"headRefName":"automation/extension-updates-pending","url":"https://example.test/pr/1"}]'
        with tempfile.TemporaryDirectory() as tmp, patch.object(publish, 'run', fake):
            with patch.object(publish, 'ROOT', self.setup_root(tmp)):
                publish.main()
        self.assertEqual(len(calls), 1)

    def test_existing_closed_proposal_branch_is_not_force_updated(self):
        calls = []
        def fake(*args):
            calls.append(args)
            return '[]' if args[0] == 'gh' else 'existing-sha refs/heads/proposal'
        with tempfile.TemporaryDirectory() as tmp, patch.object(publish, 'run', fake):
            with patch.object(publish, 'ROOT', self.setup_root(tmp)):
                publish.main()
        self.assertFalse(any('push' in call or 'create' in call for call in calls))

    def test_success_creates_draft_pr_without_merge_or_force_push(self):
        calls = []
        def fake(*args):
            calls.append(args)
            if args[:3] == ('gh', 'pr', 'list'):
                return '[]'
            if args[:3] == ('git', 'ls-files', '-m'):
                return 'extensions/updates/state.json\0extensions/updates/reports/latest.md\0'
            return ''
        with tempfile.TemporaryDirectory() as tmp, patch.object(publish, 'run', fake):
            with patch.object(publish, 'ROOT', self.setup_root(tmp)):
                publish.main()
        created = next(c for c in calls if c[:3] == ('gh', 'pr', 'create'))
        self.assertIn('--draft', created)
        self.assertFalse(any('--force' in c or 'merge' in c or 'release' in c for c in calls))

    def test_unrelated_changes_are_never_staged(self):
        calls = []
        def fake(*args):
            calls.append(args)
            if args[:3] == ('gh', 'pr', 'list'):
                return '[]'
            if args[:3] == ('git', 'ls-files', '-m'):
                return 'lib/main.dart\0'
            return ''
        with tempfile.TemporaryDirectory() as tmp, patch.object(publish, 'run', fake):
            with patch.object(publish, 'ROOT', self.setup_root(tmp)):
                with self.assertRaisesRegex(ValueError, 'Unrelated'):
                    publish.main()
        self.assertFalse(any('add' in c for c in calls))

    def test_state_filename_prefix_does_not_grant_write_scope(self):
        def fake(*args):
            if args[:3] == ('gh', 'pr', 'list'):
                return '[]'
            return 'extensions/updates/state.json.unrelated\0' if args[:3] == ('git', 'ls-files', '-m') else ''
        with tempfile.TemporaryDirectory() as tmp, patch.object(publish, 'run', fake):
            with patch.object(publish, 'ROOT', self.setup_root(tmp)):
                with self.assertRaisesRegex(ValueError, 'Unrelated'):
                    publish.main()


if __name__ == '__main__':
    unittest.main()
