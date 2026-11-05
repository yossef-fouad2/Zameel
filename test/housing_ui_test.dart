import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/app.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/wrappers/state_wrapper.dart';
import 'package:zameel/src/theme/text_theme.dart';
import 'package:zameel/src/ui/landlord/landlord_listings_page.dart';
import 'package:zameel/src/ui/landlord/listing_editor_page.dart';
import 'package:zameel/src/ui/listings/widgets/listing_ui.dart';
import 'package:zameel/src/ui/student/discovery_page.dart';
import 'package:zameel/src/ui/student/property_details_page.dart';
import 'support/auth_fakes.dart';
import 'support/profile_fakes.dart';
import 'support/listing_fakes.dart';

final _translations = <String, Map<String, dynamic>>{};

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

Future<GoRouter> _pumpHousing(
  WidgetTester tester,
  FakeListingRepository listings, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  FakeAuthRepository? auth,
  FakePreferencesRepository? preferences,
  FakeUniversityRepository? universities,
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
  await EasyLocalization.ensureInitialized();
  final authentication = auth ?? (FakeAuthRepository()..user = landlord);
  addTearDown(authentication.close);
  await tester.pumpWidget(EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ar')],
    path: 'assets/translations',
    assetLoader: const _Assets(),
    saveLocale: false,
    startLocale: locale,
    fallbackLocale: const Locale('en'),
    child: StateWrapper(
      repository: authentication,
      profileRepository: FakeProfileRepository(authentication.user ?? landlord),
      preferencesRepository: preferences ?? FakePreferencesRepository(),
      listingRepository: listings,
      universityRepository: universities ?? FakeUniversityRepository(),
      child: const App(),
    ),
  ));
  await tester.pumpAndSettle();
  return GoRouter.of(tester.element(find.byType(Scaffold).first));
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final target = find.widgetWithText(AppButton, label);
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
        target, find.byType(Scrollable).first, const Offset(0, -250));
  }
  await Scrollable.ensureVisible(target.evaluate().first, alignment: .4);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await Scrollable.ensureVisible(field.evaluate().single, alignment: .3);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _typeRoomField(
    WidgetTester tester, String name, String value) async {
  final field = find.byWidgetPredicate((widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('listing.$name.'));
  await Scrollable.ensureVisible(field.evaluate().single, alignment: .3);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump();
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

  testWidgets(
      'landlord creates a real private draft without fake map or route data',
      (tester) async {
    final repository = FakeListingRepository();
    await _pumpHousing(tester, repository);
    expect(find.byType(LandlordListingsPage), findsOneWidget);
    await _tapButton(tester, 'listings.landlord.create'.tr());
    expect(find.byType(ListingEditorPage), findsOneWidget);
    await _type(tester, 'listings.fields.title'.tr(), 'My test property');
    await _type(tester, 'listings.fields.monthly_rent'.tr(), '1400');
    await _type(tester, 'listings.fields.total_beds'.tr(), '3');
    await _tapButton(tester, 'listings.editor.save'.tr());
    expect(repository.creates, 1);
    expect(repository.listings.values.single.status, ListingStatus.draft);
    expect(repository.listings.values.single.location, isNull);
    expect(repository.refreshes, 0);
    expect(find.text('listings.feedback.saved'.tr()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('published pin disclosure is confirmed before status mutation',
      (tester) async {
    final repository = FakeListingRepository()
      ..listings['listing-1'] = testListing();
    await _pumpHousing(tester, repository);
    await tester.tap(find.byType(PropertyListingCard));
    await tester.pumpAndSettle();
    await _tapButton(tester, 'listings.editor.publish'.tr());
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.publishes, 0);
    await tester
        .tap(find.widgetWithText(TextButton, 'listings.cancel'.tr()).last);
    await tester.pumpAndSettle();
    expect(repository.publishes, 0);
    await _tapButton(tester, 'listings.editor.publish'.tr());
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching:
            find.widgetWithText(TextButton, 'listings.editor.publish'.tr())));
    await tester.pumpAndSettle();
    expect(repository.publishes, 1);
    expect(repository.listings['listing-1']!.status, ListingStatus.published);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'owner configures double and triple bed prices and edits saved options',
      (tester) async {
    final repository = FakeListingRepository();
    await _pumpHousing(tester, repository);
    await _tapButton(tester, 'listings.landlord.create'.tr());
    await _type(tester, 'listings.fields.title'.tr(), 'Mixed room home');
    for (final type in ListingRoomType.values) {
      final toggle = find.byKey(ValueKey('listing.room.${type.value}'));
      await Scrollable.ensureVisible(toggle.evaluate().single, alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await _typeRoomField(tester, '${type.value}RoomCount', '1');
      await _typeRoomField(tester, '${type.value}MonthlyRent',
          type == ListingRoomType.doubleRoom ? '2000' : '1250');
    }
    expect(repository.creates, 0);
    expect(
        find.widgetWithText(TextFormField, 'listings.fields.total_beds'.tr()),
        findsNothing);
    await _tapButton(tester, 'listings.editor.save'.tr());
    final saved = repository.listings.values.single;
    expect(saved.roomOptions, hasLength(2));
    expect(saved.totalBeds, 5);
    expect(saved.monthlyRent, 1250);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final card = find.byType(PropertyListingCard);
    await Scrollable.ensureVisible(card.evaluate().single, alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    await _typeRoomField(tester, 'doubleMonthlyRent', '2100.50');
    await _tapButton(tester, 'listings.editor.save'.tr());
    expect(repository.updates, 1);
    expect(
        repository.listings.values.single
            .roomOption(ListingRoomType.doubleRoom)!
            .monthlyRent,
        2100.50);
    expect(
        repository.listings.values.single
            .roomOption(ListingRoomType.tripleRoom)!
            .monthlyRent,
        1250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a map-picker deep link can return to the landlord dashboard',
      (tester) async {
    final router = await _pumpHousing(tester, FakeListingRepository());
    router.goNamed('propertyLocation');
    await tester.pumpAndSettle();
    final cancel = find.byKey(const ValueKey('property.location.cancel'));
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(LandlordListingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar Back preserves edits unless the user discards them',
      (tester) async {
    final repository = FakeListingRepository()
      ..listings['listing-1'] = testListing();
    await _pumpHousing(tester, repository);
    await tester.tap(find.byType(PropertyListingCard));
    await tester.pumpAndSettle();
    await _type(tester, 'listings.fields.title'.tr(), 'Unsaved edit');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('profile.keep_editing'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(ListingEditorPage), findsOneWidget);
    expect(find.text('Unsaved edit'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('profile.discard'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordListingsPage), findsOneWidget);
    expect(repository.updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student chooses university and opens the nearest real property',
      (tester) async {
    final repository = FakeListingRepository()
      ..listings['near'] = testListing(
          id: 'near', title: 'Near home', status: ListingStatus.published)
      ..listings['far'] = testListing(
          id: 'far', title: 'Far home', status: ListingStatus.published)
      ..routes['near'] = [testRoute(distance: 700)]
      ..routes['far'] = [testRoute(distance: 2200)];
    final universities = FakeUniversityRepository();
    final preferences = FakePreferencesRepository()
      ..values[student.id] = const LifestylePreferences(isSkipped: true);
    await _pumpHousing(tester, repository,
        auth: FakeAuthRepository()..user = student,
        preferences: preferences,
        universities: universities);
    expect(find.byType(StudentDiscoveryPage), findsOneWidget);
    expect(repository.searches, isEmpty);
    final selector = find.byKey(const ValueKey('university.selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(testUniversity.name));
    await tester.pumpAndSettle();
    expect(repository.searches.single.$1, 1);
    expect(universities.selections[student.id], 1);
    final first = find.byType(PropertyListingCard).first;
    expect(tester.widget<PropertyListingCard>(first).listing.id, 'near');
    await Scrollable.ensureVisible(first.evaluate().single, alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.byType(PropertyDetailsPage), findsOneWidget);
    expect(find.text('Near home'), findsOneWidget);
    expect(find.byType(WalkingDistanceLabel), findsOneWidget);
    expect(
        tester
            .widget<WalkingDistanceLabel>(find.byType(WalkingDistanceLabel))
            .metres,
        700);
    expect(repository.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student detail deep link does not expose a private draft',
      (tester) async {
    final repository = FakeListingRepository()
      ..listings['private'] = testListing(id: 'private');
    final preferences = FakePreferencesRepository()
      ..values[student.id] = const LifestylePreferences(isSkipped: true);
    final router = await _pumpHousing(tester, repository,
        auth: FakeAuthRepository()..user = student, preferences: preferences);
    router.pushNamed('listingDetails',
        pathParameters: {'listingId': 'private'},
        queryParameters: {'universityId': '1'});
    await tester.pumpAndSettle();
    expect(
        find.text('listings.details.unavailable_title'.tr()), findsOneWidget);
    expect(find.byType(ListingPrice), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (size, locale, scale, brightness) in [
    (const Size(320, 700), const Locale('en'), 1.0, Brightness.light),
    (const Size(390, 844), const Locale('ar'), 2.0, Brightness.dark),
    (const Size(1100, 900), const Locale('en'), 1.0, Brightness.dark),
  ]) {
    testWidgets('landlord views fit $size $locale $scale $brightness',
        (tester) async {
      final repository = FakeListingRepository()
        ..listings['listing-1'] = testListing(roomOptions: testRoomOptions);
      final router = await _pumpHousing(tester, repository,
          size: size, locale: locale, scale: scale, brightness: brightness);
      expect(tester.takeException(), isNull);
      router
          .pushNamed('listingEdit', pathParameters: {'listingId': 'listing-1'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tapButton(tester, 'listings.editor.publish'.tr());
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
    testWidgets(
        'student discovery and details fit $size $locale $scale $brightness',
        (tester) async {
      final repository = FakeListingRepository()
        ..listings['home'] = testListing(
            id: 'home',
            status: ListingStatus.published,
            roomOptions: testRoomOptions)
        ..routes['home'] = [testRoute()];
      final preferences = FakePreferencesRepository()
        ..values[student.id] = const LifestylePreferences(isSkipped: true);
      final universities = FakeUniversityRepository()
        ..selections[student.id] = 1;
      final router = await _pumpHousing(tester, repository,
          size: size,
          locale: locale,
          scale: scale,
          brightness: brightness,
          auth: FakeAuthRepository()..user = student,
          preferences: preferences,
          universities: universities);
      expect(find.byType(StudentDiscoveryPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      router.pushNamed('listingDetails',
          pathParameters: {'listingId': 'home'},
          queryParameters: {'universityId': '1'});
      await tester.pumpAndSettle();
      expect(find.byType(PropertyDetailsPage), findsOneWidget);
      final missingMap = find.text('maps.missing_key_title'.tr());
      await tester.dragUntilVisible(
          missingMap, find.byType(Scrollable).first, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(missingMap, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
