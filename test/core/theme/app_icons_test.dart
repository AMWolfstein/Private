import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_icons.dart';

void main() {
  test('maps Material symbols to their Cupertino counterparts', () {
    expect(appIconFor(Icons.favorite), CupertinoIcons.heart_fill);
    expect(appIconFor(Icons.favorite_border), CupertinoIcons.heart);
    expect(appIconFor(Icons.shuffle), CupertinoIcons.shuffle);
    expect(appIconFor(Icons.delete_outline), CupertinoIcons.trash);
  });

  test('several Material variants share one Cupertino glyph', () {
    expect(appIconFor(Icons.arrow_back), CupertinoIcons.back);
    expect(appIconFor(Icons.chevron_left), CupertinoIcons.back);
    expect(appIconFor(Icons.timer_outlined), CupertinoIcons.timer);
    expect(appIconFor(Icons.timer_off_outlined), CupertinoIcons.timer);
  });

  test('a Cupertino icon is returned unchanged', () {
    expect(appIconFor(CupertinoIcons.heart), same(CupertinoIcons.heart));
  });

  test('an unmapped Material icon is returned unchanged', () {
    expect(appIconFor(Icons.ac_unit), same(Icons.ac_unit));
  });
}

Matcher same(Object expected) => predicate(
  (actual) => identical(actual, expected),
  'is the same instance as $expected',
);
