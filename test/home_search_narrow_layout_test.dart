import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/screens/home_tab.dart';

import 'support/search_results_fixture.dart';

/// What the Search tab paints, as text: every painting box with its global
/// rect and paint attributes, in paint order. Layout-only wrappers are left
/// out, so moving code between widgets keeps the fingerprint while any
/// change to the pixels changes it.
String _paintFingerprint(WidgetTester tester) {
  final lines = <String>[];
  String rect(RenderBox box) {
    final r = box.localToGlobal(Offset.zero) & box.size;
    return '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} '
        '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}';
  }

  void visit(RenderObject object) {
    if (object is RenderBox && object.hasSize) {
      final description = switch (object) {
        RenderParagraph() =>
          'text ${object.text.toStringDeep(minLevel: DiagnosticLevel.info)}',
        RenderDecoratedBox() => 'box ${object.decoration}',
        RenderPhysicalShape() =>
          'shape ${object.color} ${object.elevation} ${object.clipper}',
        RenderPhysicalModel() =>
          'model ${object.color} ${object.elevation} ${object.borderRadius}',
        RenderClipRRect() => 'clip ${object.borderRadius}',
        RenderClipPath() => 'path ${object.clipper}',
        RenderClipOval() => 'oval',
        RenderImage() => 'image',
        RenderOpacity() => 'opacity ${object.opacity}',
        RenderCustomPaint() =>
          'paint ${object.painter?.runtimeType} '
              '${object.foregroundPainter?.runtimeType}',
        _ => null,
      };
      if (description != null) lines.add('${rect(object)} $description');
    }
    object.visitChildren(visit);
  }

  visit(tester.renderObject(find.byType(HomeTab)));
  return lines.join('\n');
}

/// SHA-1 of each fingerprint, recorded on the base layout (commit 44cbb57b)
/// before search results gained cover grids and shelves on wide screens, and
/// re-recorded when blue became the default accent, when the filter chips
/// gained their glass press layer, when Glass became fixed at Clear, and when
/// the glass rim painter was renamed (the fingerprint includes painter class
/// names; the painted pixels did not change). A narrow layout must paint
/// exactly these.
/// A deliberate change to
/// the phone rows records new values; the failure prints the fingerprint.
const _baseFingerprints = {
  'phone': '04f6e198f1bfab62707f15e38e5fdd28fc0a4c6e',
  'landscape phone': '6a18a9afcec7f8f4cb58f54a81ed344ba0137d51',
  'portrait tablet': '23708c51cffa085a8a0a1248e552ceac7ef718e8',
  'narrow tablet window': '22a9b32e5c4574ad57bfe681332310be029910a8',
};

void main() {
  for (final (name, size) in [
    ('phone', const Size(430, 1400)),
    ('landscape phone', const Size(932, 430)),
    ('portrait tablet', const Size(800, 1280)),
    ('narrow tablet window', const Size(820, 1400)),
  ]) {
    final key = name;
    testWidgets('Search results on a $key paint the base layout', (
      tester,
    ) async {
      await pumpSearchFixture(tester, size: size);
      expect(find.text('Found artist 0'), findsOneWidget);
      expect(find.byType(SliverGrid), findsNothing);

      final fingerprint = _paintFingerprint(tester);
      final hash = sha1.convert(utf8.encode(fingerprint)).toString();
      final expected = _baseFingerprints[key];
      if (hash != expected) debugPrint('$key: $hash\n$fingerprint');
      expect(hash, expected);
      expect(tester.takeException(), isNull);
    });
  }
}
