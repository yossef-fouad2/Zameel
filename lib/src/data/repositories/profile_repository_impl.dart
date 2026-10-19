import 'dart:typed_data';
import '../../services/media_service.dart';
import '../../services/profile_service.dart';
import '../../utils/typedefs.dart';
import '../models/profile_draft.dart';
import '../models/user_model.dart';
import 'profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({ProfileService? service, MediaService? media})
      : _service = service ?? ProfileService.instance,
        _media = media ?? MediaService.instance;
  final ProfileService _service;
  final MediaService _media;

  @override
  FutureEither<AppUser> getProfile({required String userId}) =>
      _service.getProfile(userId: userId);
  @override
  FutureEither<Uint8List?> pickAvatar() => _media.pickAvatar();
  @override
  FutureEither<String> signAvatar(
          {required String userId, required String path}) =>
      _service.signAvatar(userId: userId, path: path);
  @override
  FutureEither<AppUser> saveProfile(
          {required AppUser original,
          required ProfileDraft draft,
          Uint8List? avatarBytes,
          bool removeAvatar = false}) =>
      _service.saveProfile(
          original: original,
          draft: draft,
          avatarBytes: avatarBytes,
          removeAvatar: removeAvatar);
}
