import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Named spacing constants aligned with an 8-pt grid.
///
/// Usage:
/// ```dart
/// SizedBox(height: AppSpacing.md)        // 16 pt gap
/// Padding(padding: EdgeInsets.all(AppSpacing.lg))
/// ```
abstract final class AppSpacing {
  AppSpacing._();

  static const double _xxs = 2;
  static const double _xs = 4;
  static const double _sm = 8;
  static const double _ms = 12;
  static const double _md = 16;
  static const double _ml = 20;
  static const double _lg = 24;
  static const double _xl = 32;
  static const double _xxl = 48;
  static const double _xxxl = 64;

  /// 2 pt — hairline gap, icon-to-label spacing.
  static double get xxs => _xxs.r;

  /// 4 pt — tightest spacing, between tightly coupled elements.
  static double get xs => _xs.r;

  /// 8 pt — small spacing, inside compact components (chip padding, icon gap).
  static double get sm => _sm.r;

  /// 12 pt — medium-small, inner card padding on dense layouts.
  static double get ms => _ms.r;

  /// 16 pt — base unit, standard component padding and list item gaps.
  static double get md => _md.r;

  /// 20 pt — medium-large, comfortable section spacing.
  static double get ml => _ml.r;

  /// 24 pt — large, between content sections on a page.
  static double get lg => _lg.r;

  /// 32 pt — extra large, major section breaks or hero padding.
  static double get xl => _xl.r;

  /// 48 pt — 2× large, top-of-page safe area offsets, empty state padding.
  static double get xxl => _xxl.r;

  /// 64 pt — maximum, full-bleed header heights.
  static double get xxxl => _xxxl.r;

  // ── Static 8-pt grid (non-scaling; used by theme builders) ───────────────
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;
  static const double space56 = 56;
  static const double space64 = 64;

  /// Standard screen horizontal gutter (16 pt each side).
  static const EdgeInsets pageGutter =
      EdgeInsets.symmetric(horizontal: space16);

  /// Inner padding for cards (16 pt all sides).
  static const EdgeInsets cardInsets = EdgeInsets.all(space16);

  /// Compact card padding (12 pt all sides).
  static const EdgeInsets cardPaddingCompact = EdgeInsets.all(space12);

  /// Dialog content padding (24 pt all sides).
  static const EdgeInsets dialogPadding = EdgeInsets.all(space24);

  /// Bottom-sheet content padding.
  static const EdgeInsets bottomSheetPadding =
      EdgeInsets.fromLTRB(space20, space12, space20, space32);

  /// Input field content padding.
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: space16, vertical: space12);

  // ── Semantic aliases ──────────────────────────────────────────────────────

  /// Standard horizontal page margin.
  static double get pagePadding => md;

  /// Gap between list/grid items.
  static double get itemGap => sm;

  /// Inner padding for cards.
  static double get cardPadding => md;

  /// Vertical gap between form fields.
  static double get formFieldGap => ms;
}

