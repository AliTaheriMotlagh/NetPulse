import 'package:flutter/material.dart';

import '../monitor.dart';

const _seed = Color(0xFF2A78D6);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
  );
}

/// Tabular figures stop live numbers from jittering as digits change.
const tabular = [FontFeature.tabularFigures()];

/// Chart roles. Download/upload are categorical slots 1-2 of the validated
/// reference palette, stepped separately for light and dark surfaces.
class Viz {
  const Viz._(this.down, this.up, this.grid, this.ink, this.surface);
  final Color down, up, grid, ink, surface;

  static Viz of(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = s.brightness == Brightness.dark;
    return Viz._(
      dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6),
      dark ? const Color(0xFFD95926) : const Color(0xFFEB6834),
      s.outlineVariant.withValues(alpha: .6),
      s.onSurfaceVariant,
      s.surfaceContainerLow,
    );
  }
}

/// Status colors are reserved for health and always ship with an icon + label.
extension HealthStyle on Health {
  IconData get icon => switch (this) {
    Health.excellent || Health.good => Icons.check_circle_rounded,
    Health.fair => Icons.error_outline_rounded,
    Health.poor => Icons.warning_amber_rounded,
    Health.offline => Icons.cloud_off_rounded,
    Health.pending => Icons.hourglass_top_rounded,
    Health.off => Icons.pause_circle_outline_rounded,
  };

  Color color(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      Health.excellent || Health.good => dark ? const Color(0xFF4CC38A) : const Color(0xFF1B873F),
      Health.fair => dark ? const Color(0xFFF5B841) : const Color(0xFFB7791F),
      Health.poor => dark ? const Color(0xFFFF8A4C) : const Color(0xFFD9480F),
      Health.offline => dark ? const Color(0xFFFF6B6B) : const Color(0xFFC92A2A),
      Health.pending || Health.off => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}
