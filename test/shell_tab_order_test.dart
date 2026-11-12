import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/screens/main_shell.dart';
import 'package:mornye/services/shell_navigation_service.dart';

void main() {
  group('shell tab order', () {
    test('without the extension store, search follows the library', () {
      expect(shellTabAt(0, showStore: false), ShellTab.home);
      expect(shellTabAt(1, showStore: false), ShellTab.library);
      expect(shellTabAt(2, showStore: false), ShellTab.search);
    });

    test('with the extension store, it sits before search', () {
      expect(shellTabAt(2, showStore: true), ShellTab.repository);
      expect(shellTabAt(3, showStore: true), ShellTab.search);
    });

    test('tab indexes match their position', () {
      expect(shellIndexOfTab(ShellTab.home, showStore: false), 0);
      expect(shellIndexOfTab(ShellTab.library, showStore: false), 1);
      expect(shellIndexOfTab(ShellTab.search, showStore: false), 2);
      expect(shellIndexOfTab(ShellTab.repository, showStore: false), isNull);
      expect(shellIndexOfTab(ShellTab.repository, showStore: true), 2);
      expect(shellIndexOfTab(ShellTab.search, showStore: true), 3);
    });

    test('settings is a page, not a tab', () {
      expect(shellIndexOfTab(ShellTab.settings, showStore: false), isNull);
      expect(shellIndexOfTab(ShellTab.settings, showStore: true), isNull);
    });

    test('an index maps back to the tab it came from', () {
      for (final showStore in [false, true]) {
        for (final tab in [ShellTab.home, ShellTab.library, ShellTab.search]) {
          final index = shellIndexOfTab(tab, showStore: showStore)!;
          expect(shellTabAt(index, showStore: showStore), tab);
        }
      }
    });
  });
}
