import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/profile_draft.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/profile_repository.dart';

class ProfileState extends Equatable {
  const ProfileState(
      {required this.profile,
      required this.draft,
      this.isLoading = true,
      this.hasLoaded = false,
      this.isSaving = false,
      this.isPicking = false,
      this.avatarChanged = false,
      this.removeAvatar = false,
      this.avatarBytes,
      this.avatarUrl,
      this.errorMessage,
      this.avatarError = false,
      this.savedRevision = 0});

  final AppUser profile;
  final ProfileDraft draft;
  final bool isLoading,
      hasLoaded,
      isSaving,
      isPicking,
      avatarChanged,
      removeAvatar,
      avatarError;
  final Uint8List? avatarBytes;
  final String? avatarUrl, errorMessage;
  final int savedRevision;
  bool get isBusy => isSaving || isPicking;
  bool get isDirty => avatarChanged || draft != ProfileDraft.fromUser(profile);
  bool get canSave =>
      hasLoaded && !isLoading && !isBusy && isDirty && draft.isValid;

  ProfileState copyWith(
          {AppUser? profile,
          ProfileDraft? draft,
          bool? isLoading,
          bool? hasLoaded,
          bool? isSaving,
          bool? isPicking,
          bool? avatarChanged,
          bool? removeAvatar,
          bool? avatarError,
          int? savedRevision,
          Object? avatarBytes = _unchanged,
          Object? avatarUrl = _unchanged,
          Object? errorMessage = _unchanged}) =>
      ProfileState(
        profile: profile ?? this.profile,
        draft: draft ?? this.draft,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        isPicking: isPicking ?? this.isPicking,
        avatarChanged: avatarChanged ?? this.avatarChanged,
        removeAvatar: removeAvatar ?? this.removeAvatar,
        avatarError: avatarError ?? this.avatarError,
        savedRevision: savedRevision ?? this.savedRevision,
        avatarBytes: identical(avatarBytes, _unchanged)
            ? this.avatarBytes
            : avatarBytes as Uint8List?,
        avatarUrl: identical(avatarUrl, _unchanged)
            ? this.avatarUrl
            : avatarUrl as String?,
        errorMessage: identical(errorMessage, _unchanged)
            ? this.errorMessage
            : errorMessage as String?,
      );
  static const _unchanged = Object();
  @override
  List<Object?> get props => [
        profile,
        draft,
        isLoading,
        hasLoaded,
        isSaving,
        isPicking,
        avatarChanged,
        removeAvatar,
        avatarBytes,
        avatarUrl,
        errorMessage,
        avatarError,
        savedRevision
      ];
}

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({required ProfileRepository repository, required AppUser user})
      : _repository = repository,
        _userId = user.id,
        super(ProfileState(profile: user, draft: ProfileDraft.fromUser(user)));
  final ProfileRepository _repository;
  final String _userId;
  int _generation = 0;

  Future<void> load({bool discard = false}) async {
    if (state.isBusy || (state.isDirty && !discard)) return;
    final generation = ++_generation;
    emit(state.copyWith(isLoading: true, hasLoaded: false, errorMessage: null));
    final result = await _repository.getProfile(userId: _userId);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
      (user) => emit(ProfileState(
          profile: user,
          draft: ProfileDraft.fromUser(user),
          isLoading: false,
          hasLoaded: true)),
    );
    if (result.isRight()) await _loadAvatar(generation);
  }

  void changeDetails({String? name, String? phone, String? language}) {
    if (state.isBusy || state.isLoading || !state.hasLoaded) return;
    emit(state.copyWith(
        draft: state.draft
            .copyWith(name: name, phone: phone, language: language)));
  }

  Future<void> pickAvatar() async {
    if (state.isLoading || state.isBusy || !state.hasLoaded) return;
    emit(state.copyWith(isPicking: true, errorMessage: null));
    final result = await _repository.pickAvatar();
    if (isClosed) return;
    result.fold(
      (failure) =>
          emit(state.copyWith(isPicking: false, errorMessage: failure.message)),
      (bytes) => emit(bytes == null
          ? state.copyWith(isPicking: false)
          : state.copyWith(
              isPicking: false,
              avatarBytes: bytes,
              avatarChanged: true,
              removeAvatar: false)),
    );
  }

  void removePhoto() {
    if (state.isLoading || state.isBusy || !state.hasLoaded) return;
    emit(state.copyWith(
        avatarBytes: null,
        removeAvatar: true,
        avatarChanged: state.profile.avatarPath != null,
        errorMessage: null));
  }

  void discard() {
    if (state.isBusy) return;
    emit(state.copyWith(
        draft: ProfileDraft.fromUser(state.profile),
        avatarBytes: null,
        avatarChanged: false,
        removeAvatar: false,
        errorMessage: null));
  }

  Future<void> save() async {
    if (!state.canSave) return;
    final generation = ++_generation;
    final snapshot = state;
    emit(state.copyWith(isSaving: true, errorMessage: null));
    final result = await _repository.saveProfile(
        original: snapshot.profile,
        draft: snapshot.draft,
        avatarBytes: snapshot.avatarChanged ? snapshot.avatarBytes : null,
        removeAvatar: snapshot.avatarChanged && snapshot.removeAvatar);
    if (isClosed || generation != _generation) return;
    result.fold(
      (failure) =>
          emit(state.copyWith(isSaving: false, errorMessage: failure.message)),
      (user) => emit(state.copyWith(
          profile: user,
          draft: ProfileDraft.fromUser(user),
          isSaving: false,
          avatarChanged: false,
          removeAvatar: false,
          avatarUrl: user.avatarPath == snapshot.profile.avatarPath
              ? state.avatarUrl
              : null,
          avatarError: false,
          savedRevision: state.savedRevision + 1)),
    );
    if (result.isRight() &&
        state.profile.avatarPath != snapshot.profile.avatarPath) {
      await _loadAvatar(generation);
    }
  }

  Future<void> retryAvatar() => _loadAvatar(_generation);

  Future<void> _loadAvatar(int generation) async {
    final path = state.profile.avatarPath;
    if (path == null) return;
    final result = await _repository.signAvatar(userId: _userId, path: path);
    if (isClosed ||
        generation != _generation ||
        state.profile.avatarPath != path) {
      return;
    }
    result.fold(
      (_) => emit(state.copyWith(avatarError: true)),
      (url) => emit(state.copyWith(avatarUrl: url, avatarError: false)),
    );
  }
}
