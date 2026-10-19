import 'dart:async';
import 'dart:typed_data';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/profile_draft.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/repositories/profile_repository.dart';
import 'package:zameel/src/utils/failure.dart';
import 'package:zameel/src/utils/typedefs.dart';

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(AppUser initial)
      : user = AppUser(
          id: initial.id,
          email: initial.email,
          name: initial.name,
          role: initial.role,
          phone: initial.phone,
          preferredLanguage: initial.preferredLanguage,
          avatarPath: initial.avatarPath,
          updatedAt: initial.updatedAt ?? DateTime.utc(2026, 10, 16),
        );
  AppUser user;
  Uint8List? pickedBytes, uploadedBytes;
  bool removed = false;
  Failure? loadFailure, saveFailure, pickFailure, signFailure;
  Completer<void>? saveGate, loadGate, pickGate;
  int reads = 0, saves = 0, signs = 0, picks = 0;
  ProfileDraft? submitted;

  @override
  FutureEither<AppUser> getProfile({required String userId}) async {
    reads++;
    await loadGate?.future;
    return loadFailure == null ? right(user) : left(loadFailure!);
  }

  @override
  FutureEither<Uint8List?> pickAvatar() async {
    picks++;
    await pickGate?.future;
    return pickFailure == null ? right(pickedBytes) : left(pickFailure!);
  }

  @override
  FutureEither<String> signAvatar(
      {required String userId, required String path}) async {
    signs++;
    return signFailure == null
        ? right('https://example.com/private-avatar.png?token=test')
        : left(signFailure!);
  }

  @override
  FutureEither<AppUser> saveProfile(
      {required AppUser original,
      required ProfileDraft draft,
      Uint8List? avatarBytes,
      bool removeAvatar = false}) async {
    saves++;
    submitted = draft;
    uploadedBytes = avatarBytes;
    removed = removeAvatar;
    await saveGate?.future;
    if (saveFailure != null) return left(saveFailure!);
    user = AppUser(
        id: user.id,
        email: user.email,
        role: user.role,
        name: draft.name.trim(),
        phone: draft.phone.trim().isEmpty ? null : draft.phone.trim(),
        preferredLanguage: draft.language,
        avatarPath: removeAvatar
            ? null
            : avatarBytes != null
                ? '${user.id}/${'a' * 32}.png'
                : user.avatarPath,
        updatedAt: user.updatedAt!.add(const Duration(microseconds: 1)));
    return right(user);
  }
}
