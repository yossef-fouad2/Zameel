import 'package:equatable/equatable.dart';

import 'geo_point.dart';

enum ListingStatus {
  draft,
  published,
  archived;

  String get value => name;
  String get translationKey => 'listings.status.$value';

  static ListingStatus fromJson(Object? value) => switch (value) {
        'draft' => draft,
        'published' => published,
        'archived' => archived,
        _ => throw const FormatException('Unsupported listing status'),
      };
}

enum PricingUnit {
  perBed('per_bed'),
  perRoom('per_room'),
  perProperty('per_property');

  const PricingUnit(this.value);

  final String value;
  String get translationKey => 'listings.pricing.$value';

  static PricingUnit fromJson(Object? value) => switch (value) {
        'per_bed' => perBed,
        'per_room' => perRoom,
        'per_property' => perProperty,
        _ => throw const FormatException('Unsupported pricing unit'),
      };
}

enum ListingRoomType {
  doubleRoom('double', 2),
  tripleRoom('triple', 3);

  const ListingRoomType(this.value, this.bedsPerRoom);
  final String value;
  final int bedsPerRoom;
  String get translationKey => 'listings.room_types.$value';

  static ListingRoomType fromJson(Object? value) => switch (value) {
        'double' => doubleRoom,
        'triple' => tripleRoom,
        _ => throw const FormatException('Unsupported room type'),
      };
}

/// A bed pool with one monthly per-bed price, not a whole-room booking.
class ListingRoomOption extends Equatable {
  const ListingRoomOption({
    required this.type,
    required this.roomCount,
    required this.monthlyRent,
    required this.occupiedBeds,
  });

  final ListingRoomType type;
  final int roomCount;
  final double monthlyRent;
  final int occupiedBeds;
  int get totalBeds => roomCount * type.bedsPerRoom;
  int get availableBeds => totalBeds - occupiedBeds;

  @override
  List<Object?> get props => [type, roomCount, monthlyRent, occupiedBeds];
}

class Listing extends Equatable {
  const Listing({
    required this.id,
    required this.landlordId,
    required this.title,
    this.description,
    this.address,
    this.location,
    required this.monthlyRent,
    required this.currency,
    required this.pricingUnit,
    required this.totalBeds,
    required this.occupiedBeds,
    required this.availableBeds,
    this.roomOptions = const [],
    required this.status,
    required this.updatedAt,
  });

  static const maxMonthlyRent = 9999999999.99;
  static const maxBeds = 2147483647;
  static const selectFields =
      'id,landlord_id,title,description,address,latitude,longitude,monthly_rent,'
      'currency,pricing_unit,total_bed_capacity,occupied_beds,available_beds,'
      'double_room_count,double_room_monthly_rent,double_room_occupied_beds,'
      'triple_room_count,triple_room_monthly_rent,triple_room_occupied_beds,'
      'status,updated_at';

  final String id;
  final String landlordId;
  final String title;
  final String? description;
  final String? address;
  final GeoPoint? location;
  final double monthlyRent;
  final String currency;
  final PricingUnit pricingUnit;
  final int totalBeds;
  final int occupiedBeds;
  final int availableBeds;
  final List<ListingRoomOption> roomOptions;
  final ListingStatus status;

  bool get hasRoomOptions => roomOptions.isNotEmpty;
  ListingRoomOption? roomOption(ListingRoomType? type) {
    for (final option in roomOptions) {
      if (option.type == type) return option;
    }
    return null;
  }

  String? bookingUnavailableReason(ListingRoomType? roomType) {
    if (pricingUnit != PricingUnit.perBed) {
      return 'bookings.errors.unsupported_unit';
    }
    if (status != ListingStatus.published) return 'bookings.errors.unpublished';
    if (availableBeds <= 0) return 'bookings.errors.full';
    if (hasRoomOptions && roomType == null) {
      return 'bookings.errors.room_type_required';
    }
    if (roomType != null) {
      final option = roomOption(roomType);
      if (option == null) return 'bookings.errors.room_type_unavailable';
      if (option.availableBeds <= 0) return 'bookings.errors.room_type_full';
    }
    return null;
  }

  /// Keep the server's exact timestamp spelling and precision for CAS updates.
  final String updatedAt;

  factory Listing.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final landlordId = json['landlord_id'];
    final title = json['title'];
    final description = json['description'];
    final address = json['address'];
    final rent = json['monthly_rent'];
    final currency = json['currency'];
    final totalBeds = json['total_bed_capacity'];
    final occupiedBeds = json['occupied_beds'];
    final availableBeds = json['available_beds'];
    final updatedAt = json['updated_at'];
    if (id is! String ||
        id.trim().isEmpty ||
        landlordId is! String ||
        landlordId.trim().isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        title.trim().runes.length > 200 ||
        !json.containsKey('description') ||
        (description != null &&
            (description is! String || description.runes.length > 10000)) ||
        !json.containsKey('address') ||
        (address != null &&
            (address is! String ||
                address.trim().isEmpty ||
                address.trim().runes.length > 500)) ||
        !json.containsKey('latitude') ||
        !json.containsKey('longitude') ||
        rent is! num ||
        !rent.isFinite ||
        rent < 0 ||
        rent > maxMonthlyRent ||
        rent.toDouble() != double.parse(rent.toStringAsFixed(2)) ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        totalBeds is! int ||
        totalBeds <= 0 ||
        totalBeds > maxBeds ||
        occupiedBeds is! int ||
        occupiedBeds < 0 ||
        occupiedBeds > totalBeds ||
        availableBeds is! int ||
        availableBeds != totalBeds - occupiedBeds ||
        updatedAt is! String ||
        DateTime.tryParse(updatedAt) == null) {
      throw const FormatException('Invalid listing');
    }
    final pricingUnit = PricingUnit.fromJson(json['pricing_unit']);
    final roomOptions = <ListingRoomOption>[];
    for (final type in ListingRoomType.values) {
      final count = json['${type.value}_room_count'];
      final price = json['${type.value}_room_monthly_rent'];
      final occupied = json['${type.value}_room_occupied_beds'];
      if (count is! int ||
          count < 0 ||
          count > maxBeds ~/ type.bedsPerRoom ||
          !json.containsKey('${type.value}_room_monthly_rent') ||
          (count == 0
              ? price != null
              : price is! num ||
                  !price.isFinite ||
                  price < 0 ||
                  price > maxMonthlyRent ||
                  price.toDouble() != double.parse(price.toStringAsFixed(2))) ||
          occupied is! int ||
          occupied < 0 ||
          occupied > count * type.bedsPerRoom) {
        throw const FormatException('Invalid listing room option');
      }
      if (count > 0) {
        roomOptions.add(ListingRoomOption(
          type: type,
          roomCount: count,
          monthlyRent: (price as num).toDouble(),
          occupiedBeds: occupied,
        ));
      }
    }
    if (roomOptions.isNotEmpty &&
        (pricingUnit != PricingUnit.perBed ||
            totalBeds !=
                roomOptions.fold<int>(0, (sum, o) => sum + o.totalBeds) ||
            occupiedBeds !=
                roomOptions.fold<int>(0, (sum, o) => sum + o.occupiedBeds) ||
            rent !=
                roomOptions
                    .map((o) => o.monthlyRent)
                    .reduce((a, b) => a < b ? a : b))) {
      throw const FormatException('Inconsistent listing room totals');
    }
    final hasLocation = json['latitude'] != null || json['longitude'] != null;
    return Listing(
      id: id,
      landlordId: landlordId,
      title: title,
      description: description as String?,
      address: address as String?,
      location: hasLocation ? GeoPoint.fromJson(json) : null,
      monthlyRent: rent.toDouble(),
      currency: currency,
      pricingUnit: pricingUnit,
      totalBeds: totalBeds,
      occupiedBeds: occupiedBeds,
      availableBeds: availableBeds,
      roomOptions: List.unmodifiable(roomOptions),
      status: ListingStatus.fromJson(json['status']),
      updatedAt: updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        landlordId,
        title,
        description,
        address,
        location,
        monthlyRent,
        currency,
        pricingUnit,
        totalBeds,
        occupiedBeds,
        availableBeds,
        roomOptions,
        status,
        updatedAt,
      ];
}
