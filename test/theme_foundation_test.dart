import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zameel/src/shared/enums/button_enums.dart';
import 'package:zameel/src/shared/enums/semantic_status.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/widgets/status_badge.dart';
import 'package:zameel/src/theme/theme_constants.dart';

// Sizes and weights from the pinned google/fonts source in pubspec.yaml.
const _fonts = <String, Map<String, (int, int?)>>{
  AppFonts.latin: {
    'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf': (
      176288,
      null
    ),
  },
  AppFonts.arabic: {
    'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Regular.ttf': (
      235924,
      400
    ),
    'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Medium.ttf': (
      242100,
      500
    ),
    'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-SemiBold.ttf': (
      244616,
      600
    ),
    'assets/fonts/ibm_plex_sans_arabic/IBMPlexSansArabic-Bold.ttf': (
      246992,
      700
    ),
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the actual offline assets instead of the test runner's Ahem font.
    for (final family in _fonts.entries) {
      final loader = FontLoader(family.key);
      for (final asset in family.value.keys) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  test('font manifest, original TTFs, and OFL notices are bundled', () async {
    final manifest =
        (jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List<Object?>)
            .cast<Map<String, Object?>>();
    for (final family in _fonts.entries) {
      final faces = (manifest.singleWhere(
        (entry) => entry['family'] == family.key,
      )['fonts'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(faces, hasLength(family.value.length));
      for (final asset in family.value.entries) {
        final face = faces.singleWhere((entry) => entry['asset'] == asset.key);
        expect(face['weight'], asset.value.$2);
        final bytes = await rootBundle.load(asset.key);
        expect(bytes.lengthInBytes, asset.value.$1);
        expect(bytes.getUint32(0), 0x00010000);
        final weightTable = _tableOffset(bytes, 'OS/2')!;
        expect(bytes.getUint16(weightTable + 4), asset.value.$2 ?? 400);
        final variations = _tableOffset(bytes, 'fvar');
        if (asset.value.$2 == null) {
          expect(variations, isNotNull);
          final axis = variations! + bytes.getUint16(variations + 4);
          expect(bytes.getUint16(variations + 8), 1);
          expect(bytes.getUint32(axis), 0x77676874); // wght
          expect(bytes.getInt32(axis + 4) / 65536, 200);
          expect(bytes.getInt32(axis + 12) / 65536, 800);
        } else {
          expect(variations, isNull);
        }
      }
    }
    for (final directory in ['plus_jakarta_sans', 'ibm_plex_sans_arabic']) {
      final license =
          await rootBundle.loadString('assets/fonts/$directory/OFL.txt');
      expect(license, contains('Copyright'));
      expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    }
  });

  test('bundled variable font resolves distinct regular and bold weights', () {
    final widths = <double>[];
    for (final weight in [FontWeight.w400, FontWeight.w700]) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Kinship Student Living 12345',
          style: buildTextTheme().bodyLarge!.copyWith(fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      widths.add(painter.width);
      painter.dispose();
    }
    expect(widths.first, isNot(closeTo(widths.last, 0.01)));
  });

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('en'), const Locale('ar', 'SA')]) {
      test('$brightness $locale uses locale fonts throughout the theme', () {
        final theme = _theme(brightness, locale);
        for (final textTheme in [theme.textTheme, theme.primaryTextTheme]) {
          for (final style in _styles(textTheme)) {
            expect(style.fontFamily, AppFonts.familyFor(locale));
            expect(style.fontFamilyFallback, AppFonts.fallbacksFor(locale));
            if (locale.languageCode == 'ar') {
              expect(style.letterSpacing, 0);
              expect(style.height, greaterThanOrEqualTo(1.6));
              expect(style.fontWeight!.value, lessThanOrEqualTo(700));
            }
          }
        }
        expect(theme.textTheme.bodyMedium!.color, theme.colorScheme.onSurface);
        expect(theme.primaryTextTheme.bodyMedium!.color,
            theme.colorScheme.onPrimary);
        expect(theme.cupertinoOverrideTheme!.textTheme!.textStyle.fontFamily,
            AppFonts.familyFor(locale));
        expect(theme.inputDecorationTheme.hintStyle!.fontFamily,
            AppFonts.familyFor(locale));
      });
    }

    test('$brightness foreground pairs meet normal-text AA contrast', () {
      final theme = _theme(brightness, const Locale('en'));
      final cs = theme.colorScheme;
      final generic = theme.extension<AppColorsExtension>()!;
      final status = theme.extension<ZameelStatusColors>()!;
      final pairs = <String, (Color, Color)>{
        'primary': (cs.primary, cs.onPrimary),
        'primaryContainer': (cs.primaryContainer, cs.onPrimaryContainer),
        'secondary': (cs.secondary, cs.onSecondary),
        'secondaryContainer': (cs.secondaryContainer, cs.onSecondaryContainer),
        'tertiary': (cs.tertiary, cs.onTertiary),
        'tertiaryContainer': (cs.tertiaryContainer, cs.onTertiaryContainer),
        'error': (cs.error, cs.onError),
        'errorContainer': (cs.errorContainer, cs.onErrorContainer),
        'surface': (cs.surface, cs.onSurface),
        'surfaceVariant': (cs.surfaceContainerHighest, cs.onSurfaceVariant),
        'inverseSurface': (cs.inverseSurface, cs.onInverseSurface),
        'primaryFixed': (cs.primaryFixedDim, cs.onPrimaryFixedVariant),
        'secondaryFixed': (cs.secondaryFixedDim, cs.onSecondaryFixedVariant),
        'tertiaryFixed': (cs.tertiaryFixedDim, cs.onTertiaryFixedVariant),
        'success': (generic.success, generic.onSuccess),
        'successAsText': (cs.surface, generic.success),
        'successContainer': (
          generic.successContainer!,
          generic.onSuccessContainer!
        ),
        'warning': (generic.warning, generic.onWarning),
        'warningContainer': (
          generic.warningContainer!,
          generic.onWarningContainer!
        ),
        'info': (generic.info, generic.onInfo),
        'infoContainer': (generic.infoContainer!, generic.onInfoContainer!),
        'available': (status.availableFill, status.availableText),
        'almostFull': (status.almostFullFill, status.almostFullText),
        'fullyOccupied': (status.fullyOccupiedFill, status.fullyOccupiedText),
        'pending': (status.bookingPendingFill, status.bookingPendingText),
        'accepted': (status.bookingAcceptedFill, status.bookingAcceptedText),
        'rejected': (status.bookingRejectedFill, status.bookingRejectedText),
        'noData': (status.noDataFill, status.noDataText),
      };
      for (final pair in pairs.entries) {
        final first = pair.value.$1.computeLuminance();
        final second = pair.value.$2.computeLuminance();
        final contrast =
            (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: pair.key);
      }
    });
  }

  test('semantic radius aliases and component themes share one value', () {
    expect(AppBorders.button, AppBorders.buttonRadius);
    expect(AppBorders.input, AppBorders.inputRadius);
    expect(AppBorders.card, AppBorders.cardRadius);
    expect(AppBorders.dialog, AppBorders.dialogRadius);
    expect(AppBorders.bottomSheet, AppBorders.bottomSheetRadius);
    final theme = buildLightTheme();
    expect((theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        AppBorders.dialogRadius);
    expect(
        (theme.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius,
        AppBorders.bottomSheetRadius);
    expect((theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        AppBorders.cardRadius);
    expect(
        (theme.inputDecorationTheme.border! as OutlineInputBorder).borderRadius,
        AppBorders.inputRadius);
    expect(
        (theme.textButtonTheme.style!.shape!.resolve({})!
                as RoundedRectangleBorder)
            .borderRadius,
        AppBorders.buttonRadius);
  });

  testWidgets('custom button fill never overrides its label or icon foreground',
      (tester) async {
    const fill = Color(0xFF904D00);
    const foreground = Color(0xFFFFDCC3);
    await tester.pumpWidget(_host(AppButton(
      label: 'Continue',
      color: fill,
      onPressed: () {},
      prefixIcon: const Icon(Icons.check),
    )));
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.style!.backgroundColor!.resolve({}), fill);
    expect(button.style!.foregroundColor!.resolve({}),
        buildLightTheme().colorScheme.onPrimary);
    expect(
        DefaultTextStyle.of(tester.element(find.text('Continue'))).style.color,
        buildLightTheme().colorScheme.onPrimary);
    expect(IconTheme.of(tester.element(find.byIcon(Icons.check))).color,
        buildLightTheme().colorScheme.onPrimary);

    await tester.pumpWidget(_host(AppButton(
      label: 'Continue',
      color: fill,
      textColor: foreground,
      isLoading: true,
      onPressed: () {},
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .color,
        foreground);
  });

  testWidgets('compact controls can shrink-wrap in an unconstrained row',
      (tester) async {
    await tester.pumpWidget(_host(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(label: 'Save', onPressed: () {}),
        const SizedBox(width: 8),
        const StatusBadge(
          status: SemanticStatus.available,
          label: 'Available',
          showIcon: false,
        ),
      ],
    )));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48));
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('$locale controls wrap safely at ${scale}x on narrow screens',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final label = locale.languageCode == 'ar'
            ? '\u0645\u064f\u062a\u0627\u0628\u064e\u0639\u0629 \u0648\u0625\u0646\u0634\u0627\u0621 '
                '\u062d\u0633\u0627\u0628\u064a \u0641\u064a \u0627\u0644\u0633\u0643\u0646 \u0627\u0644\u062c\u0627\u0645\u0639\u064a 2026'
            : 'Continue and create my university housing account for 2026';
        for (final brightness in Brightness.values) {
          for (final size in ButtonSize.values) {
            await tester.pumpWidget(_host(
              SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      label: label,
                      height: size,
                      isFullWidth: true,
                      prefixIcon: const Icon(Icons.check),
                      suffixIcon: const Icon(Icons.arrow_forward),
                      onPressed: () {},
                    ),
                    const SizedBox(height: 16),
                    StatusBadge(
                        status: SemanticStatus.bookingPending, label: label),
                  ],
                ),
              ),
              locale: locale,
              brightness: brightness,
              scale: scale,
            ));
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byType(TextButton)).height,
                greaterThanOrEqualTo(48));
            expect(tester.getSize(find.byType(StatusBadge)).height,
                greaterThanOrEqualTo(24));
            for (final parent in [
              find.byType(TextButton),
              find.byType(StatusBadge)
            ]) {
              final text =
                  find.descendant(of: parent, matching: find.text(label));
              final paragraph = tester.renderObject<RenderParagraph>(text);
              expect(paragraph.didExceedMaxLines, isFalse);
              final outer = tester.getRect(parent);
              final inner = tester.getRect(text);
              expect(inner.top, greaterThanOrEqualTo(outer.top));
              expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
              expect(inner.width, lessThanOrEqualTo(outer.width));
            }
          }
        }
      });
    }
  }
}

int? _tableOffset(ByteData data, String tag) {
  for (var index = 0; index < data.getUint16(4); index++) {
    final offset = 12 + index * 16;
    final name = String.fromCharCodes(
      List.generate(4, (character) => data.getUint8(offset + character)),
    );
    if (name == tag) return data.getUint32(offset + 8);
  }
  return null;
}

List<TextStyle> _styles(TextTheme theme) => [
      theme.displayLarge!,
      theme.displayMedium!,
      theme.displaySmall!,
      theme.headlineLarge!,
      theme.headlineMedium!,
      theme.headlineSmall!,
      theme.titleLarge!,
      theme.titleMedium!,
      theme.titleSmall!,
      theme.bodyLarge!,
      theme.bodyMedium!,
      theme.bodySmall!,
      theme.labelLarge!,
      theme.labelMedium!,
      theme.labelSmall!,
    ];

ThemeData _theme(Brightness brightness, Locale locale) =>
    brightness == Brightness.dark
        ? buildDarkTheme(locale: locale)
        : buildLightTheme(locale: locale);

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) {
  return ScreenUtilInit(
    designSize: const Size(360, 690),
    builder: (context, _) => MaterialApp(
      theme: _theme(brightness, locale),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Scaffold(
              body: SingleChildScrollView(child: Center(child: child)),
            ),
          ),
        ),
      ),
    ),
  );
}
