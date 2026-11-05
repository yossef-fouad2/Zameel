import 'package:equatable/equatable.dart';

import 'geo_point.dart';
import 'listing.dart';

class ListingRoomDraft extends Equatable {
  const ListingRoomDraft({
    required this.type,
    this.roomCount = '',
    this.monthlyRent = '',
  });

  final ListingRoomType type;
  final String roomCount, monthlyRent;

  @override
  List<Object?> get props => [type, roomCount, monthlyRent];
}

class ListingDraft extends Equatable {
  const ListingDraft({
    this.title = '',
    this.description = '',
    this.address = '',
    this.monthlyRent = '',
    this.currency = 'EGP',
    this.pricingUnit = PricingUnit.perBed,
    this.totalBeds = '',
    this.roomOptions = const [],
    this.location,
  });

  factory ListingDraft.fromListing(Listing listing) => ListingDraft(
        title: listing.title,
        description: listing.description ?? '',
        address: listing.address ?? '',
        monthlyRent: listing.monthlyRent.toStringAsFixed(2),
        currency: listing.currency,
        pricingUnit: listing.pricingUnit,
        totalBeds: listing.totalBeds.toString(),
        roomOptions: List.unmodifiable(listing.roomOptions.map((option) =>
            ListingRoomDraft(
                type: option.type,
                roomCount: option.roomCount.toString(),
                monthlyRent: option.monthlyRent.toStringAsFixed(2)))),
        location: listing.location,
      );

  final String title;
  final String description;
  final String address;
  final String monthlyRent;
  final String currency;
  final PricingUnit pricingUnit;
  final String totalBeds;
  final List<ListingRoomDraft> roomOptions;
  final GeoPoint? location;

  bool get hasRoomOptions => roomOptions.isNotEmpty;
  ListingRoomDraft? roomOption(ListingRoomType type) {
    for (final option in roomOptions) {
      if (option.type == type) return option;
    }
    return null;
  }

  int? get roomBedCapacity {
    var total = 0;
    for (final option in roomOptions) {
      final count = int.tryParse(option.roomCount.trim());
      if (count == null ||
          count <= 0 ||
          count > Listing.maxBeds ~/ option.type.bedsPerRoom) {
        return null;
      }
      total += count * option.type.bedsPerRoom;
    }
    return total > 0 && total <= Listing.maxBeds ? total : null;
  }

  ListingDraft copyWith({
    String? title,
    String? description,
    String? address,
    String? monthlyRent,
    String? currency,
    PricingUnit? pricingUnit,
    String? totalBeds,
    List<ListingRoomDraft>? roomOptions,
    GeoPoint? location,
    bool clearLocation = false,
  }) =>
      ListingDraft(
        title: title ?? this.title,
        description: description ?? this.description,
        address: address ?? this.address,
        monthlyRent: monthlyRent ?? this.monthlyRent,
        currency: currency ?? this.currency,
        pricingUnit: pricingUnit ?? this.pricingUnit,
        totalBeds: totalBeds ?? this.totalBeds,
        roomOptions: roomOptions == null
            ? this.roomOptions
            : List.unmodifiable(roomOptions),
        location: clearLocation ? null : location ?? this.location,
      );

  Map<String, String> validate({
    bool requireLocation = false,
    int occupiedBeds = 0,
    List<ListingRoomOption> originalRoomOptions = const [],
  }) {
    final errors = <String, String>{};
    if (title.trim().isEmpty || title.trim().runes.length > 200) {
      errors['title'] = 'listings.validation.title';
    }
    if (description.trim().runes.length > 10000) {
      errors['description'] = 'listings.validation.description';
    }
    if (address.trim().runes.length > 500) {
      errors['address'] = 'listings.validation.address';
    }
    void validateRent(String text, String key) {
      final rentText = text.trim();
      final rent = double.tryParse(rentText);
      if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(rentText) ||
          rent == null ||
          !rent.isFinite ||
          rent < 0 ||
          rent > Listing.maxMonthlyRent) {
        errors[key] = 'listings.validation.monthly_rent';
      }
    }

    if (!hasRoomOptions) validateRent(monthlyRent, 'monthlyRent');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency.trim())) {
      errors['currency'] = 'listings.validation.currency';
    }
    final bedsText =
        hasRoomOptions ? roomBedCapacity?.toString() ?? '' : totalBeds.trim();
    final beds = int.tryParse(bedsText);
    if (!RegExp(r'^[0-9]+$').hasMatch(bedsText) ||
        beds == null ||
        beds <= 0 ||
        beds > Listing.maxBeds ||
        occupiedBeds < 0 ||
        occupiedBeds > Listing.maxBeds) {
      errors[hasRoomOptions ? 'roomOptions' : 'totalBeds'] =
          'listings.validation.total_beds';
    } else if (beds < occupiedBeds) {
      errors[hasRoomOptions ? 'roomOptions' : 'totalBeds'] =
          'listings.validation.occupied_beds';
    }
    if (hasRoomOptions &&
        (pricingUnit != PricingUnit.perBed ||
            roomOptions.map((o) => o.type).toSet().length !=
                roomOptions.length)) {
      errors['roomOptions'] = 'listings.validation.room_options';
    }
    for (final option in roomOptions) {
      final key = option.type.value;
      validateRent(option.monthlyRent, '${key}MonthlyRent');
      final count = int.tryParse(option.roomCount.trim());
      if (!RegExp(r'^[0-9]+$').hasMatch(option.roomCount.trim()) ||
          count == null ||
          count <= 0 ||
          count > Listing.maxBeds ~/ option.type.bedsPerRoom) {
        errors['${key}RoomCount'] = 'listings.validation.room_count';
      } else {
        for (final original in originalRoomOptions) {
          if (original.type == option.type &&
              count * option.type.bedsPerRoom < original.occupiedBeds) {
            errors['${key}RoomCount'] = 'listings.validation.occupied_beds';
          }
        }
      }
    }
    for (final original in originalRoomOptions) {
      if (original.occupiedBeds > 0 && roomOption(original.type) == null) {
        errors['roomOptions'] = 'listings.errors.room_options_locked';
      }
    }
    if (location != null && !location!.isValid) {
      errors['location'] = 'listings.validation.location';
    } else if (requireLocation && location == null) {
      errors['location'] = 'listings.validation.location_required';
    }
    return errors;
  }

  /// Ownership, status, occupancy, availability and timestamps are server-owned.
  Map<String, Object?> toJson() {
    if (validate().isNotEmpty) {
      throw const FormatException('Invalid listing draft');
    }
    return {
      'title': title.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'address': address.trim().isEmpty ? null : address.trim(),
      'latitude': location?.latitude,
      'longitude': location?.longitude,
      'monthly_rent': hasRoomOptions
          ? roomOptions
              .map((o) => double.parse(o.monthlyRent.trim()))
              .reduce((a, b) => a < b ? a : b)
          : double.parse(monthlyRent.trim()),
      'currency': currency.trim(),
      'pricing_unit': pricingUnit.value,
      'total_bed_capacity':
          hasRoomOptions ? roomBedCapacity! : int.parse(totalBeds.trim()),
      for (final type in ListingRoomType.values) ...{
        '${type.value}_room_count': roomOption(type) == null
            ? 0
            : int.parse(roomOption(type)!.roomCount.trim()),
        '${type.value}_room_monthly_rent': roomOption(type) == null
            ? null
            : double.parse(roomOption(type)!.monthlyRent.trim()),
      },
    };
  }

  @override
  List<Object?> get props => [
        title,
        description,
        address,
        monthlyRent,
        currency,
        pricingUnit,
        totalBeds,
        roomOptions,
        location,
      ];
}
