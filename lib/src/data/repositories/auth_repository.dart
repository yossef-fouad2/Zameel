import '../models/auth_result.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../../utils/typedefs.dart';

abstract class AuthRepository {
  Stream<AuthSessionChange> get onAuthStateChanged;

  FutureEither<void> login({required String email, required String password});

  FutureEither<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  });

  FutureEither<void> confirmEmail(
      {required String email, required String code});
  FutureEither<void> resendConfirmation({required String email});
  FutureEither<void> forgotPassword({required String email});
  FutureEither<void> verifyRecovery(
      {required String email, required String code});
  FutureEither<void> updatePassword({required String password});
  FutureEither<void> logout();
  FutureEither<AppUser?> checkAuthState();
}
