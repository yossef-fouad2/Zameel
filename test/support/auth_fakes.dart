import 'dart:async';
import 'package:fpdart/fpdart.dart';
import 'package:zameel/src/data/models/auth_result.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/models/user_role.dart';
import 'package:zameel/src/data/repositories/auth_repository.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/utils/failure.dart';
import 'package:zameel/src/utils/typedefs.dart';

const student = AppUser(
    id: 'student-1',
    email: 'student@example.com',
    name: 'Student',
    role: UserRole.student);
const landlord = AppUser(
    id: 'landlord-1',
    email: 'landlord@example.com',
    name: 'Landlord',
    role: UserRole.landlord);

class FakeAuthRepository implements AuthRepository {
  final changes = StreamController<AuthSessionChange>.broadcast();
  AppUser? user;
  AppUser loginUser = student;
  Failure? logoutFailure;
  Failure? authFailure;
  SignUpOutcome signUpOutcome = SignUpOutcome.confirmationRequired;
  FutureEither<AppUser?> Function()? onCheck;
  String? lastPassword;
  UserRole? signUpRole;
  int loginCount = 0;
  int passwordUpdates = 0;

  @override
  Stream<AuthSessionChange> get onAuthStateChanged => changes.stream;
  @override
  FutureEither<AppUser?> checkAuthState() =>
      onCheck?.call() ?? Future.value(right(user));
  @override
  FutureEither<void> login(
      {required String email, required String password}) async {
    lastPassword = password;
    loginCount++;
    if (authFailure != null) return left(authFailure!);
    user = loginUser;
    changes.add(AuthSessionChange.refreshed);
    return right(null);
  }

  @override
  FutureEither<SignUpOutcome> signUp(
      {required String name,
      required String email,
      required String password,
      required UserRole role}) async {
    signUpRole = role;
    if (authFailure != null) return left(authFailure!);
    if (signUpOutcome == SignUpOutcome.authenticated) {
      user = role == UserRole.landlord ? landlord : student;
      changes.add(AuthSessionChange.refreshed);
    }
    return right(signUpOutcome);
  }

  @override
  FutureEither<void> confirmEmail(
      {required String email, required String code}) async {
    if (authFailure != null) return left(authFailure!);
    user = loginUser;
    changes.add(AuthSessionChange.refreshed);
    return right(null);
  }

  @override
  FutureEither<void> resendConfirmation({required String email}) async =>
      right(null);
  @override
  FutureEither<void> forgotPassword({required String email}) async =>
      right(null);
  @override
  FutureEither<void> verifyRecovery(
      {required String email, required String code}) async {
    if (authFailure != null) return left(authFailure!);
    user = loginUser;
    changes.add(AuthSessionChange.passwordRecovery);
    return right(null);
  }

  @override
  FutureEither<void> updatePassword({required String password}) async {
    passwordUpdates++;
    changes.add(AuthSessionChange.refreshed);
    return right(null);
  }

  @override
  FutureEither<void> logout() async {
    if (logoutFailure != null) return left(logoutFailure!);
    user = null;
    changes.add(AuthSessionChange.signedOut);
    return right(null);
  }

  Future<void> close() => changes.close();
}

class FakePreferencesRepository implements LifestylePreferencesRepository {
  final values = <String, LifestylePreferences>{};
  Failure? failure;
  @override
  FutureEither<LifestylePreferences?> getPreferences(
          {required String userId}) async =>
      failure != null ? left(failure!) : right(values[userId]);
  @override
  FutureEither<void> savePreferences(
      {required String userId,
      required LifestylePreferences preferences}) async {
    if (failure != null) return left(failure!);
    values[userId] = preferences;
    return right(null);
  }

  @override
  FutureEither<void> deletePreferences({required String userId}) async {
    values.remove(userId);
    return right(null);
  }
}
