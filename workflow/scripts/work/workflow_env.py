"""Linux-only project-local setup and read-only environment diagnostics."""
from __future__ import annotations
import fcntl
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

from worklib import Blocked, atomic_write

HERE = Path(__file__).resolve().parent


def managed_python(root): return root / '.work/python/bin/python'


def managed_codegraph(root): return root / '.work/tools/node_modules/.bin/codegraph'


def resolve_command(root, configured):
    if configured == ['codegraph'] and managed_codegraph(root).is_file():
        confined(root)
        return [str(managed_codegraph(root))]
    if configured and ('/' in configured[0] or '\\' in configured[0]) and not Path(configured[0]).is_absolute():
        return [str((root / configured[0]).resolve()), *configured[1:]]
    return list(configured)


def confined(root):
    base = root / '.work'
    paths = [base, base / 'python', base / 'python/bin', base / 'python/lib', base / 'tools',
             base / 'tools/node_modules', base / 'tools/node_modules/.bin', base / 'cache', base / 'cache/pip', base / 'cache/npm']
    paths += list((base / 'python/lib').glob('python*/site-packages')) if (base / 'python/lib').is_dir() else []
    for path in paths:
        if path.is_symlink() or not path.resolve().is_relative_to(base.resolve()):
            raise Blocked(f'managed environment directory must not be a symlink/outside .work: {path}')
    for name in ('setup.log', 'setup.lock', 'environment.json'):
        if (base / name).is_symlink(): raise Blocked('managed metadata/log must not be a symlink: ' + name)
    engine = managed_codegraph(root)
    if engine.is_symlink() and not engine.resolve().is_relative_to(base.resolve()):
        raise Blocked('managed CodeGraph symlink must resolve inside .work')


def reexec(root):
    """CLI only: let resources/TOML and child checks use the managed interpreter."""
    confined(root)
    interpreter = managed_python(root)
    if not interpreter.is_file() or Path(sys.prefix).resolve() == interpreter.parent.parent.resolve():
        return
    if os.environ.get('WORKFLOW_ENV_REEXEC') == '1':
        raise Blocked('managed Python has an invalid environment prefix; inspect doctor output')
    os.environ['WORKFLOW_ENV_REEXEC'] = '1'
    os.execv(str(interpreter), [str(interpreter), str(HERE / 'work.py'), *sys.argv[1:]])


def clean_environment():
    env = {**os.environ, 'CODEGRAPH_TELEMETRY': '0', 'DO_NOT_TRACK': '1', 'CODEGRAPH_NO_DOWNLOAD': '1',
           'PIP_DISABLE_PIP_VERSION_CHECK': '1', 'PIP_REQUIRE_VIRTUALENV': 'true', 'PIP_CONFIG_FILE': os.devnull}
    for key in ('PIP_TARGET', 'PIP_PREFIX', 'PIP_USER', 'PIP_ROOT', 'PIP_LOG', 'PIP_REPORT', 'PIP_BUILD_TRACKER', 'PIP_SRC', 'PIP_CACHE_DIR'):
        env.pop(key, None)
    return env


def execute(argv, root, timeout=30, log=None):
    result = subprocess.run(argv, cwd=root, capture_output=True, text=True, timeout=timeout,
                            env=clean_environment())
    if log:
        fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'a') as handle:
            handle.write(json.dumps(argv) + '\n' + result.stdout + result.stderr + '\n')
    if result.returncode:
        raise Blocked(f'{Path(argv[0]).name} exited {result.returncode}: {(result.stderr or result.stdout)[-700:]}')
    return result.stdout.strip()


def config(root):
    document = json.loads((root / 'workflow/work/map.json').read_text())
    data = document.get('extractor') if isinstance(document, dict) else None
    if not isinstance(data, dict): raise Blocked('map.json needs an extractor object')
    command = data.get('command')
    if not isinstance(command, list) or not command or not all(isinstance(v, str) and v for v in command):
        raise Blocked('extractor.command must be a nonempty argv list')
    if data.get('name') != 'codegraph' or data.get('package') != '@colbymchenry/codegraph':
        raise Blocked('setup only provisions the configured CodeGraph package')
    if not isinstance(data.get('version'), str) or not all(part.isdigit() for part in data['version'].split('.')):
        raise Blocked('CodeGraph version must be a pinned numeric release')
    return data


def requirements_digest(root):
    return hashlib.sha256((root / 'workflow/scripts/work/requirements.txt').read_bytes()).hexdigest()


def prerequisites(root):
    if platform.system() != 'Linux': raise Blocked('supported environment: Linux cloud/Fedora only')
    if platform.machine().lower() not in ('x86_64', 'amd64', 'aarch64', 'arm64'):
        raise Blocked('CodeGraph Linux bundle requires x86_64 or aarch64')
    if sys.version_info < (3, 10): raise Blocked('Python 3.10+ is required')
    confined(root)
    top = Path(execute(['git', 'rev-parse', '--show-toplevel'], root)).resolve()
    if top != root: raise Blocked('copy AGENTS.md and workflow/ to the Git repository root before setup')
    execute(['git', 'rev-parse', '--verify', 'HEAD'], root)
    # No file is created: git check-ignore accepts an arbitrary pathname.
    tracked = execute(['git', 'ls-files', '-z', '--', '.work'], root)
    if tracked: raise Blocked('managed .work files are tracked by Git; remove them from tracking before setup')
    for path in ('.work/environment-probe', '.work/setup.log', '.work/setup.lock', '.work/environment.json',
                 '.work/tools/node_modules/.bin/codegraph', '.work/python/pyvenv.cfg',
                 '.work/cache/pip/probe', '.work/cache/npm/_logs/probe'):
        execute(['git', 'check-ignore', '--no-index', path], root)


def doctor(root):
    root = Path(root).resolve();checks = []
    def check(name, operation):
        try:
            detail = operation()
            checks.append({'name': name, 'status': 'PASS', 'detail': detail})
        except (Blocked, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            checks.append({'name': name, 'status': 'BLOCKED', 'detail': str(error)})
    check('linux/git/ignore', lambda: prerequisites(root) or {'os': platform.system(), 'arch': platform.machine()})
    if checks[-1]['status'] != 'PASS':
        return {'status': 'BLOCKED', 'checks': checks, 'hint': 'Fix Linux/Git/root/ignore or managed-path prerequisites before provisioning.'}
    try: settings = config(root)
    except (OSError, ValueError, KeyError, Blocked) as error:
        return {'status': 'BLOCKED', 'checks': checks + [{'name': 'configuration', 'status': 'BLOCKED', 'detail': str(error)}]}
    interpreter = managed_python(root)
    def python_info():
        code = 'import sys,json; print(json.dumps({"version":sys.version.split()[0],"prefix":sys.prefix}))'
        info = json.loads(execute([str(interpreter), '-c', code], root))
        if Path(info['prefix']).resolve() != interpreter.parent.parent.resolve(): raise Blocked('not the managed virtual environment')
        if tuple(map(int, info['version'].split('.')[:2])) < (3, 10): raise Blocked('managed Python is older than 3.10')
        return info
    check('managed-python', python_info)
    def parser_info():
        probe = "import json,sys; exec('import tomllib' if sys.version_info >= (3,11) else 'import tomli as tomllib'); assert tomllib.loads('[doctor]\\nok=true')['doctor']['ok']; print('TOML parser ready')"
        execute([str(interpreter), '-c', probe], root)
        shell_python = os.environ.get('WORK_SHELL_PYTHON')
        import shlex
        argv = shlex.split(shell_python) if shell_python else [str(interpreter)]
        info = json.loads(execute([*argv, str(root / 'workflow/scripts/work/shell_adapter.py'), 'version'], root))
        if not info.get('available'): raise Blocked(info.get('reason', 'pinned Bash packages unavailable'))
        with tempfile.TemporaryDirectory(prefix='workflow-doctor-') as temporary:
            source, request = Path(temporary) / 'probe.sh', Path(temporary) / 'request.json'
            source.write_text('probe() { :; }\nprobe\n')
            request.write_text(json.dumps([{'file': 'probe.sh', 'path': str(source)}]))
            data = json.loads(execute([*argv, str(root / 'workflow/scripts/work/shell_adapter.py'), 'extract', '--request', str(request)], root))
            if not data or data[0]['errors'] or not data[0]['functions']: raise Blocked('real Bash parse probe failed')
        return info
    check('real-bash-and-toml', parser_info)
    def engine():
        if settings['command'] == ['codegraph'] and not managed_codegraph(root).is_file():
            raise Blocked('project-local CodeGraph missing; run setup')
        command = resolve_command(root, settings['command'])
        installed = execute([*command, '--version'], root)
        if installed != settings['version']: raise Blocked(f'CodeGraph {settings["version"]} required, got {installed}')
        return {'version': installed, 'command': command}
    check('codegraph', engine)
    def specification():
        marker = json.loads((root / '.work/environment.json').read_text())
        if not isinstance(marker, dict): raise Blocked('invalid environment.json metadata; rerun setup')
        if marker.get('requirements_sha256') != requirements_digest(root): raise Blocked('requirements changed; rerun setup')
        if marker.get('codegraph') != settings['version']: raise Blocked('engine pin changed; rerun setup')
        return 'managed environment matches current dependency specification'
    check('dependency-specification', specification)
    return {'status': 'PASS' if all(c['status'] == 'PASS' for c in checks) else 'BLOCKED', 'checks': checks,
            'hint': 'Run python3 workflow/scripts/work/work.py setup if blocked; Node/npm are needed for initial provisioning only.'}


@contextmanager
def setup_lock(root):
    path = root / '.work/setup.lock';path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a') as handle:
        deadline = time.monotonic() + 5
        while True:
            try: fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB);break
            except BlockingIOError:
                if time.monotonic() >= deadline: raise Blocked('another setup is running; retry after it completes')
                time.sleep(0.1)
        try: yield
        finally: fcntl.flock(handle, fcntl.LOCK_UN)


def setup(root, offline=False):
    root = Path(root).resolve()
    try: prerequisites(root)
    except (OSError, subprocess.TimeoutExpired, Blocked) as error:
        raise Blocked('setup prerequisites: ' + str(error) + '; ensure Git HEAD exists and .gitignore excludes .work/') from error
    settings = config(root)
    with setup_lock(root):
        before = doctor(root)
        if before['status'] == 'PASS': return {**before, 'reused': True}
        if offline: return {**before, 'reused': False, 'hint': 'Offline mode does not download dependencies; run setup online first.'}
        log = root / '.work/setup.log'
        interpreter = managed_python(root)
        if not interpreter.exists(): execute([sys.executable, '-m', 'venv', str(interpreter.parent.parent)], root, 90, log)
        # Even an old/broken environment cannot redirect installs outside the project.
        prefix = execute([str(interpreter), '-c', 'import sys;print(sys.prefix)'], root)
        if Path(prefix).resolve() != interpreter.parent.parent.resolve(): raise Blocked('managed Python prefix is invalid')
        pip_cache = root / '.work/cache/pip'
        execute([str(interpreter), '-m', 'pip', 'install', '--no-user', '--only-binary=:all:', '--root', '/', '--prefix', str(interpreter.parent.parent), '--cache-dir', str(pip_cache),
                 '-r', str(root / 'workflow/scripts/work/requirements.txt')], root, 600, log)
        npm = shutil.which('npm')
        if not npm: raise Blocked('Node.js/npm is required to provision local CodeGraph; install it for Linux and rerun setup')
        execute([npm, 'install', '--prefix', str(root / '.work/tools'), '--global=false', '--ignore-scripts',
                 '--cache', str(root / '.work/cache/npm'), '--logs-dir', str(root / '.work/cache/npm/_logs'), '--no-audit', '--no-fund', '--update-notifier=false',
                 settings['package'] + '@' + settings['version']], root, 600, log)
        atomic_write(root / '.work/environment.json', json.dumps({'requirements_sha256': requirements_digest(root),
                     'codegraph': settings['version'], 'python': str(interpreter)}) + '\n')
        result = doctor(root)
        return {**result, 'reused': False, 'log': '.work/setup.log'}
