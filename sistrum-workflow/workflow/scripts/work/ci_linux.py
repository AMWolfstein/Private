#!/usr/bin/env python3
"""Linux CI: copy the distribution into a fresh Git root and exercise real setup/checks."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    package = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix='sistrum-workflow-ci-') as temporary:
        root = Path(temporary)
        shutil.copytree(package / 'workflow', root / 'workflow', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copy2(package / 'AGENTS.md', root / 'AGENTS.md')
        shutil.copy2(package / '.gitignore', root / '.gitignore')
        if (package / '.github').is_dir(): shutil.copytree(package / '.github', root / '.github')
        env = dict(os.environ)
        for key in list(env):
            if key.startswith(('FAKE_CODEGRAPH', 'WORK_MAP_', 'WORK_SHELL_', 'WORK_CODEGRAPH_')) or key == 'WORKFLOW_ENV_REEXEC':
                env.pop(key)
        def run(argv, capture=False):
            done = subprocess.run(argv, cwd=root, env=env, text=True,
                                  stdout=subprocess.PIPE if capture else None)
            if done.returncode:
                if capture and done.stdout: print(done.stdout, file=sys.stderr)
                latest = root / '.work/runs/latest.json'
                if latest.is_file():
                    report = json.loads(latest.read_text())
                    for check in report.get('checks', []):
                        log = (root / check.get('log', '')).resolve()
                        if log.is_relative_to(root / '.work') and log.is_file():
                            print(log.read_text(errors='replace')[-20000:], file=sys.stderr)
                raise subprocess.CalledProcessError(done.returncode, argv)
            return json.loads(done.stdout) if capture else None
        for args in [['git', 'init', '-q'], ['git', 'config', 'user.name', 'Workflow CI'],
                     ['git', 'config', 'user.email', 'workflow-ci@example.invalid'], ['git', 'add', '.'],
                     ['git', 'commit', '-qm', 'copied distribution']]: run(args)
        tool = 'workflow/scripts/work/work.py'
        run([sys.executable, tool, 'setup'])
        first = run([sys.executable, tool, 'doctor'], True)
        if first['status'] != 'PASS': raise RuntimeError('doctor failed')
        again = run([sys.executable, tool, 'setup', '--offline'], True)
        if not again.get('reused'): raise RuntimeError('setup is not reusable offline')
        env['PATH'] = str(root / '.work/tools/node_modules/.bin') + os.pathsep + env.get('PATH', '')
        env['WORKFLOW_STRICT_INTEGRATION'] = '1'
        report = run([sys.executable, tool, 'check', 'workflow'], True)
        print(json.dumps(report, indent=2))
        if report['status'] != 'PASS' or report['tests']['failed']: raise RuntimeError('workflow checks failed')
        run([sys.executable, tool, 'fresh'])
        # Setup/checks may create only ignored runtime state, not tracked project changes.
        dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, env=env, text=True)
        if dirty.strip(): raise RuntimeError('installation dirtied the copied project: ' + dirty)
        print('Linux setup, doctor, offline reuse, strict real integrations and clean copied installation PASS')
    return 0


if __name__ == '__main__': raise SystemExit(main())
