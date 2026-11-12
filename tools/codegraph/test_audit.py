import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import audit


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        self.config=json.loads(Path(audit.__file__).with_name('audit-config.json').read_text())

    def write(self,path,text):
        target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text)

    def test_scope_excludes_generated_tests_vendor_and_rejects_unknown_languages(self):
        for path in ['lib/main.dart','lib/main.g.dart','test/main_test.dart','third_party/a.dart','src/lib.rs']:
            self.write(path,'')
        files,protected=audit.select_files(self.root,self.config,['dart'],['.'])
        self.assertEqual(files,{'dart':['lib/main.dart']})
        self.assertEqual(protected,['lib/main.g.dart','third_party/a.dart'])
        with self.assertRaises(ValueError): audit.select_files(self.root,self.config,['bogus'],['.'])
        with self.assertRaises(ValueError): audit.select_files(self.root,self.config,[],['../'])

    def test_dart_parser_and_classification_separate_categories(self):
        output=f'WARNING|STATIC_WARNING|UNUSED_IMPORT|{self.root}/lib/main.dart|3|1|4|Unused import\nINFO|LINT|UNNECESSARY_NEW|lib/main.dart|4|1|4|Remove new\n'
        found=audit.parse_dart_machine(output,self.root,{})
        dead=audit.classify(found,self.config['categories'],'dead-code','dart')
        simple=audit.classify(found,self.config['categories'],'simplifier','dart')
        self.assertEqual([f['code'] for f in dead],['unused_import'])
        self.assertEqual([f['code'] for f in simple],['unnecessary_new'])
        self.assertEqual(dead[0]['confidence'],'REVIEW_REQUIRED')

    def test_rust_uncoded_error_is_retained_and_duplicate_warning_deduplicated(self):
        error={'reason':'compiler-message','message':{'level':'error','message':'broken','spans':[{'file_name':'src/lib.rs','is_primary':True,'line_start':4}]}}
        warning={'reason':'compiler-message','message':{'level':'warning','message':'unused','code':{'code':'dead_code'},'spans':[{'file_name':'src/lib.rs','is_primary':True,'line_start':5}]}}
        found=audit.parse_cargo_json('\n'.join(map(json.dumps,[error,warning,warning])),self.root,{'cwd':'rust_backend'})
        self.assertEqual([f['code'] for f in found],['compiler_error','dead_code'])
        self.assertEqual(found[0]['path'],'rust_backend/src/lib.rs')

    def test_nonzero_without_diagnostics_and_mixed_compiler_errors_are_incomplete(self):
        for output in ['',f'ERROR|COMPILE_TIME_ERROR|BROKEN|{self.root}/lib/main.dart|1|1|1|error']:
            with mock.patch.object(audit.subprocess,'run',return_value=subprocess.CompletedProcess([],2,output,'')):
                _,status=audit.run_tool(self.root,'dart',self.config['tools']['dart'],['lib/main.dart'],'code',self.root/'tool.log')
            self.assertEqual(status['status'],'INCOMPLETE')

    def test_rust_uses_explicit_toolchain_locked_clippy_for_suggestions(self):
        with mock.patch.object(audit.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','')) as run:
            audit.run_tool(self.root,'rust',self.config['tools']['rust'],['src/lib.rs'],'optimization',self.root/'tool.log')
        argv=run.call_args.args[0]
        self.assertEqual(argv[:3],['cargo','+1.99.1','clippy'])
        self.assertIn('--locked',argv);self.assertIn('clippy::perf',argv)
        self.assertEqual(run.call_args.kwargs['cwd'],self.root/'rust_backend')

    def test_reports_findings_and_gaps_without_modifying_source(self):
        self.write('lib/main.dart','void main() {}');self.write('android/Main.kt','class Main')
        found=[{'path':'lib/main.dart','line':1,'code':'unused_import','message':'candidate'}]
        def run(root,language,*args):return (found,{'status':'RAN'}) if language=='dart' else ([],{'status':'UNAVAILABLE'})
        with mock.patch.object(audit,'run_tool',side_effect=run):
            result,report=audit.scan(self.root,kind='code',paths=['.'])
        self.assertEqual(result['status'],'INCOMPLETE');self.assertEqual(result['gaps'],['kotlin'])
        self.assertEqual(len(result['findings']),1);self.assertTrue(report.is_file())
        self.assertEqual((self.root/'lib/main.dart').read_text(),'void main() {}')

    def test_requires_scope(self):
        with self.assertRaises(ValueError):audit.scan(self.root)
