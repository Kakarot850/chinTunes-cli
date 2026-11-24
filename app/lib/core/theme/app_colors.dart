import 'package:flutter/material.dart';

/// OLED-first surface hierarchy. Depth comes from surface steps + 1px
/// hairline borders, not shadows.
abstract final class AppColors {
  static const Color background = Color(0xFF09090B); // scaffold
  static const Color surface = Color(0xFF121216); // cards, tiles
  static const Color elevated = Color(0xFF1C1C22); // sheets, bars, inputs
  static const Color border = Color(0x14FFFFFF); // 8% white hairline

  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);

  /// Single accent (10% of the palette): active states, primary CTA.
  static const Color accent = Color(0xFF8B7CFF);
  static const Color onAccent = Color(0xFF0B0B10);
  static const Color danger = Color(0xFFF87171);

  /// Status only (downloaded badge, completed state); never decorative.
  static const Color success = Color(0xFF34D399);
}
