import 'package:equatable/equatable.dart';

import 'listing.dart';

class ListingSearchResult extends Equatable {
  const ListingSearchResult({
    required this.listing,
    required this.distanceMeters,
    required this.universityId,
  });

  final Listing listing;
  final double distanceMeters;
  final int universityId;

  factory ListingSearchResult.fromJson(Map<String, Object?> json) {
    final listing = Listing.fromJson(json);
    final distance = json['distance_m'];
    final universityId = json['university_id'];
    if (listing.status != ListingStatus.published ||
        listing.location == null ||
        distance is! num ||
        !distance.isFinite ||
        distance < 0 ||
        distance > 10000 ||
        universityId is! int ||
        universityId <= 0 ||
        universityId > 2147483647) {
      throw const FormatException('Invalid listing search result');
    }
    return ListingSearchResult(
      listing: listing,
      distanceMeters: distance.toDouble(),
      universityId: universityId,
    );
  }

  @override
  List<Object> get props => [listing, distanceMeters, universityId];
}

class ListingSearchPage extends Equatable {
  ListingSearchPage({
    required Iterable<ListingSearchResult> items,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<ListingSearchResult> items;
  final bool hasMore;

  double? get afterDistanceMeters =>
      items.isEmpty ? null : items.last.distanceMeters;
  String? get afterListingId => items.isEmpty ? null : items.last.listing.id;

  @override
  List<Object> get props => [items, hasMore];
}
