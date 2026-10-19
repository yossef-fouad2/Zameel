import 'dart:typed_data';
import '../../utils/typedefs.dart';
import '../models/profile_draft.dart';
import '../models/user_model.dart';

abstract class ProfileRepository {
  FutureEither<AppUser> getProfile({required String userId});
  FutureEither<Uint8List?> pickAvatar();
  FutureEither<String> signAvatar(
      {required String userId, required String path});
  FutureEither<AppUser> saveProfile(
      {required AppUser original,
      required ProfileDraft draft,
      Uint8List? avatarBytes,
      bool removeAvatar = false});
}
