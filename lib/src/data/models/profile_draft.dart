import 'package:equatable/equatable.dart';
import 'user_model.dart';

/// Only user-editable fields belong here; role and email are never submitted.
class ProfileDraft extends Equatable {
  const ProfileDraft(
      {required this.name, required this.phone, required this.language});
  factory ProfileDraft.fromUser(AppUser user) => ProfileDraft(
        name: user.name ?? '',
        phone: user.phone ?? '',
        language: user.preferredLanguage,
      );

  final String name;
  final String phone;
  final String language;

  ProfileDraft copyWith({String? name, String? phone, String? language}) =>
      ProfileDraft(
          name: name ?? this.name,
          phone: phone ?? this.phone,
          language: language ?? this.language);

  static String? validateName(String value) =>
      value.trim().isEmpty || value.trim().length > 200
          ? 'profile.name_invalid'
          : null;
  static String? validatePhone(String value) {
    final phone = value.trim();
    if (phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '').length;
    return digits < 6 ||
            digits > 15 ||
            !RegExp(r'^\+?[0-9() .\-]{6,39}$').hasMatch(phone)
        ? 'profile.phone_invalid'
        : null;
  }

  String? get nameError => validateName(name);
  String? get phoneError => validatePhone(phone);
  bool get isValid =>
      nameError == null &&
      phoneError == null &&
      const ['en', 'ar'].contains(language);

  Map<String, Object?> toUpdate() => {
        'full_name': name.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'preferred_language': language,
      };

  @override
  List<Object> get props => [name.trim(), phone.trim(), language];
}
