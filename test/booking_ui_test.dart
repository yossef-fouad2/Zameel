import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zameel/src/app.dart';
import 'package:zameel/src/data/models/auth_result.dart';
import 'package:zameel/src/data/models/booking.dart';
import 'package:zameel/src/data/models/booking_failure.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/shared/widgets/app_button.dart';
import 'package:zameel/src/shared/wrappers/state_wrapper.dart';
import 'package:zameel/src/theme/text_theme.dart';
import 'package:zameel/src/ui/bookings/booking_details_page.dart';
import 'package:zameel/src/ui/bookings/booking_request_page.dart';
import 'package:zameel/src/ui/bookings/bookings_page.dart';
import 'package:zameel/src/ui/bookings/widgets/booking_ui.dart';
import 'package:zameel/src/ui/landlord/landlord_listings_page.dart';
import 'package:zameel/src/ui/listings/widgets/listing_ui.dart';
import 'package:zameel/src/ui/student/discovery_page.dart';
import 'package:zameel/src/utils/failure.dart';

import 'support/auth_fakes.dart';
import 'support/booking_fakes.dart';
import 'support/listing_fakes.dart';
import 'support/profile_fakes.dart';

final _translations = <String, Map<String, dynamic>>{};

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations[locale.languageCode]!;
}

Future<GoRouter> _pumpBookings(
  WidgetTester tester,
  FakeBookingRepository bookings, {
  FakeAuthRepository? auth,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reducedMotion);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  final authentication = auth ?? (FakeAuthRepository()..user = student);
  addTearDown(authentication.close);
  final preferences = FakePreferencesRepository()
    ..values[student.id] = const LifestylePreferences(isSkipped: true)
    ..values['student-2'] = const LifestylePreferences(isSkipped: true);
  await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      assetLoader: const _Assets(),
      saveLocale: false,
      startLocale: locale,
      fallbackLocale: const Locale('en'),
      child: StateWrapper(
          repository: authentication,
          profileRepository:
              FakeProfileRepository(authentication.user ?? student),
          preferencesRepository: preferences,
          listingRepository: bookings.listings,
          universityRepository: FakeUniversityRepository()
            ..selections[student.id] = 1,
          bookingRepository: bookings,
          child: const App())));
  await tester.pumpAndSettle();
  return GoRouter.of(tester.element(find.byType(Scaffold).first));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.dragUntilVisible(
        target, find.byType(Scrollable).first, const Offset(0, -240));
  }
  await Scrollable.ensureVisible(target.evaluate().first, alignment: .4);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> _button(WidgetTester tester, String key) =>
    _tap(tester, find.widgetWithText(AppButton, key.tr()));

Future<void> _confirm(WidgetTester tester, BookingAction action) async {
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, action.translationKey.tr())));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    EasyLocalization.logger.enableLevels = [];
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

  FakeBookingRepository repository() => FakeBookingRepository(
      listings: FakeListingRepository()
        ..listings['listing-1'] = bookingListing());

  testWidgets(
      'student submits, tracks and cancels a real request from property details',
      (tester) async {
    final bookings = repository();
    final router = await _pumpBookings(tester, bookings);
    expect(bookings.pages, isEmpty, reason: 'Hidden Requests tab loads lazily');
    router.pushNamed('listingDetails',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('property.request_bed')));
    expect(find.byType(BookingRequestPage), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField), 'A note for the landlord');
    await _tap(tester, find.byKey(const ValueKey('booking.submit')));
    expect(bookings.submissions, hasLength(1));
    expect(bookings.bookings.values.single.status, BookingStatus.pending);
    expect(bookings.listings.listings['listing-1']!.occupiedBeds, 0);
    expect(find.text('bookings.request.recorded'.tr()), findsOneWidget);
    await _button(tester, 'bookings.open_request');
    expect(find.byType(BookingDetailsPage), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('booking.action.cancel')));
    expect(bookings.actions, isEmpty);
    await _confirm(tester, BookingAction.cancel);
    expect(bookings.bookings.values.single.status, BookingStatus.cancelled);
    router.goNamed('discovery', queryParameters: {'tab': 'requests'});
    await tester.pumpAndSettle();
    expect(find.byType(BookingCard), findsOneWidget);
    expect(tester.widget<BookingCard>(find.byType(BookingCard)).booking.status,
        BookingStatus.cancelled);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'landlord reviews original quote, confirms accept and refreshes availability',
      (tester) async {
    final bookings = repository()..bookings['booking-1'] = testBooking();
    await _pumpBookings(tester, bookings,
        auth: FakeAuthRepository()..user = landlord);
    await _button(tester, 'bookings.landlord.navigation');
    expect(find.byType(LandlordBookingsPage), findsOneWidget);
    await _tap(tester, find.byType(BookingCard));
    expect(
        tester
            .widget<BookingQuote>(find.byType(BookingQuote))
            .booking
            .monthlyRent,
        1250);
    await _tap(tester, find.byKey(const ValueKey('booking.action.accept')));
    expect(bookings.actions, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'bookings.go_back'.tr()));
    await tester.pumpAndSettle();
    expect(bookings.actions, isEmpty);
    await _tap(tester, find.byKey(const ValueKey('booking.action.accept')));
    await _confirm(tester, BookingAction.accept);
    expect(bookings.listings.listings['listing-1']!.occupiedBeds, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(BookingCard), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('bookings.filter.accepted')));
    expect(find.byType(BookingCard), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LandlordListingsPage), findsOneWidget);
    final card = find.byType(PropertyListingCard);
    if (card.evaluate().isEmpty) {
      await tester.dragUntilVisible(
          card, find.byType(Scrollable).first, const Offset(0, -220));
    }
    expect(tester.widget<PropertyListingCard>(card).listing.availableBeds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'student chooses a room type, sees its price and keeps it in the request',
      (tester) async {
    final bookings = repository()
      ..listings.listings['listing-1'] =
          bookingListing(roomOptions: testRoomOptions);
    final router = await _pumpBookings(tester, bookings);
    router.pushNamed('bookingRequest',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('booking.room.double')));
    var price = tester.widget<ListingPrice>(
        find.byKey(const ValueKey('booking.selected_price')));
    expect(price.roomOption!.monthlyRent, 2000);
    await _tap(tester, find.byKey(const ValueKey('booking.room.triple')));
    await tester.dragUntilVisible(
        find.byKey(const ValueKey('booking.selected_price')),
        find.byType(Scrollable).first,
        const Offset(0, 180));
    await tester.pumpAndSettle();
    price = tester.widget<ListingPrice>(
        find.byKey(const ValueKey('booking.selected_price')));
    expect(price.roomOption!.monthlyRent, 1250);
    expect(bookings.submissions, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'A room-only draft must be protected');
    await tester.tap(find.text('bookings.stay'.tr()));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('booking.submit')));
    expect(bookings.submissions.single.roomType, ListingRoomType.tripleRoom);
    expect(bookings.bookings.values.single.monthlyRent, 1250);
    await _button(tester, 'bookings.open_request');
    expect(
        tester.widget<BookingQuote>(find.byType(BookingQuote)).booking.roomType,
        ListingRoomType.tripleRoom);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'full room types are visible but disabled while another type is available',
      (tester) async {
    final bookings = repository()
      ..listings.listings['listing-1'] = bookingListing(roomOptions: [
        const ListingRoomOption(
            type: ListingRoomType.doubleRoom,
            roomCount: 1,
            monthlyRent: 2000,
            occupiedBeds: 2),
        testRoomOptions.last,
      ]);
    final router = await _pumpBookings(tester, bookings);
    router.pushNamed('bookingRequest',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pumpAndSettle();
    final full = find.byKey(const ValueKey('booking.room.double'));
    await _tap(tester, full);
    expect(
        tester.widget<RadioListTile<ListingRoomType>>(full).enabled, isFalse);
    expect(
        tester
            .widget<ListingPrice>(
                find.byKey(const ValueKey('booking.selected_price')))
            .roomOption,
        isNull);
    await _tap(tester, find.byKey(const ValueKey('booking.room.triple')));
    await _tap(tester, find.byKey(const ValueKey('booking.submit')));
    expect(bookings.submissions.single.roomType, ListingRoomType.tripleRoom);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'archived accepted request remains cancellable without leaking listing details',
      (tester) async {
    final bookings = repository()
      ..bookings['booking-1'] = testBooking(status: BookingStatus.accepted)
      ..listings.listings['listing-1'] =
          bookingListing(status: ListingStatus.archived, occupied: 1);
    final router = await _pumpBookings(tester, bookings);
    router.pushNamed('studentBookingDetails',
        pathParameters: {'bookingId': 'booking-1'});
    await tester.pumpAndSettle();
    expect(find.text('Campus home'), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('booking.action.cancel')));
    expect(find.text('bookings.confirm.cancel_accepted_body'.tr()),
        findsOneWidget);
    await _confirm(tester, BookingAction.cancel);
    expect(bookings.listings.listings['listing-1']!.occupiedBeds, 0);
    expect(bookings.bookings['booking-1']!.status, BookingStatus.cancelled);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'both Back paths protect an unsent message and discard never submits',
      (tester) async {
    final bookings = repository();
    final router = await _pumpBookings(tester, bookings);
    router.pushNamed('bookingRequest',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Unsent message');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bookings.stay'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('Unsent message'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('bookings.leave'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(BookingRequestPage), findsNothing);
    expect(bookings.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uncertain submission freezes message, warns on leaving, and retries the same ID',
      (tester) async {
    final bookings = repository()
      ..submitFailure = const BookingWriteUncertainFailure();
    final router = await _pumpBookings(tester, bookings);
    router.pushNamed('bookingRequest',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Keep the payload');
    await _tap(tester, find.byKey(const ValueKey('booking.submit')));
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('bookings.request.leave_uncertain'.tr()), findsOneWidget);
    await tester.tap(find.text('bookings.stay'.tr()));
    await tester.pumpAndSettle();
    await _button(tester, 'bookings.reload');
    bookings.submitFailure = null;
    await _tap(tester, find.byKey(const ValueKey('booking.submit')));
    expect(bookings.submissions, hasLength(2));
    expect(bookings.submissions[0], bookings.submissions[1]);
    expect(find.text('bookings.request.recorded'.tr()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account switch replaces request state before an old lookup completes',
      (tester) async {
    final bookings = repository();
    final auth = FakeAuthRepository()..user = student;
    final router = await _pumpBookings(tester, bookings, auth: auth);
    final gate = Completer<Either<Failure, Booking?>>();
    bookings.onFind = (_) => gate.future;
    router.pushNamed('bookingRequest',
        pathParameters: {'listingId': 'listing-1'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    bookings.onFind = (_) async => right(null);
    auth.user = const AppUser(
        id: 'student-2', email: 'other@example.test', role: UserRole.student);
    auth.changes.add(AuthSessionChange.refreshed);
    await tester.pumpAndSettle();
    gate.complete(right(testBooking(message: 'Private old account message')));
    await tester.pumpAndSettle();
    expect(find.text('Private old account message'), findsNothing);
    expect(find.text('bookings.request.existing'.tr()), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(bookings.finds.last.$1, 'student-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong-role deep links redirect without loading booking data',
      (tester) async {
    final bookings = repository();
    final router = await _pumpBookings(tester, bookings);
    router.goNamed('landlordBookingDetails',
        pathParameters: {'bookingId': 'booking-1'});
    await tester.pumpAndSettle();
    expect(find.byType(StudentDiscoveryPage), findsOneWidget);
    expect(find.byType(BookingDetailsPage), findsNothing);
    expect(bookings.detailReads, 0);
    expect(bookings.actions, isEmpty);
  });

  testWidgets(
      'inbox distinguishes failure from empty and retries without fake requests',
      (tester) async {
    final bookings = repository()
      ..readFailure = const NetworkFailure('bookings.errors.request_failed');
    final router = await _pumpBookings(tester, bookings);
    router.goNamed('discovery', queryParameters: {'tab': 'requests'});
    await tester.pumpAndSettle();
    expect(find.text('bookings.load_failed'.tr()), findsOneWidget);
    expect(find.text('bookings.student.empty_title'.tr()), findsNothing);
    bookings.readFailure = null;
    await _button(tester, 'auth_flow.retry');
    expect(find.text('bookings.student.empty_title'.tr()), findsOneWidget);
    expect(find.byType(BookingCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (size, locale, scale, brightness) in [
    (const Size(320, 700), const Locale('en'), 1.0, Brightness.light),
    (const Size(390, 844), const Locale('ar'), 2.0, Brightness.dark),
    (const Size(1100, 900), const Locale('en'), 2.0, Brightness.dark),
  ]) {
    for (final owner in [false, true]) {
      testWidgets('booking views fit $size $locale $scale owner=$owner',
          (tester) async {
        final bookings = repository()
          ..listings.listings['listing-1'] =
              bookingListing(roomOptions: testRoomOptions)
          ..bookings['booking-1'] = testBooking(
              message: 'A longer request message ' * 20,
              roomType: ListingRoomType.doubleRoom);
        final router = await _pumpBookings(tester, bookings,
            auth: FakeAuthRepository()..user = owner ? landlord : student,
            size: size,
            locale: locale,
            scale: scale,
            brightness: brightness);
        if (owner) {
          router.pushNamed('landlordBookings');
        } else {
          router.goNamed('discovery', queryParameters: {'tab': 'requests'});
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byType(BookingCard));
        await _tap(
            tester,
            find.byKey(ValueKey(
                owner ? 'booking.action.reject' : 'booking.action.cancel')));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester
            .tap(find.widgetWithText(TextButton, 'bookings.go_back'.tr()));
        await tester.pumpAndSettle();
        if (!owner) {
          bookings.bookings.clear();
          router.pushNamed('bookingRequest',
              pathParameters: {'listingId': 'listing-1'});
          await tester.pumpAndSettle();
          await _tap(tester, find.byKey(const ValueKey('booking.room.double')));
          await _tap(tester, find.byType(TextFormField));
          await tester.enterText(
              find.byType(TextFormField), 'A keyboard-visible message');
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final submit = find.byKey(const ValueKey('booking.submit'));
          if (submit.evaluate().isEmpty) {
            await tester.dragUntilVisible(
                submit, find.byType(Scrollable).first, const Offset(0, -200));
          }
          await Scrollable.ensureVisible(submit.evaluate().single,
              alignment: .5);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
        'booking motion respects reducedMotion=$reducedMotion and settles',
        (tester) async {
      final bookings = repository()..bookings['booking-1'] = testBooking();
      final router =
          await _pumpBookings(tester, bookings, reducedMotion: reducedMotion);
      router.goNamed('discovery', queryParameters: {'tab': 'requests'});
      await tester.pumpAndSettle();
      final card = find.byType(BookingCard);
      if (card.evaluate().isEmpty) {
        await tester.dragUntilVisible(
            card, find.byType(Scrollable).first, const Offset(0, -240));
      }
      await Scrollable.ensureVisible(card.evaluate().single, alignment: .4);
      await tester.pumpAndSettle();
      final reveal =
          find.ancestor(of: card, matching: find.byType(HousingReveal));
      expect(reveal, findsOneWidget);
      expect(
          find.descendant(
              of: reveal, matching: find.byType(TweenAnimationBuilder<double>)),
          reducedMotion ? findsNothing : findsOneWidget);

      await _tap(tester, card);
      final badge = find.byType(BookingStatusBadge);
      expect(
          MediaQuery.disableAnimationsOf(tester.element(badge)), reducedMotion);
      expect(
          find.descendant(of: badge, matching: find.byType(AnimatedSwitcher)),
          reducedMotion ? findsNothing : findsOneWidget);
      bookings.bookings['booking-1'] =
          testBooking(status: BookingStatus.accepted);
      await tester.tap(find.byTooltip('bookings.refresh'.tr()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<BookingStatusBadge>(badge).status,
          BookingStatus.accepted);
      final outgoing = find.descendant(
          of: badge,
          matching: find.byKey(const ValueKey(BookingStatus.pending)));
      expect(outgoing, reducedMotion ? findsNothing : findsOneWidget);
      if (!reducedMotion) {
        expect(
            find.ancestor(
                of: outgoing, matching: find.byType(ExcludeSemantics)),
            findsOneWidget);
      }
      await tester.pumpAndSettle();
      expect(outgoing, findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
