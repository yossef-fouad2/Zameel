import 'package:equatable/equatable.dart';

import 'geo_point.dart';

class University extends Equatable {
  const University({
    required this.id,
    required this.name,
    required this.city,
    required this.location,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String city;
  final GeoPoint location;
  final bool isActive;

  factory University.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final city = json['city'];
    final isActive = json['is_active'];
    if (id is! int ||
        id <= 0 ||
        id > 2147483647 ||
        name is! String ||
        name.trim().isEmpty ||
        city is! String ||
        city.trim().isEmpty ||
        isActive is! bool) {
      throw const FormatException('Invalid university');
    }
    return University(
      id: id,
      name: name,
      city: city,
      location: GeoPoint.fromJson(json),
      isActive: isActive,
    );
  }

  @override
  List<Object> get props => [id, name, city, location, isActive];
}
