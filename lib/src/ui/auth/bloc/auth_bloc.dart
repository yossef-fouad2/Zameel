import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/auth_result.dart';
import '../../../data/models/user_role.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../utils/typedefs.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  confirmationRequired,
  recoveryEmailSent,
  codeResent,
  recoveryVerified,
  passwordUpdated,
  failure,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initial,
    this.email = '',
    this.role = UserRole.student,
    this.errorMessage,
  });

  final AuthStatus status;
  final String email;
  final UserRole role;
  final String? errorMessage;
  bool get isLoading => status == AuthStatus.loading;

  @override
  List<Object?> get props => [status, email, role, errorMessage];
}

sealed class AuthEvent {
  const AuthEvent();
}

class LoginRequested extends AuthEvent {
  const LoginRequested({required this.email, required this.password});
  final String email;
  final String password;
}

class SignUpRequested extends AuthEvent {
  const SignUpRequested({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });
  final String name;
  final String email;
  final String password;
  final UserRole role;
}

class ForgotPasswordRequested extends AuthEvent {
  const ForgotPasswordRequested({required this.email});
  final String email;
}

class AuthCodeSubmitted extends AuthEvent {
  const AuthCodeSubmitted(
      {required this.email, required this.code, this.recovery = false});
  final String email;
  final String code;
  final bool recovery;
}

class AuthCodeResendRequested extends AuthEvent {
  const AuthCodeResendRequested({required this.email, this.recovery = false});
  final String email;
  final bool recovery;
}

class PasswordUpdateRequested extends AuthEvent {
  const PasswordUpdateRequested({required this.password});
  final String password;
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    on<AuthEvent>(_onEvent);
  }

  final AuthRepository _repository;

  Future<void> _onEvent(AuthEvent event, Emitter<AuthState> emit) async {
    if (state.isLoading) return;
    emit(const AuthState(status: AuthStatus.loading));

    if (event is SignUpRequested) {
      final result = await _repository.signUp(
        name: event.name.trim(),
        email: event.email.trim(),
        password: event.password,
        role: event.role,
      );
      result.fold(
        (failure) => emit(AuthState(
            status: AuthStatus.failure, errorMessage: failure.message)),
        (outcome) => emit(AuthState(
          status: outcome == SignUpOutcome.confirmationRequired
              ? AuthStatus.confirmationRequired
              : AuthStatus.authenticated,
          email: event.email.trim(),
          role: event.role,
        )),
      );
      return;
    }

    final FutureEither<void> request;
    final AuthStatus success;
    String email = '';
    switch (event) {
      case LoginRequested():
        email = event.email.trim();
        request = _repository.login(email: email, password: event.password);
        success = AuthStatus.authenticated;
      case ForgotPasswordRequested():
        email = event.email.trim();
        request = _repository.forgotPassword(email: email);
        success = AuthStatus.recoveryEmailSent;
      case AuthCodeSubmitted():
        email = event.email.trim();
        request = event.recovery
            ? _repository.verifyRecovery(email: email, code: event.code)
            : _repository.confirmEmail(email: email, code: event.code);
        success = event.recovery
            ? AuthStatus.recoveryVerified
            : AuthStatus.authenticated;
      case AuthCodeResendRequested():
        email = event.email.trim();
        request = event.recovery
            ? _repository.forgotPassword(email: email)
            : _repository.resendConfirmation(email: email);
        success = AuthStatus.codeResent;
      case PasswordUpdateRequested():
        request = _repository.updatePassword(password: event.password);
        success = AuthStatus.passwordUpdated;
      case SignUpRequested():
        return;
    }
    final result = await request;
    result.fold(
      (failure) => emit(AuthState(
        status: event is LoginRequested &&
                failure.message == 'auth_flow.email_not_confirmed'
            ? AuthStatus.confirmationRequired
            : AuthStatus.failure,
        email: email,
        errorMessage: failure.message,
      )),
      (_) => emit(AuthState(status: success, email: email)),
    );
  }
}
