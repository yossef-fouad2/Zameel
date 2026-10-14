import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

import 'package:zameel/src/data/models/user_model.dart';
import 'package:zameel/src/data/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthService _authService = AuthService.instance;

  @override
  Stream<AppUser?> get onAuthStateChanged {
    return _authService.authStateChanges.map((userData) {
      if (userData == null) return null;
      return AppUser(
        id: userData['id'] ?? '',
        email: userData['email'] ?? '',
        name: userData['name'],
        photoUrl: userData['photoUrl'],
        role: userData['role'] != null
            ? UserRole.values.firstWhere(
                (e) => e.name == userData['role'],
                orElse: () => UserRole.student,
              )
            : null,
      );
    });
  }

  @override
  FutureEither<AppUser> login({
    required String email,
    required String password,
  }) async {
    final result = await _authService.login(email: email, password: password);

    return result.flatMap((userData) {
      if (userData == null) {
        return left(const ServerFailure('Login failed: User record not found'));
      }

      final user = AppUser(
        id: userData['id'],
        email: userData['email'] ?? email,
        name: userData['name'],
        photoUrl: userData['photoUrl'],
        role: userData['role'] != null
            ? UserRole.values.firstWhere(
                (e) => e.name == userData['role'],
                orElse: () => UserRole.student,
              )
            : null,
      );

      return right(user);
    });
  }

  @override
  FutureEither<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final result = await _authService.signUp(
      name: name,
      email: email,
      password: password,
      role: role,
    );

    return result.flatMap((userData) {
      if (userData == null) {
        return left(
            const ServerFailure('Sign up failed: User record corrupted'));
      }

      final user = AppUser(
        id: userData['id'],
        email: userData['email'] ?? email,
        name: name,
        role: role,
      );

      return right(user);
    });
  }

  @override
  FutureEither<void> forgotPassword({required String email}) {
    return _authService.forgotPassword(email: email);
  }

  @override
  FutureEither<void> logout() {
    return _authService.logout();
  }

  @override
  FutureEither<AppUser?> checkAuthState() async {
    final result = await _authService.getCurrentUser();

    return result.map((userData) {
      if (userData == null) return null;

      return AppUser(
        id: userData['id'],
        email: userData['email'] ?? '',
        name: userData['name'],
        photoUrl: userData['photoUrl'],
        role: userData['role'] != null
            ? UserRole.values.firstWhere(
                (e) => e.name == userData['role'],
                orElse: () => UserRole.student,
              )
            : null,
      );
    });
  }
}
