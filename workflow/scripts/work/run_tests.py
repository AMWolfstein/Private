#!/usr/bin/env python3
"""Run workflow tests; CI additionally requires the real engine/parser tests to execute."""
import argparse
import os
import sys
import unittest
from pathlib import Path

REQUIRED = ('test_codegraph_adapter.RealCodeGraphRegressions.',
            'test_workmap.RealCodeGraphSmokeTests.', 'test_resource_index.BashTests.')
OPTIONAL = 'test_workmap.RealCodeGraphSmokeTests.test_real_extraction_needs_no_network'


class TrackingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs);self.seen = set()
    def startTest(self, test):
        self.seen.add(test.id());super().startTest(test)


def integration_problems(result):
    problems = ['real integration class did not run: ' + prefix for prefix in REQUIRED
                if not any(ident.startswith(prefix) for ident in result.seen)]
    for test, reason in result.skipped:
        if test.id() == OPTIONAL and reason == 'cannot create a network namespace here':
            continue
        problems.append(f'unexpected skip: {test.id()}: {reason}')
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--strict-integrations', action='store_true')
    args = parser.parse_args(argv)
    suite = unittest.defaultTestLoader.discover(str(Path(__file__).resolve().parent), pattern='test_*.py')
    result = unittest.TextTestRunner(resultclass=TrackingResult, verbosity=1).run(suite)
    strict = args.strict_integrations or os.environ.get('WORKFLOW_STRICT_INTEGRATION') == '1'
    problems = integration_problems(result) if strict else []
    for problem in problems: print('INTEGRATION BLOCKED: ' + problem, file=sys.stderr)
    return 0 if result.wasSuccessful() and not problems else 1


if __name__ == '__main__': raise SystemExit(main())
