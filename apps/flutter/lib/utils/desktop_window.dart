import 'dart:math' as math;
import 'dart:ui';

/// Start with three feed columns beside the navigation rail. Keep the whole
/// window inside the monitor's logical work area, including on scaled displays.
Rect desktopStartupBounds(Rect workArea) {
  final scale = math.min(
      1.0,
      math.min(math.max(1.0, workArea.width - 32) / 1280,
          math.max(1.0, workArea.height - 32) / 720));
  return Rect.fromCenter(
      center: workArea.center, width: 1280 * scale, height: 720 * scale);
}
