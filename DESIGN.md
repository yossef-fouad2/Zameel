# Zameel Design System

## Source And Scope

The current app follows the slate/amber/mint **Kinship Student Living** export under `stitch_student_housing_marketplace_app/stitch_student_housing_marketplace_app (1)/stitch_student_housing_marketplace_app`. Its `code.html` files and design guide provide the visual reference. The separate navy handoff palette is not active. Product branding in the app is Zameel.

Preserve the visual hierarchy, but never copy fabricated listing inventory, verification claims, match counts, or compatibility scores from mockups. Unimplemented providers/features should be hidden or explicitly unavailable, not successful-looking buttons. Decorative previews must be labeled as illustrations, not live results. Screens use icon illustrations rather than claiming to reproduce the export's photography pixel for pixel.

## Theme And Colors

Use `package:zameel/src/imports/imports.dart`, or the existing `core_imports.dart` / `packages_imports.dart` pair. The theme is initialized once in `App`:

```dart
theme: buildLightTheme(locale: context.locale),
darkTheme: buildDarkTheme(locale: context.locale),
themeMode: ThemeMode.system,
```

`ZameelColorSchemes` contains fixed Material 3 palettes in `lib/src/theme/color_schemes.dart`. Do not pass a seed color or build a new `ThemeData` per page.

| Access | Purpose |
|---|---|
| `context.colors` | Standard Material roles; light primary `#091426`, primary container `#1E293B`, amber secondary container `#FE932C`, deep-green tertiary container `#00301F` |
| `context.textTheme` / `context.typography` | Typography roles |
| `context.appColors` | Generic success/warning/info and their container/foreground pairs |
| `context.statusColors` | Availability, booking and no-data fill/text/border triples |
| `context.designTokens` | Small fallback padding/radius/elevation extension |

Pair foregrounds with the actual background: `onPrimaryContainer` on `primaryContainer`, `onSurface` on surfaces, and semantic text on its semantic fill. Do not use `onPrimary` for a primary-container panel, especially in dark mode. Light success text was darkened to `#087443` to retain contrast on pale surfaces. Dark colors are an app-defined counterpart because the reference screens specify light values only.

## Typography

- English: bundled **Plus Jakarta Sans**, variable weights 200-800.
- Arabic: bundled **IBM Plex Sans Arabic**, weights 400/500/600/700, with increased line height and zero letter spacing.
- Each family falls back to the other for mixed-language content. `AppFonts` and `buildTextTheme(locale: ...)` live in `text_theme.dart`.
- `displayLarge` / `displayMedium` provide 36/28 hero sizes; headline roles use 30/24/20; body roles use 16/14/12. Use the closest role, then only necessary `copyWith` adjustments.
- Fonts and OFL notices are in `assets/fonts/`, sourced from the pinned official Google Fonts commit documented in `pubspec.yaml`. No network font package is used.
- Text already uses logical sizes and the platform text scaler. Do not apply `.sp` again to an existing themed `fontSize` or scale away the user's accessibility setting.

## Responsive Layout

`ScreenUtilWrapper` is initialized once above the Material app. Its implemented baseline is **360 x 690**, not the old scaffold documentation's 390 x 844.

| Token | Correct use |
|---|---|
| `AppSpacing.xxs` through `xxxl` | Responsive getters; already `.r` scaled. Use bare values. |
| `AppSpacing.pagePadding`, `cardPadding`, `itemGap`, `formFieldGap` | Responsive double aliases. |
| `AppSpacing.space2` through `space64` | Unscaled logical constants, useful for theme definitions. |
| `pageGutter`, `cardInsets`, `inputPadding`, `dialogPadding`, `bottomSheetPadding` | Unscaled `EdgeInsets` presets for theme/layout use. |
| `.w`, `.h`, `.r`, `.sp` on raw numbers | Only when a raw dimension really needs ScreenUtil scaling. |

Never use `AppSpacing.md.w` or `AppSpacing.lg.h`: those scale twice. Avoid fixed content heights where translated/scaled text must grow. Use bounded preview geometry, scrollable forms, `Flexible`/`Expanded` for bounded rows, `Wrap` for multiple labels, and `EdgeInsetsDirectional`/`PositionedDirectional` for RTL. A `Stack` containing only positioned children requires finite height and width. Use a max-width constraint for centered forms on wide screens, not an additional ScreenUtil initialization.

## Shape And Motion

| Class | Purpose |
|---|---|
| `AppBorders` | Semantic radii: button/input 8, card 12, badge 6, dialog 16, bottom-sheet top 20; semantic aliases and `*Radius` members agree. |
| `AppShadows` | Shared subtle/card/elevated/modal and floating/dialog effects; prefer tonal elevation where possible. |
| `AppDurations` | Shared interaction/transition timing. |
| `AppCurves` | Shared animation easing. |

Do not invent new global radius or spacing names for one screen. Keep component-specific numeric geometry local when it has no reusable semantic meaning.

## Reusable Components

- `AppButton`: theme typography, independent background/foreground overrides, wrapping label, minimum touch height instead of clipped fixed text height.
- `AppCard`, `AppTextField`: use the global card/input theme; cards use the lowest surface and fields use a low surface for tonal separation.
- `AppTopBar`: accessible directional Back only when the router can pop or a custom action exists. Root screens must not navigate to another role's home on Back.
- `StatusBadge`: use a truthful domain state, localized label, icon and semantic colors together. It expands for longer/scaled text.
- `KinshipBrandMark`, `KinshipPill`: reuse the design's branding treatment/chips without hardcoded unlocalized campus text or fake verification badges.
- `AuthFeedback`: UI listener for auth failures/success feedback. Blocs do not receive `BuildContext`, show toasts, or navigate.

## New Page Pattern

```dart
import 'package:zameel/src/imports/imports.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(title: 'feature.title'.tr()),
    body: SafeArea(
      child: ListView(
        padding: EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          AppCard(child: Text('feature.body'.tr(),
            style: context.textTheme.bodyMedium)),
        ],
      ),
    ),
  );
}
```

The `feature.*` keys above are examples, not existing translations. Register real routes only in `app_router.dart`, add keys to both JSON locales, and keep backend calls in services/repositories. Router redirects enforce session/role access; database RLS is the security boundary.

## Validation

Run `flutter analyze` and `flutter test` after changes. Theme tests load the bundled font assets and check contrast, font weights, tokens, both themes, and English/Arabic scaling. Auth/onboarding widget tests exercise actual routes and constrained layouts. Device smoke tests and final comparison with the design remain necessary before claiming production visual parity.
