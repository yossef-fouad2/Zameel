import 'package:equatable/equatable.dart';

import 'university.dart';

enum RouteOutcome {
  ready,
  unroutable,
  needsPinReview;

  static RouteOutcome fromJson(Object? value) => switch (value) {
        'ready' => ready,
        'unroutable' => unroutable,
        'needs_pin_review' => needsPinReview,
        _ => throw const FormatException('Unsupported route outcome'),
      };
}

class UniversityRoute extends Equatable {
  const UniversityRoute({
    required this.university,
    required this.outcome,
    this.distanceMeters,
    required this.calculatedAt,
  });

  final University university;
  final RouteOutcome outcome;
  final double? distanceMeters;
  final DateTime calculatedAt;

  bool get isNearby =>
      outcome == RouteOutcome.ready &&
      distanceMeters != null &&
      distanceMeters!.isFinite &&
      distanceMeters! >= 0 &&
      distanceMeters! <= 10000;

  factory UniversityRoute.fromJson(Map<String, Object?> json) {
    final universityJson = json['university'];
    final distance = json['distance_m'];
    final calculatedAt = json['calculated_at'];
    final outcome = RouteOutcome.fromJson(json['status']);
    if (universityJson is! Map<String, Object?> ||
        !json.containsKey('distance_m') ||
        (outcome == RouteOutcome.ready
            ? distance is! num || !distance.isFinite || distance < 0
            : distance != null) ||
        calculatedAt is! String ||
        DateTime.tryParse(calculatedAt) == null) {
      throw const FormatException('Invalid university route');
    }
    final university = University.fromJson(universityJson);
    if (json['university_id'] is! int ||
        json['university_id'] != university.id ||
        !university.isActive) {
      throw const FormatException('Invalid route university');
    }
    return UniversityRoute(
      university: university,
      outcome: outcome,
      distanceMeters: (distance as num?)?.toDouble(),
      calculatedAt: DateTime.parse(calculatedAt).toUtc(),
    );
  }

  @override
  List<Object?> get props =>
      [university, outcome, distanceMeters, calculatedAt];
}
