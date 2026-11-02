import 'package:equatable/equatable.dart';

class GeoPoint extends Equatable {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  factory GeoPoint.fromJson(Map<String, Object?> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (latitude is! num || longitude is! num) {
      throw const FormatException('Invalid coordinate pair');
    }
    final point = GeoPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
    if (!point.isValid) {
      throw const FormatException('Invalid coordinate pair');
    }
    return point;
  }

  @override
  List<Object> get props => [latitude, longitude];
}
