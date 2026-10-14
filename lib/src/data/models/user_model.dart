import 'package:equatable/equatable.dart';
import 'user_role.dart';

class AppUser extends Equatable {
  final String id;
  final String email;
  final String? name;
  final String? photoUrl;
  final UserRole? role; // ← ADD THIS

  const AppUser(
      {required this.id,
      required this.email,
      this.name,
      this.photoUrl,
      this.role});

  factory AppUser.empty() => const AppUser(id: '', email: '');

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => id.isNotEmpty;

  @override
  List<Object?> get props => [id, email, name, photoUrl, role];
}
