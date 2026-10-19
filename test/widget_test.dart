import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/app.dart';
import 'package:zameel/src/routing/app_routes.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/wrappers/state_wrapper.dart';
import 'package:zameel/src/theme/text_theme.dart';
import 'package:zameel/src/ui/auth/auth_code_page.dart';
import 'package:zameel/src/ui/auth/role_selection_page.dart';
import 'package:zameel/src/ui/auth/student_auth_page.dart';
import 'package:zameel/src/ui/auth/update_password_page.dart';
import 'package:zameel/src/ui/profile/account_page.dart';
import 'package:zameel/src/ui/student/onboarding_bridge_page.dart';
import 'package:zameel/src/ui/student/discovery_page.dart';
import 'package:zameel/src/utils/failure.dart';
import 'support/auth_fakes.dart';
import 'support/profile_fakes.dart';

final _translations = <String, Map<String, dynamic>>{};

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  FakeAuthRepository repository, {
  Locale locale = const Locale('en'),
  FakePreferencesRepository? preferences,
}) async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  await tester.pumpWidget(EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ar')],
    path: 'assets/translations',
    assetLoader: const _TestAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    saveLocale: false,
    child: StateWrapper(
        repository: repository,
        profileRepository:
            FakeProfileRepository(repository.user ?? repository.loginUser),
        preferencesRepository: preferences ?? FakePreferencesRepository(),
        child: const App()),
  ));
  await tester.pumpAndSettle();
  return GoRouter.of(tester.element(find.byType(Scaffold).first));
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(AppButton, label);
  if (button.evaluate().isEmpty) {
    // Long forms build lazily; drag the primary list until the target exists.
    final list = find.byType(ListView);
    final view =
        list.evaluate().isNotEmpty ? list.first : find.byType(Scrollable).first;
    await tester.dragUntilVisible(button, view, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  expect(button, findsWidgets, reason: 'Missing AppButton "$label"');
  // A pinned bottom action bar can cover a widget that is technically visible
  // at the viewport edge, so center it before tapping.
  await Scrollable.ensureVisible(button.evaluate().single, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final language in ['en', 'ar']) {
      _translations[language] = jsonDecode(
              await rootBundle.loadString('assets/translations/$language.json'))
          as Map<String, dynamic>;
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      if (![AppFonts.latin, AppFonts.arabic].contains(entry['family'])) {
        continue;
      }
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final (size, locale, scale, brightness) in [
    (const Size(320, 690), const Locale('en'), 1.0, Brightness.light),
    (const Size(390, 844), const Locale('ar'), 1.4, Brightness.light),
    (const Size(390, 844), const Locale('ar'), 1.4, Brightness.dark),
    (const Size(1024, 768), const Locale('en'), 1.0, Brightness.dark),
  ]) {
    testWidgets('auth pages lay out at $size $locale text=$scale $brightness',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final repository = FakeAuthRepository();
      addTearDown(repository.close);
      final router = await _pumpApp(tester, repository, locale: locale);
      expect(find.byType(RoleSelectionPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      router.go(AppRoutes.studentAuth);
      await tester.pumpAndSettle();
      expect(find.byType(StudentAuthPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      router.go(AppRoutes.signup);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('confirmation-required signup stays out of the private app',
      (tester) async {
    final repository = FakeAuthRepository();
    addTearDown(repository.close);
    final router = await _pumpApp(tester, repository);
    router.go(AppRoutes.signup);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Student');
    await tester.enterText(fields.at(1), 'student@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    await _tapButton(tester, 'Create Zameel Account');
    expect(find.byType(AuthCodePage), findsOneWidget);
    expect(find.byType(StudentOnboardingBridgePage), findsNothing);
    expect(repository.user, isNull);
    await tester.enterText(find.byType(TextFormField), '12345678');
    await _tapButton(tester, 'Verify code');
    expect(find.byType(StudentOnboardingBridgePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'sign-in accepts an existing shorter password and obeys the profile role',
      (tester) async {
    final repository = FakeAuthRepository()..loginUser = landlord;
    addTearDown(repository.close);
    final router = await _pumpApp(tester, repository);
    router.go(AppRoutes.studentAuth);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'landlord@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await _tapButton(tester, 'Sign In to Zameel');
    expect(repository.lastPassword, 'secret');
    expect(find.byType(AccountPage), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.landlord);
    router.go(AppRoutes.lifestyleQuiz);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.landlord);
    await _tapButton(tester, 'Sign out');
    expect(find.byType(RoleSelectionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'password recovery verifies code and updates password before leaving reset',
      (tester) async {
    final repository = FakeAuthRepository();
    addTearDown(repository.close);
    final router = await _pumpApp(tester, repository);
    router.go(AppRoutes.forgotPassword);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'student@example.com');
    await _tapButton(tester, 'Send reset code');
    expect(find.byType(AuthCodePage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '12345678');
    await _tapButton(tester, 'Verify code');
    expect(find.byType(UpdatePasswordPage), findsOneWidget);
    router.go(AppRoutes.discovery);
    await tester.pumpAndSettle();
    expect(find.byType(UpdatePasswordPage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'replacement123');
    await tester.enterText(find.byType(TextFormField).at(1), 'replacement123');
    await _tapButton(tester, 'Save new password');
    expect(repository.passwordUpdates, 1);
    expect(find.byType(StudentOnboardingBridgePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('anonymous deep links never mount protected quiz or discovery',
      (tester) async {
    final repository = FakeAuthRepository();
    addTearDown(repository.close);
    final router = await _pumpApp(tester, repository);
    for (final route in [
      AppRoutes.discovery,
      AppRoutes.lifestyleQuiz,
      AppRoutes.landlord
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.byType(RoleSelectionPage), findsOneWidget);
      expect(find.byType(StudentDiscoveryPage), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bridge skip persists and returning students bypass the bridge',
      (tester) async {
    final repository = FakeAuthRepository()..user = student;
    final preferences = FakePreferencesRepository();
    addTearDown(repository.close);
    await _pumpApp(tester, repository, preferences: preferences);
    expect(find.byType(StudentOnboardingBridgePage), findsOneWidget);
    final skip =
        find.widgetWithText(TextButton, 'student_onboarding.skip_browse'.tr());
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.byType(StudentDiscoveryPage), findsOneWidget);
    expect(preferences.values[student.id]?.isSkipped, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpApp(tester, repository, preferences: preferences);
    expect(find.byType(StudentDiscoveryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('logout failure stays on account and can be retried',
      (tester) async {
    final repository = FakeAuthRepository()
      ..user = landlord
      ..logoutFailure = const NetworkFailure('auth_flow.network_error');
    addTearDown(repository.close);
    await _pumpApp(tester, repository);
    await _tapButton(tester, 'Sign out');
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('auth_flow.network_error'.tr()), findsOneWidget);
    repository.logoutFailure = null;
    // Let the failure snackbar auto-dismiss so it no longer covers the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'Sign out');
    expect(find.byType(RoleSelectionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
