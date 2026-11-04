import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). Decorative motion such as the
/// album artwork drift stays off there.
final lowEndDeviceProvider = Provider<bool>((ref) => false);
