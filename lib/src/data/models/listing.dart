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
    required this.status,
    required this.updatedAt,
  });

  static const maxMonthlyRent = 9999999999.99;
  static const maxBeds = 2147483647;
  static const selectFields =
      'id,landlord_id,title,description,address,latitude,longitude,monthly_rent,'
      'currency,pricing_unit,total_bed_capacity,occupied_beds,available_beds,'
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
  final ListingStatus status;

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
      pricingUnit: PricingUnit.fromJson(json['pricing_unit']),
      totalBeds: totalBeds,
      occupiedBeds: occupiedBeds,
      availableBeds: availableBeds,
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
        status,
        updatedAt,
      ];
}
