import 'package:flutter/material.dart';

/// Shared palette for the dark, phone-app-style theme used throughout the
/// game screen. Kept in one place so panels, headers, and controls read as
/// one consistent system rather than each picking their own shades.
class AppColors {
  AppColors._();

  static const background = Color(0xFF1B1A1E);
  static const panel = Color(0x59000000);
  static const panelBorder = Color(0x1FFFFFFF);
  static const accent = Color(0xFF4C8DE0);
  static const dashedSlot = Color(0x66FFFFFF);
  static const star = Color(0xFFFFD84A);
  static const success = Color(0xFF4CAF50);

  /// "This is happening right now" — the running highlight border on a
  /// function slot (see FunctionPanel) and the currently-active frame's
  /// instructions in the control bar's status line (see ControlBar) both
  /// use this, so the two read as the same signal.
  static const runningHighlight = Colors.amberAccent;

  /// Neutral (colorless) selection/drag-hover highlight — deliberately not
  /// blue, since [accent] is close enough to the blue tile-condition color
  /// that using it for "this is selected/hovered" reads as "this has a blue
  /// condition" instead.
  static const selectionFill = Color(0x59FFFFFF);
  static const selectionBorder = Colors.white;
}
