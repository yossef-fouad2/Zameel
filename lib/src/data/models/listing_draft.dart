import 'package:equatable/equatable.dart';

import 'geo_point.dart';
import 'listing.dart';

class ListingDraft extends Equatable {
  const ListingDraft({
    this.title = '',
    this.description = '',
    this.address = '',
    this.monthlyRent = '',
    this.currency = 'EGP',
    this.pricingUnit = PricingUnit.perBed,
    this.totalBeds = '',
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
        location: listing.location,
      );

  final String title;
  final String description;
  final String address;
  final String monthlyRent;
  final String currency;
  final PricingUnit pricingUnit;
  final String totalBeds;
  final GeoPoint? location;

  ListingDraft copyWith({
    String? title,
    String? description,
    String? address,
    String? monthlyRent,
    String? currency,
    PricingUnit? pricingUnit,
    String? totalBeds,
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
        location: clearLocation ? null : location ?? this.location,
      );

  Map<String, String> validate({
    bool requireLocation = false,
    int occupiedBeds = 0,
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
    final rentText = monthlyRent.trim();
    final rent = double.tryParse(rentText);
    if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(rentText) ||
        rent == null ||
        !rent.isFinite ||
        rent < 0 ||
        rent > Listing.maxMonthlyRent) {
      errors['monthlyRent'] = 'listings.validation.monthly_rent';
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency.trim())) {
      errors['currency'] = 'listings.validation.currency';
    }
    final bedsText = totalBeds.trim();
    final beds = int.tryParse(bedsText);
    if (!RegExp(r'^[0-9]+$').hasMatch(bedsText) ||
        beds == null ||
        beds <= 0 ||
        beds > Listing.maxBeds ||
        occupiedBeds < 0 ||
        occupiedBeds > Listing.maxBeds) {
      errors['totalBeds'] = 'listings.validation.total_beds';
    } else if (beds < occupiedBeds) {
      errors['totalBeds'] = 'listings.validation.occupied_beds';
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
      'monthly_rent': double.parse(monthlyRent.trim()),
      'currency': currency.trim(),
      'pricing_unit': pricingUnit.value,
      'total_bed_capacity': int.parse(totalBeds.trim()),
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
        location,
      ];
}
