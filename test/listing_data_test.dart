import 'package:flutter_test/flutter_test.dart';
import 'package:zameel/src/data/models/geo_point.dart';
import 'package:zameel/src/data/models/listing.dart';
import 'package:zameel/src/data/models/listing_draft.dart';
import 'package:zameel/src/data/models/listing_search_result.dart';
import 'package:zameel/src/data/models/university.dart';
import 'package:zameel/src/data/models/university_route.dart';

const _point = GeoPoint(latitude: 30.0276, longitude: 31.21014);
const _timestamp = '2026-10-22T01:02:03.123456+00:00';
const _listingId = '12345678-1234-1234-1234-123456789abc';
const _ownerId = '22345678-1234-1234-1234-123456789abc';
const _validDraft = ListingDraft(
  title: ' Shared home ',
  description: ' Quiet entrance ',
  address: ' University Street ',
  monthlyRent: '1250.50',
  totalBeds: '3',
  location: _point,
);

Map<String, Object?> _listingRow() => {
      'id': _listingId,
      'landlord_id': _ownerId,
      'title': 'Shared home',
      'description': null,
      'address': 'University Street',
      'latitude': _point.latitude,
      'longitude': _point.longitude,
      'monthly_rent': 1250.50,
      'currency': 'EGP',
      'pricing_unit': 'per_bed',
      'total_bed_capacity': 3,
      'occupied_beds': 1,
      'available_beds': 2,
      'status': 'draft',
      'created_at': '2026-10-01T00:00:00Z',
      'updated_at': _timestamp,
    };

Map<String, Object?> _universityRow() => {
      'id': 1,
      'name': 'Cairo University',
      'city': 'Giza',
      'latitude': _point.latitude,
      'longitude': _point.longitude,
      'is_active': true,
    };

Map<String, Object?> _routeRow({Object? distance = 125.123456789}) => {
      'university_id': 1,
      'university': _universityRow(),
      'status': 'ready',
      'distance_m': distance,
      'calculated_at': _timestamp,
    };

void main() {
  group('GeoPoint', () {
    test('preserves latitude/longitude precision and inclusive world bounds',
        () {
      expect(GeoPoint.fromJson(_universityRow()), _point);
      expect(_point.isValid, isTrue);
      expect(const GeoPoint(latitude: -90, longitude: -180).isValid, isTrue);
      expect(const GeoPoint(latitude: 90, longitude: 180).isValid, isTrue);
      expect(const GeoPoint(latitude: 0, longitude: 0).isValid, isTrue);
    });

    for (final point in [
      const GeoPoint(latitude: 90.0001, longitude: 0),
      const GeoPoint(latitude: -90.0001, longitude: 0),
      const GeoPoint(latitude: 0, longitude: 180.0001),
      const GeoPoint(latitude: 0, longitude: -180.0001),
      const GeoPoint(latitude: double.nan, longitude: 0),
      const GeoPoint(latitude: 0, longitude: double.infinity),
      const GeoPoint(latitude: double.negativeInfinity, longitude: 0),
    ]) {
      test('rejects invalid coordinates $point', () {
        expect(point.isValid, isFalse);
        expect(
          () => GeoPoint.fromJson({
            'latitude': point.latitude,
            'longitude': point.longitude,
          }),
          throwsFormatException,
        );
      });
    }

    test('never supplies a missing coordinate or coerces text', () {
      for (final row in <Map<String, Object?>>[
        {'latitude': 30},
        {'longitude': 31},
        {'latitude': '30', 'longitude': 31},
        {'latitude': 30, 'longitude': null},
      ]) {
        expect(() => GeoPoint.fromJson(row), throwsFormatException);
      }
    });
  });

  group('University', () {
    test('keeps supplied English text and explicitly parses the active flag',
        () {
      final university = University.fromJson(_universityRow());
      expect(university.id, 1);
      expect(university.name, 'Cairo University');
      expect(university.city, 'Giza');
      expect(university.location, _point);
      expect(university.isActive, isTrue);
      expect(
        University.fromJson({..._universityRow(), 'is_active': false}).isActive,
        isFalse,
      );
    });

    test('rejects malformed catalogue rows instead of inventing defaults', () {
      for (final change in <Map<String, Object?>>[
        {'id': 0},
        {'id': 2147483648},
        {'id': 1.0},
        {'name': ''},
        {'city': null},
        {'is_active': 'true'},
        {'is_active': null},
        {'latitude': double.nan},
      ]) {
        expect(() => University.fromJson({..._universityRow(), ...change}),
            throwsFormatException);
      }
    });
  });

  group('Listing', () {
    test('preserves raw server revision and genuine generated availability',
        () {
      final listing = Listing.fromJson(_listingRow());
      expect(listing.updatedAt, _timestamp);
      expect(listing.location, _point);
      expect(listing.monthlyRent, 1250.50);
      expect(listing.totalBeds, 3);
      expect(listing.occupiedBeds, 1);
      expect(listing.availableBeds, 2);
      expect(listing.description, isNull);
      expect(listing, Listing.fromJson(_listingRow()));
    });

    test('accepts paired null coordinates including legacy published rows', () {
      final listing = Listing.fromJson({
        ..._listingRow(),
        'latitude': null,
        'longitude': null,
        'status': 'published',
      });
      expect(listing.location, isNull);
      expect(listing.status, ListingStatus.published);
    });

    test('all statuses and pricing units map explicitly to DB and locale keys',
        () {
      for (final status in ListingStatus.values) {
        expect(ListingStatus.fromJson(status.value), status);
        expect(status.translationKey, 'listings.status.${status.value}');
      }
      for (final unit in PricingUnit.values) {
        expect(PricingUnit.fromJson(unit.value), unit);
        expect(unit.translationKey, 'listings.pricing.${unit.value}');
      }
      expect(PricingUnit.perBed.value, 'per_bed');
      expect(PricingUnit.perRoom.value, 'per_room');
      expect(PricingUnit.perProperty.value, 'per_property');
      expect(() => ListingStatus.fromJson('future'), throwsFormatException);
      expect(() => PricingUnit.fromJson('perBed'), throwsFormatException);
    });

    test('rejects invalid fields, enums, incomplete pins and inconsistent beds',
        () {
      for (final change in <Map<String, Object?>>[
        {'id': ''},
        {'landlord_id': null},
        {'title': ' '},
        {'description': 2},
        {'address': ''},
        {'latitude': null},
        {'longitude': '31'},
        {'monthly_rent': -1},
        {'monthly_rent': double.nan},
        {'monthly_rent': double.infinity},
        {'monthly_rent': '1200.00'},
        {'monthly_rent': 1.001},
        {'monthly_rent': 10000000000},
        {'pricing_unit': 'future'},
        {'status': null},
        {'currency': 'egp'},
        {'total_bed_capacity': 0},
        {'total_bed_capacity': 2147483648},
        {'total_bed_capacity': 3.0},
        {'occupied_beds': -1},
        {'occupied_beds': 4},
        {'available_beds': 3},
        {'available_beds': null},
        {'updated_at': 'not-a-timestamp'},
      ]) {
        expect(() => Listing.fromJson({..._listingRow(), ...change}),
            throwsFormatException,
            reason: '$change');
      }
      final missing = _listingRow()..remove('latitude');
      expect(() => Listing.fromJson(missing), throwsFormatException);
    });
  });

  group('ListingDraft', () {
    test('starts empty, and reconstructs editable text without server fields',
        () {
      const empty = ListingDraft();
      expect(empty.currency, 'EGP');
      expect(empty.pricingUnit, PricingUnit.perBed);
      expect(empty.location, isNull);
      expect(
          empty.validate().keys.toSet(), {'title', 'monthlyRent', 'totalBeds'});
      final draft = ListingDraft.fromListing(Listing.fromJson(_listingRow()));
      expect(draft.monthlyRent, '1250.50');
      expect(draft.totalBeds, '3');
      expect(draft.description, '');
      expect(draft.location, _point);
    });

    test('serializes exactly the granted columns, trimming empty optional text',
        () {
      final payload =
          _validDraft.copyWith(description: ' ', address: '').toJson();
      expect(payload, {
        'title': 'Shared home',
        'description': null,
        'address': null,
        'latitude': 30.0276,
        'longitude': 31.21014,
        'monthly_rent': 1250.50,
        'currency': 'EGP',
        'pricing_unit': 'per_bed',
        'total_bed_capacity': 3,
      });
      expect(_validDraft.copyWith(clearLocation: true).toJson()['latitude'],
          isNull);
      expect(_validDraft.copyWith(clearLocation: true).toJson()['longitude'],
          isNull);
      expect(() => const ListingDraft().toJson(), throwsFormatException);
    });

    test(
        'supports inclusive money limits without rounding extra decimal places',
        () {
      for (final text in ['0', '0.00', '1.23', '9999999999.99', ' 99.10 ']) {
        final draft = _validDraft.copyWith(monthlyRent: text);
        expect(draft.validate(), isEmpty, reason: text);
        expect(draft.toJson()['monthly_rent'], double.parse(text.trim()));
      }
      for (final text in [
        '',
        '-1',
        'NaN',
        'Infinity',
        '-Infinity',
        '1e3',
        '1.001',
        '10000000000',
        '9007199254740993',
        '1,000',
        '1,50',
        '+1',
        '0.001',
      ]) {
        expect(
            _validDraft.copyWith(monthlyRent: text).validate()['monthlyRent'],
            'listings.validation.monthly_rent',
            reason: text);
      }
    });

    test('bounds positive integer beds and protects occupied capacity', () {
      expect(_validDraft.copyWith(totalBeds: '2147483647').validate(), isEmpty);
      expect(_validDraft.copyWith(totalBeds: '1').validate(occupiedBeds: 1),
          isEmpty);
      expect(_validDraft.copyWith(totalBeds: '1').validate(occupiedBeds: 2),
          {'totalBeds': 'listings.validation.occupied_beds'});
      for (final text in [
        '',
        '0',
        '-1',
        '1.5',
        '1e3',
        '2147483648',
        '99999999999999999999'
      ]) {
        expect(_validDraft.copyWith(totalBeds: text).validate()['totalBeds'],
            'listings.validation.total_beds',
            reason: text);
      }
      expect(_validDraft.validate(occupiedBeds: -1)['totalBeds'],
          'listings.validation.total_beds');
    });

    test('matches text/currency bounds and keeps address optional with a pin',
        () {
      expect(_validDraft.copyWith(title: 'x' * 200).validate(), isEmpty);
      expect(_validDraft.copyWith(title: 'x' * 201).validate()['title'],
          'listings.validation.title');
      expect(
          _validDraft
              .copyWith(description: 'x' * 10001)
              .validate()['description'],
          'listings.validation.description');
      expect(_validDraft.copyWith(address: 'x' * 501).validate()['address'],
          'listings.validation.address');
      for (final currency in ['egp', 'EG', 'EGPP', 'E1P']) {
        expect(_validDraft.copyWith(currency: currency).validate()['currency'],
            'listings.validation.currency');
      }
      expect(_validDraft.copyWith(address: '').validate(requireLocation: true),
          isEmpty);
      final unpinned = _validDraft.copyWith(clearLocation: true);
      expect(unpinned.validate(), isEmpty);
      expect(unpinned.validate(requireLocation: true)['location'],
          'listings.validation.location_required');
      expect(
          _validDraft
              .copyWith(location: const GeoPoint(latitude: 91, longitude: 1))
              .validate()['location'],
          'listings.validation.location');
    });

    test(
        'copyWith preserves a pin unless explicitly cleared and tracks raw edits',
        () {
      expect(_validDraft.copyWith(location: null), _validDraft);
      expect(_validDraft.copyWith(title: 'Other').location, _point);
      expect(_validDraft.copyWith(clearLocation: true).location, isNull);
      expect(_validDraft.copyWith(title: 'Shared home'), isNot(_validDraft));
    });
  });

  group('UniversityRoute', () {
    test('zero is a valid computed distance, with an inclusive 10 km cutoff',
        () {
      for (final distance in [0, 9999.9999999, 10000]) {
        final route = UniversityRoute.fromJson(_routeRow(distance: distance));
        expect(route.distanceMeters, distance.toDouble());
        expect(route.isNearby, isTrue);
        expect(route.calculatedAt, DateTime.parse(_timestamp));
      }
      expect(
          UniversityRoute.fromJson(_routeRow(distance: 10000.0000001)).isNearby,
          isFalse);
    });

    test('no route stays null and needs-pin-review is not a walking estimate',
        () {
      for (final entry in {
        'unroutable': RouteOutcome.unroutable,
        'needs_pin_review': RouteOutcome.needsPinReview,
      }.entries) {
        final route = UniversityRoute.fromJson({
          ..._routeRow(distance: null),
          'status': entry.key,
        });
        expect(route.outcome, entry.value);
        expect(route.distanceMeters, isNull);
        expect(route.isNearby, isFalse);
      }
    });

    test('rejects invalid/missing distances, joins, statuses and timestamps',
        () {
      for (final change in <Map<String, Object?>>[
        {'distance_m': null},
        {'distance_m': -1},
        {'distance_m': double.nan},
        {'distance_m': double.infinity},
        {'distance_m': '12'},
        {'status': 'unroutable'},
        {'status': 'future'},
        {'university': null},
        {'university_id': 2},
        {'university_id': 1.0},
        {'calculated_at': 'yesterday'},
      ]) {
        expect(() => UniversityRoute.fromJson({..._routeRow(), ...change}),
            throwsFormatException,
            reason: '$change');
      }
    });
  });

  group('ListingSearchResult', () {
    test('uses flat published data and keeps exact keyset values', () {
      const distance = 1234.1234567890123;
      final item = ListingSearchResult.fromJson({
        ..._listingRow(),
        'status': 'published',
        'distance_m': distance,
        'university_id': 1,
      });
      final source = [item];
      final page = ListingSearchPage(items: source, hasMore: true);
      source.clear();
      expect(page.items, [item]);
      expect(page.afterDistanceMeters, distance);
      expect(page.afterListingId, _listingId);
      expect(page.hasMore, isTrue);
      expect(() => page.items.clear(), throwsUnsupportedError);
      final empty = ListingSearchPage(items: const [], hasMore: false);
      expect(empty.afterDistanceMeters, isNull);
      expect(empty.afterListingId, isNull);
    });

    test('does not accept private, unpinned, over-distance or invalid results',
        () {
      final row = {
        ..._listingRow(),
        'status': 'published',
        'distance_m': 0,
        'university_id': 1,
      };
      for (final change in <Map<String, Object?>>[
        {'status': 'draft'},
        {'status': 'archived'},
        {'latitude': null, 'longitude': null},
        {'distance_m': null},
        {'distance_m': double.nan},
        {'distance_m': 10000.00001},
        {'university_id': 0},
      ]) {
        expect(() => ListingSearchResult.fromJson({...row, ...change}),
            throwsFormatException);
      }
    });
  });
}
