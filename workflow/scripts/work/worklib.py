"""Small helpers shared by work.py and workmap.py. Standard library only."""
from __future__ import annotations

import fnmatch
import os
import shutil
import subprocess
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

TEST_DIRS = {'test', 'tests', 'integration_test', 'androidTest'}
TEST_SUFFIXES = ('_test.dart', 'Test.kt', 'Tests.kt', '_test.py', '_test.rs')


class Blocked(Exception):
    """A gate, guard or configuration problem the caller must resolve."""


@contextmanager
def file_lock(path: Path, timeout: float = 0):
    """OS-released advisory lock; interrupted commands cannot leave a stale lock."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        import fcntl
        windows = None
    except ImportError:
        import msvcrt as windows
        fcntl = None
    with path.open('a+') as handle:
        deadline = time.monotonic() + timeout
        while True:
            try:
                if fcntl:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                else:
                    handle.seek(0)
                    windows.locking(handle.fileno(), windows.LK_NBLCK, 1)
                break
            except OSError as error:
                if time.monotonic() >= deadline:
                    raise Blocked(f'another workflow operation holds {path.name}; retry when it finishes') from error
                time.sleep(0.1)
        try:
            yield
        finally:
            if fcntl:
                fcntl.flock(handle, fcntl.LOCK_UN)
            else:
                handle.seek(0)
                windows.locking(handle.fileno(), windows.LK_UNLCK, 1)


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def git(root: Path, *args: str, check: bool = True, env: dict | None = None) -> str:
    result = subprocess.run(['git', *args], cwd=root, capture_output=True, env=env)
    if check and result.returncode != 0:
        raise Blocked(f'git {" ".join(args)} failed: {result.stderr.decode(errors="replace").strip()}')
    return result.stdout.decode('utf-8', errors='surrogateescape')


def is_test(path: str) -> bool:
    parts = path.split('/')
    return (any(part in TEST_DIRS for part in parts[:-1]) or parts[-1].endswith(TEST_SUFFIXES)
            or parts[-1].startswith('test_'))


def atomic_write(path: Path, data: str | bytes) -> None:
    """Write a complete file or nothing: readers see the old or the new content, never a mix."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = data.encode() if isinstance(data, str) else data
    handle, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(handle, 'wb') as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def snapshot(root: Path, drop: tuple[str, ...] = (), listing: bool = False,
             exclude: tuple[str, ...] = ()) -> tuple[str, dict[str, tuple[str, str]]]:
    """Stage every non-ignored file into a temporary index; never touches the real index.

    Returns git's tree id of that content (minus `drop` paths) and, with `listing`, each
    path's (mode, blob id). Same content gives the same ids before and after a commit.
    """
    index = Path(git(root, 'rev-parse', '--git-path', 'index').strip())
    index = index if index.is_absolute() else root / index
    with tempfile.TemporaryDirectory(prefix='work-fp-') as temp:
        temp_index = Path(temp) / 'index'
        if index.is_file():
            shutil.copy2(index, temp_index)  # reuse git's cached file hashes
        env = {**os.environ, 'GIT_INDEX_FILE': str(temp_index)}
        commands = [['git', 'add', '--all', '--', '.']]
        if drop:
            commands.append(['git', 'rm', '-r', '--cached', '-q', '--ignore-unmatch', '--', *drop])
        for argv in commands:
            done = subprocess.run(argv, cwd=root, env=env, capture_output=True)
            if done.returncode != 0:
                raise Blocked(f'fingerprint failed: {done.stderr.decode(errors="replace").strip()}')
        if exclude:  # exact paths on stdin: no pathspec magic and no argument-length limit
            done = subprocess.run(['git', 'update-index', '--force-remove', '-z', '--stdin'], cwd=root, env=env,
                                  input='\0'.join(exclude).encode('utf-8', errors='surrogateescape'),
                                  capture_output=True)
            if done.returncode != 0:
                raise Blocked(f'fingerprint failed: {done.stderr.decode(errors="replace").strip()}')
        tree = subprocess.run(['git', 'write-tree'], cwd=root, env=env, capture_output=True,
                              check=True).stdout.decode().strip()
        files: dict[str, tuple[str, str]] = {}
        if listing:
            for entry in git(root, 'ls-files', '--stage', '-z', env=env).split('\0'):
                if entry:
                    meta, path = entry.split('\t', 1)
                    mode, blob, _stage = meta.split(' ')
                    files[path] = (mode, blob)
        return tree, files


def committed_fingerprint(root: Path, commit: str, drop: tuple[str, ...]) -> str:
    """Tree id of a commit minus `drop` paths, comparable with snapshot(); never touches the real index."""
    with tempfile.TemporaryDirectory(prefix='work-commit-fp-') as folder:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(folder) / 'index')}
        git(root, 'read-tree', commit, env=env)
        git(root, 'rm', '-r', '-f', '--cached', '-q', '--ignore-unmatch', '--', *drop, env=env)
        return git(root, 'write-tree', env=env).strip()


def domains_for(config: dict, paths: list[str]) -> dict[str, list[str]]:
    """Domains of checks.json whose fnmatch patterns ('*' crosses '/') match each path."""
    found: dict[str, list[str]] = {}
    for path in paths:
        for domain, patterns in config['domains'].items():
            if any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns):
                found.setdefault(domain, []).append(path)
    return found
