import 'dart:ui_web' as ui_web;

/// Traverse Flutter's configured URL strategy, preserving its history state.
Future<bool> goBrowserHistory(int delta) async {
  final strategy = ui_web.urlStrategy;
  if (strategy == null || delta == 0) return false;
  await strategy.go(delta);
  return true;
}
