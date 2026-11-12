#!/usr/bin/env python3
"""Report-only compiler diagnostics for dead-code, optimization and simplification scans."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import fnmatch
import json
from pathlib import Path
import subprocess
import codegraph_adapter

def parse_dart_machine(output: str, root: Path, tool: dict) -> list[dict]:
    """dart analyze --format=machine: SEVERITY|TYPE|CODE|path|line|column|length|message."""
    found = []
    for line in output.splitlines():
        parts = line.split('|', 7)
        if len(parts) != 8 or not parts[4].isdigit():
            continue
        path = Path(parts[3])
        try:
            relative = path.resolve().relative_to(root.resolve()).as_posix() if path.is_absolute() else path.as_posix()
        except ValueError:
            continue
        found.append({'path': relative, 'line': int(parts[4]), 'code': parts[2].lower(), 'message': parts[7], 'severity': parts[0].lower()})
    return found

def parse_cargo_json(output: str, root: Path, tool: dict) -> list[dict]:
    """cargo --message-format=json: one compiler-message object per diagnostic."""
    base = (root / tool.get('cwd', '.')).resolve()
    found, seen = [], set()
    for line in output.splitlines():
        if not line.startswith('{'):
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get('message') or {}
        code = (message.get('code') or {}).get('code') or ('compiler_error' if message.get('level') == 'error' else None)
        span = next((s for s in message.get('spans', []) if s.get('is_primary')), None)
        if entry.get('reason') != 'compiler-message' or not code or not span:
            continue
        path = Path(span['file_name'])
        try:
            relative = (path if path.is_absolute() else base / path).resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        key = (relative, span['line_start'], code, message.get('message'))
        if key not in seen:  # the same diagnostic repeats for each target that compiles the file
            seen.add(key)
            found.append({'path': relative, 'line': span['line_start'], 'code': code,
                          'message': message.get('message', ''), 'severity': message.get('level', '')})
    return found


def select_files(root, config, languages, paths, base=None):
    unknown = set(languages) - set(config['languages'])
    if unknown: raise ValueError(f'Unknown languages: {sorted(unknown)}')
    argv = ['git','-C',str(root)]
    tracked = subprocess.run([*argv,*(['diff','--name-only','-z',base] if base else ['ls-files','-z'])],
                             capture_output=True,check=True).stdout.decode()
    others = subprocess.run([*argv,'ls-files','-z','--others','--exclude-standard'],capture_output=True,check=True).stdout.decode()
    prefixes = []
    for raw in paths:
        path = (root/raw).resolve()
        if not path.exists() or not path.is_relative_to(root): raise ValueError(f'Invalid scope: {raw}')
        prefixes.append(path.relative_to(root).as_posix())
    result, protected = {}, []
    for path in sorted(set((tracked+'\0'+others).split('\0'))-{''}):
        if any(part in {'.git','.work','.dart_tool','build','target','node_modules','__pycache__'} for part in Path(path).parts): continue
        if prefixes and not any(prefix=='.' or path==prefix or path.startswith(prefix+'/') for prefix in prefixes): continue
        language = next((name for name, data in config['languages'].items() if Path(path).suffix in data['extensions']),None)
        if not language or (languages and language not in languages): continue
        if any(fnmatch.fnmatchcase(path,p) for p in config['languages'][language].get('tests',[])): continue
        if not (root/path).is_file(): continue
        if (root/path).is_symlink() or not (root/path).resolve().is_relative_to(root): raise ValueError(f'Unsafe input: {path}')
        if any(fnmatch.fnmatchcase(path,p) for p in config['protected']): protected.append(path);continue
        result.setdefault(language,[]).append(path)
    return result, protected


def classify(found, categories, kind, language):
    kinds = list(categories) if kind=='code' else [kind]
    result=[]
    for finding in found:
        matches=[name for name in kinds if finding['code'] in categories[name].get(language,[])]
        if matches: result.append({**finding,'categories':matches,'evidence':'tool-diagnostic','confidence':'REVIEW_REQUIRED'})
    return result


def run_tool(root, language, tool, members, kind, log):
    if not tool: return [], {'status':'UNAVAILABLE','reason':'No diagnostic runner configured for this language'}
    argv=list(tool['run'])
    if language=='dart' and len(members)==1: argv.append(members[0])
    if language=='rust' and kind!='dead-code':
        argv[2]='clippy'
        argv += ['--','-W','clippy::perf','-W','clippy::complexity','-W','clippy::style']
    try:
        done=subprocess.run(argv,cwd=root/tool['cwd'],capture_output=True,text=True,errors='replace',
                            stdin=subprocess.DEVNULL,timeout=tool['timeout'])
    except (OSError,subprocess.TimeoutExpired) as error:
        return [], {'status':'INCOMPLETE','command':argv,'reason':str(error)}
    log.write_text(done.stdout+'\n--- stderr ---\n'+done.stderr)
    parser={'dart-machine':parse_dart_machine,'cargo-json':parse_cargo_json}[tool['parser']]
    found=parser(done.stdout,root,tool)
    errors=sum(f.get('severity')=='error' for f in found)
    failed=errors>0 or (done.returncode!=0 and (language!='dart' or not found))
    return found, {'status':'INCOMPLETE' if failed else 'RAN','command':argv,'exit_code':done.returncode,
                   'diagnostics':len(found),'errors':errors,'log':str(log),
                   'scope_note':'Runner may analyze additional files; findings below are filtered to the selected scope'}


def scan(root, kind='code', languages=(), paths=(), base=None):
    root=root.resolve()
    if not (languages or paths or base): raise ValueError('Choose --lang, --path, --base or --all')
    config=json.loads(Path(__file__).with_name('audit-config.json').read_text())
    if kind!='code' and kind not in config['categories']: raise ValueError('Unknown audit kind')
    files,protected=select_files(root,config,languages,paths,base)
    directory=root/'.work/audit'/kind;directory.mkdir(parents=True,exist_ok=True)
    findings=[];tools={}
    for language,members in files.items():
        found,tools[language]=run_tool(root,language,config['tools'].get(language),members,kind,directory/f'{language}.log')
        selected=set(members)
        findings.extend(classify([f for f in found if f['path'] in selected],config['categories'],kind,language))
    gaps=[name for name,tool in tools.items() if tool['status']!='RAN']
    result={'status':'NO_FILES' if not files else 'INCOMPLETE' if gaps else 'FINDINGS' if findings else 'PASS',
            'kind':kind,'at':datetime.now(timezone.utc).isoformat(),'scope':{'languages':list(languages),'paths':list(paths),'base':base},
            'file_list':files,'protected_skipped':protected,'tools':tools,'gaps':gaps,'findings':findings,
            'limits':config['notes']+['No source files are modified. Compiler tools can write build caches and execute build scripts.',
             'A clean report is not proof that all dead code has been found. Only emitted, allowlisted diagnostics are classified.',
             'Compiler errors make coverage incomplete. Dart suggestions depend on the enabled analyzer lints.',
             'Validate cross-language references and behavior before applying any suggestion.']}
    (directory/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    lines=[f'# Code scan: {kind}', '', f'Status: {result["status"]}', '',
           f'Files: {sum(map(len,files.values()))}; findings: {len(findings)}; protected: {len(protected)}.', '', '## Tools', '']
    lines += [f'- {name}: {tool["status"]} — {tool.get("reason",str(tool.get("command")))}' for name,tool in tools.items()]
    lines += ['', '## Candidates requiring verification', '']
    lines += [f'- `{f["path"]}:{f["line"]}` [{f["code"]}] ({", ".join(f["categories"])}) {f["message"]}' for f in findings] or ['None reported in this scope.']
    lines += ['', '## Limits', '']+[f'- {note}' for note in result['limits']]
    (directory/'report.md').write_text('\n'.join(lines)+'\n')
    return result,directory/'report.md'


def configure_parser(p, include_root=True):
    if include_root: p.add_argument('--root',type=Path,default=Path.cwd())
    p.add_argument('--kind',choices=['code','dead-code','optimization','simplifier'],default='code')
    p.add_argument('--lang',nargs='+',default=[])
    p.add_argument('--path',action='append',default=[])
    p.add_argument('--base');p.add_argument('--all',action='store_true')
    return p


def execute(args):
    result,report=scan(args.root,args.kind,args.lang,args.path or (['.'] if args.all else []),args.base)
    print(json.dumps({'status':result['status'],'findings':len(result['findings']),'gaps':result['gaps'],'report':str(report)}))
    return 2 if result['status'] in ('INCOMPLETE','NO_FILES') else 1 if result['findings'] else 0


def main(argv=None):
    p=configure_parser(argparse.ArgumentParser(description=__doc__))
    args=p.parse_args(argv)
    try:
        return execute(args)
    except (ValueError,OSError,subprocess.CalledProcessError) as error:
        p.error(str(error))

if __name__=='__main__':
    raise SystemExit(main())
