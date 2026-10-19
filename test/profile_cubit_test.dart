import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zameel/src/data/models/profile_draft.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/ui/profile/profile_cubit.dart';
import 'package:zameel/src/utils/failure.dart';
import 'support/auth_fakes.dart';
import 'support/profile_fakes.dart';

void main() {
  late FakeProfileRepository repository;
  late ProfileCubit cubit;
  setUp(() {
    repository = FakeProfileRepository(student);
    cubit = ProfileCubit(repository: repository, user: student);
  });
  tearDown(() => cubit.close());

  test('draft normalizes editable fields without submitting identity or role',
      () {
    const draft = ProfileDraft(name: ' Student ', phone: ' ', language: 'ar');
    expect(draft.toUpdate(),
        {'full_name': 'Student', 'phone': null, 'preferred_language': 'ar'});
    expect(draft.isValid, isTrue);
    expect(ProfileDraft.validateName(' '), 'profile.name_invalid');
    expect(ProfileDraft.validatePhone('......'), 'profile.phone_invalid');
    expect(ProfileDraft.validatePhone('+20 1234567890'), isNull);
  });

  test('loading or failed load never exposes a writable stale profile',
      () async {
    repository.loadFailure = const NetworkFailure('profile.request_failed');
    await cubit.load();
    cubit.changeDetails(name: 'Should not save');
    await cubit.save();
    await cubit.pickAvatar();
    expect(cubit.state.hasLoaded, isFalse);
    expect(cubit.state.draft.name, student.name);
    expect(repository.saves, 0);
    expect(repository.picks, 0);
    repository.loadFailure = null;
    await cubit.load();
    expect(cubit.state.hasLoaded, isTrue);
  });

  test('typing does not reload profiles or mint more signed URLs', () async {
    final withPhoto = AppUser(
        id: student.id,
        email: student.email,
        name: student.name,
        role: student.role,
        avatarPath: '${student.id}/${'a' * 32}.png');
    repository = FakeProfileRepository(withPhoto);
    await cubit.close();
    cubit = ProfileCubit(repository: repository, user: withPhoto);
    await cubit.load();
    for (var index = 0; index < 100; index++) {
      cubit.changeDetails(name: 'Student $index');
    }
    expect(repository.reads, 1);
    expect(repository.signs, 1);
    expect(repository.saves, 0);
  });

  test('save keeps fields readonly while pending and sends one canonical write',
      () async {
    await cubit.load();
    cubit.changeDetails(
        name: ' New name ', phone: '+20 1234567890', language: 'ar');
    repository.saveGate = Completer<void>();
    final pending = cubit.save();
    await cubit.save();
    cubit.changeDetails(name: 'Too late');
    expect(repository.saves, 1);
    expect(cubit.state.isSaving, isTrue);
    repository.saveGate!.complete();
    await pending;
    expect(cubit.state.profile.name, 'New name');
    expect(cubit.state.profile.preferredLanguage, 'ar');
    expect(cubit.state.isDirty, isFalse);
    expect(cubit.state.savedRevision, 1);
  });

  test('failure or conflict preserves edits and does not announce success',
      () async {
    await cubit.load();
    repository.saveFailure = const ServerFailure('profile.conflict');
    cubit.changeDetails(name: 'Keep this draft');
    await cubit.save();
    expect(cubit.state.draft.name, 'Keep this draft');
    expect(cubit.state.profile.name, student.name);
    expect(cubit.state.savedRevision, 0);
    expect(cubit.state.isDirty, isTrue);
    await cubit.load();
    expect(repository.reads, 1);
    cubit.discard();
    expect(cubit.state.draft.name, student.name);
  });

  test('photo selection is staged, cancel is harmless, discard uploads nothing',
      () async {
    await cubit.load();
    await cubit.pickAvatar();
    expect(cubit.state.isDirty, isFalse);
    repository.pickedBytes = Uint8List.fromList([1, 2, 3]);
    await cubit.pickAvatar();
    expect(cubit.state.avatarChanged, isTrue);
    expect(repository.saves, 0);
    cubit.discard();
    expect(cubit.state.avatarBytes, isNull);
    expect(cubit.state.isDirty, isFalse);
  });

  test(
      'new photo is uploaded once only on save and retained as a stable preview',
      () async {
    await cubit.load();
    repository.pickedBytes = Uint8List.fromList([1, 2, 3]);
    await cubit.pickAvatar();
    await cubit.save();
    expect(repository.uploadedBytes, same(repository.pickedBytes));
    expect(cubit.state.avatarBytes, same(repository.pickedBytes));
    expect(cubit.state.avatarChanged, isFalse);
    expect(repository.signs, 1);
    await cubit.save();
    expect(repository.saves, 1);
  });

  test('photo signing failure is non-blocking for text edits', () async {
    repository.user = AppUser(
        id: student.id,
        email: student.email,
        name: student.name,
        role: student.role,
        avatarPath: '${student.id}/${'a' * 32}.png',
        updatedAt: DateTime.utc(2026));
    repository.signFailure = const NetworkFailure('profile.photo_failed');
    await cubit.load();
    expect(cubit.state.avatarError, isTrue);
    cubit.changeDetails(name: 'Still editable');
    await cubit.save();
    expect(cubit.state.profile.name, 'Still editable');
  });
}
