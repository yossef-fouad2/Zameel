import 'package:flutter/material.dart';

/// Reusable border radii and border shapes used across the app.
///
/// Usage:
/// ```dart
/// Container(decoration: BoxDecoration(borderRadius: AppBorders.md))
/// ```
abstract final class AppBorders {
  AppBorders._();

  // ── Border Radii ──────────────────────────────────────────────────────────

  /// 4 pt - subtle rounding for small decorative elements.
  static const BorderRadius xs = BorderRadius.all(Radius.circular(4));

  /// 8 pt — standard rounding for buttons, text fields.
  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));

  /// 12 pt — medium rounding for cards, list tiles.
  static const BorderRadius md = BorderRadius.all(Radius.circular(12));

  /// 16 pt - large rounding for panels and modals.
  static const BorderRadius lg = BorderRadius.all(Radius.circular(16));

  /// 24 pt - extra large rounding for feature containers.
  static const BorderRadius xl = BorderRadius.all(Radius.circular(24));

  /// Fully circular (pill/stadium shape).
  static const BorderRadius full = BorderRadius.all(Radius.circular(999));

  // ── Zameel marketplace radii (numeric tokens) ─────────────────────────────
  static const double radius4 = 4;
  static const double radius6 = 6;
  static const double radius8 = 8;
  static const double radius12 = 12;
  static const double radius16 = 16;
  static const double radius20 = 20;
  static const double radiusPill = 999;

  /// Default card radius (12 pt) — listing cards, grouped containers.
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(radius12));

  /// Default input radius (8 pt) — solid architectural anchor.
  static const BorderRadius inputRadius =
      BorderRadius.all(Radius.circular(radius8));

  /// Default button radius (8 pt) — consistent with inputs.
  static const BorderRadius buttonRadius =
      BorderRadius.all(Radius.circular(radius8));

  /// Status badge radius (6 pt).
  static const BorderRadius badgeRadius =
      BorderRadius.all(Radius.circular(radius6));

  /// Dialog radius (16 pt).
  static const BorderRadius dialogRadius =
      BorderRadius.all(Radius.circular(radius16));

  /// Bottom-sheet top radius (20 pt).
  static const BorderRadius bottomSheetRadius =
      BorderRadius.vertical(top: Radius.circular(radius20));

  /// Standard hairline border width.
  static const double borderWidthHairline = 1;

  /// Focused / active border width.
  static const double borderWidthActive = 1.5;

  // ── Semantic aliases ──────────────────────────────────────────────────────

  /// Default button border radius.
  static const BorderRadius button = buttonRadius;

  /// Default card border radius.
  static const BorderRadius card = cardRadius;

  /// Default input field border radius.
  static const BorderRadius input = inputRadius;

  /// Default dialog border radius.
  static const BorderRadius dialog = dialogRadius;

  /// Default bottom-sheet top radius.
  static const BorderRadius bottomSheet = bottomSheetRadius;

  // ── RoundedRectangleBorder shapes (for ShapeBorder APIs) ─────────────────

  /// Small rounded rectangle shape (8 pt).
  static const RoundedRectangleBorder shapeSm = RoundedRectangleBorder(
    borderRadius: sm,
  );

  /// Medium rounded rectangle shape (12 pt).
  static const RoundedRectangleBorder shapeMd = RoundedRectangleBorder(
    borderRadius: md,
  );

  /// Large rounded rectangle shape (16 pt).
  static const RoundedRectangleBorder shapeLg = RoundedRectangleBorder(
    borderRadius: lg,
  );

  /// Fully circular/stadium shape.
  static const StadiumBorder stadium = StadiumBorder();
}
