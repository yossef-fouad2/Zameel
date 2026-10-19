import 'dart:convert';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/app.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/routing/app_transition_page.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/widgets/profile_avatar.dart';
import 'package:zameel/src/shared/wrappers/state_wrapper.dart';
import 'package:zameel/src/theme/text_theme.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';
import 'package:zameel/src/ui/profile/account_page.dart';
import 'package:zameel/src/utils/failure.dart';
import 'support/auth_fakes.dart';
import 'support/profile_fakes.dart';

final _translations = <String, Map<String, dynamic>>{};
final _nameField = find.byKey(const ValueKey('profile.name'));
final _phoneField = find.byKey(const ValueKey('profile.phone'));

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

Future<FakeProfileRepository> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  AppUser? account,
  Failure? loadFailure,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  SharedPreferences.setMockInitialValues({});
  final user = account ??
      AppUser(
          id: student.id,
          email: student.email,
          name: student.name,
          role: student.role,
          preferredLanguage: locale.languageCode);
  final auth = FakeAuthRepository()..user = user;
  final profile = FakeProfileRepository(user)..loadFailure = loadFailure;
  addTearDown(auth.close);
  // Use the real app so localization, ScreenUtil, session restoration and
  // navigation are exercised together instead of rebuilding an incomplete shell.
  await tester.pumpWidget(EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ar')],
    path: 'assets/translations',
    assetLoader: const _Loader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    saveLocale: false,
    child: StateWrapper(
        repository: auth,
        profileRepository: profile,
        preferencesRepository: FakePreferencesRepository(),
        child: const App()),
  ));
  await tester.pumpAndSettle();
  if (find.byType(AccountPage).evaluate().isEmpty) {
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .pushNamed('account');
    await tester.pumpAndSettle();
  }
  return profile;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
        target, find.byType(ListView).first, const Offset(0, -200));
  }
  await Scrollable.ensureVisible(target.evaluate().single, alignment: .4);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
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

  for (final (size, locale, scale, dark) in [
    (const Size(320, 690), const Locale('en'), 1.0, false),
    (const Size(320, 690), const Locale('ar'), 2.0, true),
    (const Size(1024, 768), const Locale('en'), 1.0, true),
  ]) {
    testWidgets(
        'profile and photo sheet fit $size $locale at $scale, dark=$dark',
        (tester) async {
      await _pump(tester,
          locale: locale,
          size: size,
          scale: scale,
          brightness: dark ? Brightness.dark : Brightness.light);
      expect(find.byType(ProfileAvatar), findsOneWidget);
      await tester
          .tap(find.widgetWithText(TextButton, 'profile.change_photo'.tr()));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('profile.choose_photo'.tr()));
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('profile.photo_title'.tr()))).pop();
      await tester.pumpAndSettle();
      await _reveal(tester, _phoneField);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'editing details saves the whitelist and updates the live session',
      (tester) async {
    final profile = await _pump(tester);
    final session =
        tester.element(find.byType(AccountPage)).read<SessionBloc>();
    await _reveal(tester, _nameField);
    await tester.enterText(_nameField, '  Renamed Student  ');
    await _reveal(tester, _phoneField);
    await tester.enterText(_phoneField, '+20 1234567890');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(profile.reads, 1);
    expect(profile.saves, 1);
    expect(profile.submitted?.toUpdate(), {
      'full_name': 'Renamed Student',
      'phone': '+20 1234567890',
      'preferred_language': 'en',
    });
    expect(session.state.user?.name, 'Renamed Student');
    expect(session.state.user?.phone, '+20 1234567890');
    expect(find.text('Your details are up to date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid phone keeps Save disabled and explains the problem',
      (tester) async {
    final profile = await _pump(tester);
    await _reveal(tester, _phoneField);
    await tester.enterText(_phoneField, '12');
    await tester.pumpAndSettle();
    final save = tester
        .widget<AppButton>(find.widgetWithText(AppButton, 'Save changes'));
    expect(save.onPressed, isNull);
    expect(profile.saves, 0);
    expect(find.text('profile.phone_invalid'.tr()), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saved language updates the app and session without restarting',
      (tester) async {
    final profile = await _pump(tester);
    final languages = find.byType(SegmentedButton<String>);
    await _reveal(tester, languages);
    await tester
        .tap(find.descendant(of: languages, matching: find.text('Arabic')));
    await tester.pumpAndSettle();
    expect(profile.saves, 0);
    await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AccountPage));
    expect(context.read<SessionBloc>().state.user?.preferredLanguage, 'ar');
    expect(Directionality.of(context), ui.TextDirection.rtl);
    expect(find.text('حفظ التغييرات'), findsOneWidget);
    expect(profile.saves, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unsaved back navigation can be cancelled or discarded without a write',
      (tester) async {
    final profile = await _pump(tester);
    await _reveal(tester, _nameField);
    await tester.enterText(_nameField, 'Unsaved name');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('profile.discard_title'.tr()), findsOneWidget);
    await tester.tap(find.text('profile.keep_editing'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'profile.discard'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsNothing);
    expect(profile.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('load failure offers retry without a writable stale form',
      (tester) async {
    final profile = await _pump(tester,
        loadFailure: const NetworkFailure('profile.request_failed'));
    expect(find.byType(TextFormField), findsNothing);
    final retry = find.widgetWithText(AppButton, 'Try again');
    await _reveal(tester, retry);
    profile.loadFailure = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    await _reveal(tester, _phoneField);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(profile.reads, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'account role/email are readonly and a clean profile cannot be saved',
      (tester) async {
    await _pump(tester,
        account: const AppUser(
            id: 'landlord-1',
            email: 'owner@example.com',
            name: 'Owner',
            role: UserRole.landlord));
    expect(find.text('auth.role_landlord'.tr()), findsOneWidget);
    await _reveal(tester, find.text('owner@example.com'));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('profile.email_locked'.tr()), findsOneWidget);
    expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Save changes'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('profile transition respects reduced motion', (tester) async {
    Page<void>? page;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        page = appTransitionPage(
            context: context,
            key: const ValueKey('test'),
            child: const SizedBox());
        return const SizedBox();
      }),
    )));
    expect(page, isA<NoTransitionPage<void>>());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
