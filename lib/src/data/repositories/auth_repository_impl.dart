import '../models/auth_result.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../utils/typedefs.dart';
import 'auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({AuthService? authService})
      : _authService = authService ?? AuthService.instance;

  final AuthService _authService;

  @override
  Stream<AuthSessionChange> get onAuthStateChanged =>
      _authService.authStateChanges;

  @override
  FutureEither<void> login({required String email, required String password}) =>
      _authService.login(email: email, password: password);

  @override
  FutureEither<SignUpOutcome> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) =>
      _authService.signUp(
          name: name, email: email, password: password, role: role);

  @override
  FutureEither<void> confirmEmail(
          {required String email, required String code}) =>
      _authService.confirmEmail(email: email, code: code);

  @override
  FutureEither<void> resendConfirmation({required String email}) =>
      _authService.resendConfirmation(email: email);

  @override
  FutureEither<void> forgotPassword({required String email}) =>
      _authService.forgotPassword(email: email);

  @override
  FutureEither<void> verifyRecovery(
          {required String email, required String code}) =>
      _authService.verifyRecovery(email: email, code: code);

  @override
  FutureEither<void> updatePassword({required String password}) =>
      _authService.updatePassword(password: password);

  @override
  FutureEither<void> logout() => _authService.logout();

  @override
  FutureEither<AppUser?> checkAuthState() => _authService.getCurrentUser();
}
