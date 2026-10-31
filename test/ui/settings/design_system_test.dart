import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import '../../support/material_test_theme.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_search_field.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/selection/selection_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/widgets/settings/settings_chips_and_cards.dart';
import 'package:sistrum/widgets/library/track_card.dart';

part 'design_system_1.dart';
part 'design_system_2.dart';
part 'design_system_3.dart';

/// Every Dart source file under `lib/`, used by the source-level contracts
/// below. Those contracts exist because the duplication they guard against was
/// re-introduced by copy-paste several times before the shared widgets landed.
List<File> _libSources() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

String _basename(File file) => file.uri.pathSegments.last;

class _IconButtonTooltipVisitor extends RecursiveAstVisitor<void> {
  _IconButtonTooltipVisitor({
    required this.file,
    required this.lineInfo,
    required this.offenders,
  });

  final File file;
  final LineInfo lineInfo;
  final List<String> offenders;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'IconButton') {
      final hasTooltip = node.argumentList.arguments.any(
        (argument) =>
            argument is NamedArgument && argument.name.lexeme == 'tooltip',
      );
      if (!hasTooltip) {
        final line = lineInfo.getLocation(node.offset).lineNumber;
        offenders.add('${file.path}:$line');
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

Widget _hostSliver(Widget sliver) {
  return ProviderScope(
    child: MaterialApp(
      theme: MaterialTestTheme.light(),
      home: Scaffold(body: CustomScrollView(slivers: [sliver])),
    ),
  );
}

void main() {
  _registerDesignSystem1();
  _registerDesignSystem2();
  _registerDesignSystem3();
}
