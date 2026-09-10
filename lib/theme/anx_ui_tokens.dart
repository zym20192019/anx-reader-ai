import 'package:flutter/material.dart';

/// Shared visual values for the Anx Reader AI presentation layer.
///
/// This class intentionally contains no app state or behavior. Widgets should
/// use these values to keep surfaces, spacing, and interaction states coherent
/// while leaving their existing callbacks and data flow untouched.
class AnxUiTokens {
  AnxUiTokens._();

  static const double surfaceRadius = 18;
  static const double controlRadius = 12;
  static const double pillRadius = 999;

  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets compactControlPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  static const EdgeInsets settingTilePadding = EdgeInsetsDirectional.only(
    start: 12,
    end: 12,
    top: 12,
    bottom: 12,
  );

  static Color raisedSurface(ColorScheme scheme) => scheme.surfaceContainerLow;

  static Color subtleSurface(ColorScheme scheme) => scheme.surfaceContainer;

  static Color quietBorder(ColorScheme scheme) =>
      scheme.outlineVariant.withValues(alpha: 0.62);

  static Color quietText(ColorScheme scheme) => scheme.onSurfaceVariant;

  static Color hoverSurface(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.08);

  static Color pressedSurface(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.14);
}
