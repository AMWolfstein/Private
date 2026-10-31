import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass_render.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/glass/chrome/app_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/widgets/player/artwork/app_player_ground.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';

part 'app_artwork_glass_shaders.dart';
part 'app_artwork_glass_grounds.dart';

final _cover = File('test/fixtures/covers/qamar.png').absolute.path;
final _otherCover = File('test/fixtures/covers/saturated.png').absolute.path;

Widget _app({
  required Widget child,
  AppGlassLevel level = AppGlassLevel.liquid,
  int clarity = 3,
  bool shaders = true,
  bool highContrast = false,
}) => ProviderScope(
  overrides: [
    appGlassLevelProvider.overrideWithValue(level),
    appGlassClarityLevelProvider.overrideWithValue(clarity),
    appShaderFiltersSupportedProvider.overrideWithValue(shaders),
  ],
  child: MaterialApp(
    theme: AppTheme.build(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(highContrast: highContrast),
      child: child!,
    ),
    home: child,
  ),
);

/// Lets real decoding and rasterizing finish, then pumps.
///
/// The budget is real time, not frames: a decoded cover under the parallel load
/// of the full suite regularly needs more than the 800 ms covered by 40 rounds,
/// which made these tests fail with "ground never became ready" while passing
/// alone. Keep the wait generous so the tests assert the material, not timing.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'ground never became ready');
}

/// A stand-in player: its ground, and a menu button inside it.
class _Player extends StatelessWidget {
  const _Player({required this.source, this.insetKey});

  final String? source;
  final GlobalKey? insetKey;

  @override
  Widget build(BuildContext context) => AppPlayerGround(
    source: source,
    immersive: false,
    showArtwork: true,
    artworkAspectRatio: null,
    fadeStart: .58,
    insetArtworkKey: insetKey ?? GlobalKey(),
    child: Stack(
      children: [
        Positioned(
          left: 40,
          top: 80,
          width: 300,
          height: 300,
          child: SizedBox.expand(key: insetKey),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppContextMenu<void>(
                context: context,
                builder: (_) => const AppContextMenu(
                  groups: [
                    [
                      AppMenuAction(
                        icon: Icons.star,
                        label: 'Favorite',
                        onPressed: null,
                      ),
                    ],
                  ],
                ),
              ),
              child: const Text('More'),
            ),
          ),
        ),
      ],
    ),
  );
}

AppGroundController _playerGround(WidgetTester tester) => tester
    .state<State<AppPlayerGround>>(find.byType(AppPlayerGround))
    .let((state) => (state as dynamic).controller as AppGroundController);

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void main() {
  _registerAppArtworkGlassShaders();
  _registerAppArtworkGlassGrounds();
}
