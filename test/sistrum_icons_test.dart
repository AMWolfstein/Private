import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/sistrum_icons.dart';

void main() {
  test('maps Material symbols to their Cupertino counterparts', () {
    expect(sistrumIconFor(Icons.favorite), CupertinoIcons.heart_fill);
    expect(sistrumIconFor(Icons.favorite_border), CupertinoIcons.heart);
    expect(sistrumIconFor(Icons.shuffle), CupertinoIcons.shuffle);
    expect(sistrumIconFor(Icons.delete_outline), CupertinoIcons.trash);
  });

  test('several Material variants share one Cupertino glyph', () {
    expect(sistrumIconFor(Icons.arrow_back), CupertinoIcons.back);
    expect(sistrumIconFor(Icons.chevron_left), CupertinoIcons.back);
    expect(sistrumIconFor(Icons.timer_outlined), CupertinoIcons.timer);
    expect(sistrumIconFor(Icons.timer_off_outlined), CupertinoIcons.timer);
  });

  test('a Cupertino icon is returned unchanged', () {
    expect(sistrumIconFor(CupertinoIcons.heart), same(CupertinoIcons.heart));
  });

  test('an unmapped Material icon is returned unchanged', () {
    expect(sistrumIconFor(Icons.ac_unit), same(Icons.ac_unit));
  });
}

Matcher same(Object expected) => predicate(
  (actual) => identical(actual, expected),
  'is the same instance as $expected',
);
