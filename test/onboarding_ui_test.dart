import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/routing/app_routes.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/widgets/app_top_bar.dart';
import 'package:zameel/src/shared/widgets/kinship_widgets.dart';
import 'package:zameel/src/theme/theme_constants.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';
import 'package:zameel/src/ui/auth/role_selection_page.dart';
import 'package:zameel/src/ui/student/discovery_page.dart';
import 'package:zameel/src/ui/student/lifestyle_quiz/lifestyle_quiz_bloc.dart';
import 'package:zameel/src/ui/student/lifestyle_quiz/lifestyle_quiz_page.dart';
import 'package:zameel/src/ui/student/onboarding_bridge_page.dart';
import 'package:zameel/src/utils/failure.dart';
import 'package:zameel/src/utils/typedefs.dart';

final _translations = <String, Map<String, dynamic>>{};
const _student = AppUser(
  id: 'student-1',
  email: 'student@example.test',
  role: UserRole.student,
);
const _answers = LifestylePreferences(
  sleepSchedule: SleepSchedule.earlyBird,
  studyAtmosphere: StudyAtmosphere.librarySilence,
  dishPolicy: DishPolicy.immediate,
  guestPreference: GuestPreference.none,
  roomSharingPreference: RoomSharingPreference.privateRoom,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    for (final language in ['en', 'ar']) {
      _translations[language] = jsonDecode(
        await rootBundle.loadString('assets/translations/$language.json'),
      ) as Map<String, dynamic>;
    }
    // Measure the bundled fonts rather than the test runner's Ahem fallback.
    final manifest =
        (jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List<Object?>)
            .cast<Map<String, dynamic>>();
    for (final family in [AppFonts.latin, AppFonts.arabic]) {
      final entry = manifest.singleWhere((item) => item['family'] == family);
      final loader = FontLoader(family);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('top bar is safe at a standalone MaterialApp root',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(appBar: AppTopBar(title: 'Standalone')),
    ));
    expect(find.byType(BackButton), findsNothing);
    expect(tester.takeException(), isNull);

    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppTopBar(
          title: 'Custom back',
          onPressed: () => pressed = true,
        ),
      ),
    ));
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    expect(pressed, isTrue);
  });

  testWidgets('top bar uses the RTL BackButton for a real Navigator pop',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const Scaffold(appBar: AppTopBar(title: 'Root')),
    ));
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(appBar: AppTopBar(title: 'Detail')),
    )));
    await tester.pumpAndSettle();
    final back = find.byType(BackButton);
    expect(back, findsOneWidget);
    expect(Directionality.of(tester.element(back)), TextDirection.rtl);
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ar']) {
    for (final dark in [false, true]) {
      testWidgets(
          'onboarding layouts wrap at 320px / 3x in $language, dark=$dark',
          (tester) async {
        final locale = Locale(language);
        final session = _RecordingSessionBloc();
        addTearDown(session.close);
        await _pumpSurface(
          tester,
          home: const RoleSelectionPage(),
          locale: locale,
          dark: dark,
          textScale: 3,
        );
        expect(find.text('role_selection.hero_badge'.tr()), findsOneWidget);
        expect(find.text('role_selection.campus'.tr()), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _pumpSurface(
          tester,
          home: const StudentOnboardingBridgePage(),
          session: session,
          locale: locale,
          dark: dark,
          textScale: 3,
        );
        expect(find.text('student_onboarding.preview_notice'.tr()),
            findsOneWidget);
        expect(find.textContaining('96%'), findsNothing);
        expect(find.textContaining('1,400'), findsNothing);
        expect(tester.takeException(), isNull);

        await _pumpSurface(
          tester,
          home: LifestyleQuizPage(
            userId: _student.id,
            repository: _PreferencesRepository(),
          ),
          locale: locale,
          dark: dark,
          textScale: 3,
        );
        expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            0);
        await tester.scrollUntilVisible(
          find.text('student_quiz.skip'.tr()),
          500,
          maxScrolls: 100,
        );
        expect(tester.takeException(), isNull);

        await _pumpSurface(
          tester,
          home: const StudentDiscoveryPage(),
          locale: locale,
          dark: dark,
          textScale: 3,
        );
        for (final tab in ['requests', 'saved', 'match_quiz']) {
          await tester.tap(find.text('student_discovery.$tab'.tr()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('landlord selection uses named auth entry; sign-in omits role',
      (tester) async {
    final router = _router(AppRoutes.roleSelection);
    addTearDown(router.dispose);
    await _pumpSurface(tester, router: router);
    final landlord = find.text('role_selection.manager_title'.tr());
    await tester.ensureVisible(landlord);
    await tester.tap(landlord);
    await tester.pumpAndSettle();
    final continueButton = find.text('role_selection.continue_manager'.tr());
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('auth:landlord'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    final signIn = find.text('role_selection.sign_in'.tr());
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(find.text('auth:none'), findsOneWidget);
  });

  testWidgets('bridge skip dispatches once and waits for the session redirect',
      (tester) async {
    final session = _RecordingSessionBloc(markSkipBusy: true);
    final router = _router(AppRoutes.studentOnboarding);
    addTearDown(session.close);
    addTearDown(router.dispose);
    await _pumpSurface(tester, router: router, session: session);
    await tester.tap(find.text('student_onboarding.skip'.tr()));
    await tester.pumpAndSettle();

    expect(session.events.whereType<SessionOnboardingSkipRequested>(),
        hasLength(1));
    expect(find.byType(StudentOnboardingBridgePage), findsOneWidget);
    expect(find.byType(StudentDiscoveryPage), findsNothing);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
    for (final key in ['skip', 'skip_browse']) {
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(
                TextButton,
                'student_onboarding.$key'.tr(),
              ))
              .onPressed,
          isNull);
    }
    expect(
        tester
            .widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.account_circle_outlined),
            )
            .onPressed,
        isNull);

    session.failSkip();
    await tester.pumpAndSettle();
    expect(find.text('student_onboarding.skip_error'.tr()), findsOneWidget);
    expect(
        tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
    await tester.tap(find.byTooltip('student_onboarding.profile'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('Account destination'), findsOneWidget);
  });

  testWidgets('bridge two-column preview has bounded layout at normal text size',
      (tester) async {
    final session = _RecordingSessionBloc();
    addTearDown(session.close);
    await _pumpSurface(
      tester,
      home: const StudentOnboardingBridgePage(),
      session: session,
      size: const Size(390, 844),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.bedroom_parent_outlined)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.cleaning_services_outlined).first).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('quiz load failure shows retry instead of a writable form',
      (tester) async {
    final repository = _PreferencesRepository()
      ..saved =
          const LifestylePreferences(sleepSchedule: SleepSchedule.nightOwl)
      ..loadFailure = const CacheFailure('unreadable');
    await _pumpSurface(
      tester,
      home: LifestyleQuizPage(userId: _student.id, repository: repository),
    );
    expect(find.text('student_quiz.load_error_title'.tr()), findsOneWidget);
    expect(find.text('student_quiz.sleep_title'.tr()), findsNothing);
    expect(find.text('student_quiz.save'.tr()), findsNothing);
    expect(find.text('student_quiz.skip'.tr()), findsNothing);
    expect(repository.saveCalls, 0);

    repository.loadFailure = null;
    await tester.tap(find.text('student_quiz.retry'.tr()));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('student_quiz.title'.tr()));
    expect(
        context.read<LifestyleQuizBloc>().state.preferences, repository.saved);
    expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1 / 5);
    expect(tester.takeException(), isNull);
  });

  for (final skip in [false, true]) {
    testWidgets(
        'quiz ${skip ? 'skip' : 'save'} disables controls then refreshes session',
        (tester) async {
      final repository = _PreferencesRepository()
        ..saved = skip ? const LifestylePreferences() : _answers
        ..saveGate = Completer<void>();
      final session = _RecordingSessionBloc();
      final router = _router(AppRoutes.lifestyleQuiz, repository: repository);
      addTearDown(session.close);
      addTearDown(router.dispose);
      await _pumpSurface(tester, router: router, session: session);
      final action = find.text('student_quiz.${skip ? 'skip' : 'save'}'.tr());
      await tester.scrollUntilVisible(action, 400, maxScrolls: 50);
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.saveCalls, 1);
      final save = tester.widget<AppButton>(find.byType(AppButton));
      expect(save.onPressed, isNull);
      expect(save.isLoading, isTrue);
      expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'student_quiz.skip'.tr()),
              )
              .onPressed,
          isNull);
      expect(session.events.whereType<SessionCheckRequested>(), isEmpty);

      repository.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StudentDiscoveryPage), findsOneWidget);
      expect(session.events.whereType<SessionCheckRequested>(), hasLength(1));
      expect(repository.savedUserId, _student.id);
      expect(repository.saved!.isSkipped, skip);
      expect(repository.saved!.isComplete, !skip);
      if (skip) expect(repository.saved!.sleepSchedule, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('discovery shows honest shells and real quiz and account entry',
      (tester) async {
    final session = _RecordingSessionBloc();
    final router = _router(AppRoutes.discovery);
    addTearDown(session.close);
    addTearDown(router.dispose);
    await _pumpSurface(tester, router: router, session: session);
    expect(find.text('student_discovery.empty_explore'.tr()), findsOneWidget);
    expect(find.textContaining('1,250'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    for (final tab in ['requests', 'saved']) {
      await tester.tap(find.text('student_discovery.$tab'.tr()));
      await tester.pumpAndSettle();
      expect(find.text('student_discovery.empty_$tab'.tr()), findsOneWidget);
    }
    await tester.tap(find.text('student_discovery.match_quiz'.tr()));
    await tester.pumpAndSettle();
    final quiz = find.text('student_discovery.edit_quiz'.tr());
    await tester.ensureVisible(quiz);
    await tester.tap(quiz);
    await tester.pumpAndSettle();
    expect(find.byType(LifestyleQuizPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('student_discovery.account'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('Account destination'), findsOneWidget);
  });

  testWidgets('long pills wrap inside a constrained RTL row', (tester) async {
    await _pumpSurface(
      tester,
      locale: const Locale('ar'),
      textScale: 3,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            child: Row(children: [
              Expanded(
                child: KinshipPill(
                  icon: Icons.info_outline,
                  label: _translations['ar']!['student_onboarding']
                      ['preview_notice'] as String,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    expect(
        tester.getSize(find.byType(KinshipPill)).width, lessThanOrEqualTo(180));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  Widget? home,
  GoRouter? router,
  SessionBloc? session,
  Locale locale = const Locale('en'),
  bool dark = false,
  double textScale = 1,
  Size size = const Size(320, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final localized = EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('en'), Locale('ar')],
    startLocale: locale,
    saveLocale: false,
    path: 'assets/translations',
    assetLoader: const _AssetLoader(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (context, child) {
        Widget scale(BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            );
        final theme = dark
            ? buildDarkTheme(locale: locale)
            : buildLightTheme(locale: locale);
        return router == null
            ? MaterialApp(
                theme: theme,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: scale,
                home: home,
              )
            : MaterialApp.router(
                routerConfig: router,
                theme: theme,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: scale,
              );
      },
    ),
  );
  await tester.pumpWidget(session == null
      ? localized
      : BlocProvider<SessionBloc>.value(value: session, child: localized));
  await tester.pumpAndSettle();
}

GoRouter _router(String initial, {LifestylePreferencesRepository? repository}) {
  final preferences = repository ?? _PreferencesRepository();
  return GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: AppRoutes.roleSelection,
        name: 'roleSelection',
        builder: (context, state) => const RoleSelectionPage(),
      ),
      GoRoute(
        path: AppRoutes.studentAuth,
        name: 'studentAuth',
        builder: (_, state) => Scaffold(
          body: Text('auth:${state.uri.queryParameters['role'] ?? 'none'}'),
        ),
      ),
      GoRoute(
        path: AppRoutes.studentOnboarding,
        name: 'studentOnboarding',
        builder: (context, state) => const StudentOnboardingBridgePage(),
      ),
      GoRoute(
        path: AppRoutes.lifestyleQuiz,
        name: 'lifestyleQuiz',
        builder: (context, state) => LifestyleQuizPage(
          userId: _student.id,
          repository: preferences,
        ),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        name: 'discovery',
        builder: (context, state) => const StudentDiscoveryPage(),
      ),
      GoRoute(
        path: AppRoutes.account,
        name: 'account',
        builder: (context, state) =>
            const Scaffold(body: Text('Account destination')),
      ),
    ],
  );
}

class _AssetLoader extends AssetLoader {
  const _AssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

class _RecordingSessionBloc extends Bloc<SessionEvent, SessionState>
    implements SessionBloc {
  _RecordingSessionBloc({bool markSkipBusy = false})
      : super(const SessionState.authenticated(_student)) {
    on<SessionEvent>((event, emit) {
      events.add(event);
      if (markSkipBusy && event is SessionOnboardingSkipRequested) {
        emit(const SessionState(
          status: SessionStatus.authenticated,
          user: _student,
          isUpdatingOnboarding: true,
        ));
      }
    });
  }

  final events = <SessionEvent>[];

  void failSkip() => emit(const SessionState(
        status: SessionStatus.authenticated,
        user: _student,
        errorMessage: 'auth_flow.preferences_failed',
      ));
}

class _PreferencesRepository implements LifestylePreferencesRepository {
  LifestylePreferences? saved;
  String? savedUserId;
  Failure? loadFailure;
  Completer<void>? saveGate;
  int saveCalls = 0;

  @override
  FutureEither<LifestylePreferences?> getPreferences(
          {required String userId}) async =>
      loadFailure == null ? right(saved) : left(loadFailure!);

  @override
  FutureEither<void> savePreferences({
    required String userId,
    required LifestylePreferences preferences,
  }) async {
    saveCalls++;
    await saveGate?.future;
    saved = preferences;
    savedUserId = userId;
    return right(null);
  }

  @override
  FutureEither<void> deletePreferences({required String userId}) async {
    saved = null;
    return right(null);
  }
}
