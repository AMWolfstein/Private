import 'package:flutter/material.dart';

/// The detail page a route shows, so a link to the page already on top keeps
/// it instead of stacking a copy.
///
/// This is route identity only: it depends on Flutter's navigator, never on the
/// screens it identifies, so screens can mark their own route without importing
/// the module that constructs other screens.
class DetailPage {
  DetailPage.album(String name, {required String artistName})
    : kind = 'album',
      id =
          '${name.trim().toLowerCase()}\u0000'
          '${artistName.trim().toLowerCase()}';

  final String kind;
  final String id;

  bool matches(DetailPage other) => kind == other.kind && id == other.id;

  static final _routes = Expando<DetailPage>('detail page');

  /// Records that the route around [context] shows [page].
  static void mark(BuildContext context, DetailPage page) {
    final route = ModalRoute.of(context);
    if (route != null) _routes[route] = page;
  }

  /// Whether [navigator]'s top route already shows this page.
  static bool isOnTop(NavigatorState navigator, DetailPage page) {
    Route<dynamic>? top;
    // Reads the top route without popping anything.
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final shown = top == null ? null : _routes[top!];
    return shown != null && shown.matches(page);
  }
}
