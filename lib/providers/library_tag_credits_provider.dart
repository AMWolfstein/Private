import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';

/// The tag credits table, shared so every screen reads one derived copy.
final libraryTagCreditsCacheProvider = Provider<LibraryTagCreditsCache>(
  (ref) => LibraryTagCreditsCache(),
);

/// The split rules, from the Tag separators settings.
final tagCreditRulesProvider = Provider<TagCreditRules>(
  (ref) => TagCreditRules.fromSettings(
    ref.watch(settingsProvider.select((s) => s.tagCredits)),
  ),
);
