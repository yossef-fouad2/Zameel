import 'package:equatable/equatable.dart';
import 'user_role.dart';

class AppUser extends Equatable {
  final String id;
  final String email;
  final String? name;
  final String? photoUrl;
  final UserRole? role;

  const AppUser(
      {required this.id,
      required this.email,
      this.name,
      this.photoUrl,
      this.role});

  factory AppUser.empty() => const AppUser(id: '', email: '');

  /// Authorization comes from the protected profile, never user metadata.
  factory AppUser.fromProfile({
    required String id,
    required String email,
    required Map<String, dynamic> profile,
  }) {
    final role = switch (profile['role']) {
      'student' => UserRole.student,
      'landlord' => UserRole.landlord,
      _ => throw const FormatException('Invalid profile role'),
    };
    if (profile['id'] != id) {
      throw const FormatException('Profile does not belong to this session');
    }
    return AppUser(
      id: id,
      email: email,
      name: profile['full_name'] as String?,
      photoUrl: profile['avatar_url'] as String?,
      role: role,
    );
  }

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => id.isNotEmpty;

  @override
  List<Object?> get props => [id, email, name, photoUrl, role];
}
