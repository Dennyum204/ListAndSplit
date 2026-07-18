import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';

enum AuthField { email, password, passwordConfirmation }

enum AuthActionFlow {
  signIn,
  signUp,
  verification,
  forgotPassword,
  passwordRecovery,
  session,
}

enum AuthActionMessage {
  checkInboxToVerify,
  verificationSent,
  passwordResetSent,
  passwordUpdated,
  signInFailed,
  operationFailed,
}

class AuthActionState {
  const AuthActionState({
    this.isSubmitting = false,
    this.fieldErrors = const {},
    this.message,
  });

  final bool isSubmitting;
  final Map<AuthField, AuthValidationIssue> fieldErrors;
  final AuthActionMessage? message;

  AuthActionState copyWith({
    bool? isSubmitting,
    Map<AuthField, AuthValidationIssue>? fieldErrors,
    AuthActionMessage? message,
    bool clearMessage = false,
  }) =>
      AuthActionState(
        isSubmitting: isSubmitting ?? this.isSubmitting,
        fieldErrors: fieldErrors ?? this.fieldErrors,
        message: clearMessage ? null : message ?? this.message,
      );
}

class AuthActionsController extends StateNotifier<AuthActionState> {
  AuthActionsController(
    this._repository, {
    required void Function(String email) onVerificationPending,
    required void Function() onRecoveryCompleted,
    required void Function() onSignedOut,
  })  : _onVerificationPending = onVerificationPending,
        _onRecoveryCompleted = onRecoveryCompleted,
        _onSignedOut = onSignedOut,
        super(const AuthActionState());

  final AuthRepository _repository;
  final void Function(String email) _onVerificationPending;
  final void Function() _onRecoveryCompleted;
  final void Function() _onSignedOut;

  void clearMessage() => state = state.copyWith(clearMessage: true);

  Future<bool> signUp({
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    if (!_setCredentialsValidation(
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
    )) {
      return false;
    }

    final normalizedEmail = AuthValidation.normalizeEmail(email);
    return _run(
      () => _repository.signUp(
        email: normalizedEmail,
        password: password,
      ),
      successMessage: AuthActionMessage.checkInboxToVerify,
      onSuccess: () => _onVerificationPending(normalizedEmail),
    );
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    final errors = <AuthField, AuthValidationIssue>{};
    final emailError = AuthValidation.email(email);
    final passwordError =
        password.isEmpty ? AuthValidationIssue.passwordRequired : null;
    if (emailError != null) errors[AuthField.email] = emailError;
    if (passwordError != null) errors[AuthField.password] = passwordError;
    if (!_beginIfValid(errors)) return false;

    final normalizedEmail = AuthValidation.normalizeEmail(email);
    try {
      await _repository.signIn(email: normalizedEmail, password: password);
      if (mounted) state = const AuthActionState();
      return true;
    } on AuthFailure catch (failure) {
      if (!mounted) return false;
      if (failure.code == AuthFailureCode.verificationRequired) {
        _onVerificationPending(normalizedEmail);
        state = const AuthActionState(
          message: AuthActionMessage.checkInboxToVerify,
        );
      } else {
        state = const AuthActionState(
          message: AuthActionMessage.signInFailed,
        );
      }
      return false;
    } catch (_) {
      if (mounted) {
        state = const AuthActionState(
          message: AuthActionMessage.signInFailed,
        );
      }
      return false;
    }
  }

  Future<bool> resendVerification(String email) {
    final error = AuthValidation.email(email);
    if (error != null) {
      state = AuthActionState(fieldErrors: {AuthField.email: error});
      return Future.value(false);
    }
    return _run(
      () => _repository.resendVerification(
        email: AuthValidation.normalizeEmail(email),
      ),
      successMessage: AuthActionMessage.verificationSent,
    );
  }

  Future<bool> requestPasswordReset(String email) {
    final error = AuthValidation.email(email);
    if (error != null) {
      state = AuthActionState(fieldErrors: {AuthField.email: error});
      return Future.value(false);
    }
    return _run(
      () => _repository.requestPasswordReset(
        email: AuthValidation.normalizeEmail(email),
      ),
      successMessage: AuthActionMessage.passwordResetSent,
    );
  }

  Future<bool> updatePassword({
    required String password,
    required String passwordConfirmation,
  }) async {
    final errors = <AuthField, AuthValidationIssue>{};
    final passwordError = AuthValidation.password(password);
    final confirmationError = AuthValidation.passwordConfirmation(
      password,
      passwordConfirmation,
    );
    if (passwordError != null) errors[AuthField.password] = passwordError;
    if (confirmationError != null) {
      errors[AuthField.passwordConfirmation] = confirmationError;
    }
    if (!_beginIfValid(errors)) return false;

    try {
      await _repository.updatePassword(password: password);
      if (mounted) {
        _onRecoveryCompleted();
        state = const AuthActionState(
          message: AuthActionMessage.passwordUpdated,
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        state = const AuthActionState(
          message: AuthActionMessage.operationFailed,
        );
      }
      return false;
    }
  }

  Future<bool> signOut() async {
    if (state.isSubmitting) return false;
    state = const AuthActionState(isSubmitting: true);
    try {
      await _repository.signOut();
      if (mounted) {
        _onSignedOut();
        state = const AuthActionState();
      }
      return true;
    } catch (_) {
      if (mounted) {
        state = const AuthActionState(
          message: AuthActionMessage.operationFailed,
        );
      }
      return false;
    }
  }

  bool _setCredentialsValidation({
    required String email,
    required String password,
    required String passwordConfirmation,
  }) {
    final errors = <AuthField, AuthValidationIssue>{};
    final emailError = AuthValidation.email(email);
    final passwordError = AuthValidation.password(password);
    final confirmationError = AuthValidation.passwordConfirmation(
      password,
      passwordConfirmation,
    );
    if (emailError != null) errors[AuthField.email] = emailError;
    if (passwordError != null) errors[AuthField.password] = passwordError;
    if (confirmationError != null) {
      errors[AuthField.passwordConfirmation] = confirmationError;
    }
    if (state.isSubmitting) return false;
    if (errors.isNotEmpty) {
      state = AuthActionState(fieldErrors: errors);
      return false;
    }
    return true;
  }

  bool _beginIfValid(Map<AuthField, AuthValidationIssue> errors) {
    if (state.isSubmitting) return false;
    if (errors.isNotEmpty) {
      state = AuthActionState(fieldErrors: errors);
      return false;
    }
    state = const AuthActionState(isSubmitting: true);
    return true;
  }

  Future<bool> _run(
    Future<void> Function() operation, {
    required AuthActionMessage successMessage,
    void Function()? onSuccess,
  }) async {
    if (state.isSubmitting) return false;
    state = const AuthActionState(isSubmitting: true);
    try {
      await operation();
      if (mounted) {
        onSuccess?.call();
        state = AuthActionState(message: successMessage);
      }
      return true;
    } catch (_) {
      if (mounted) {
        state = const AuthActionState(
          message: AuthActionMessage.operationFailed,
        );
      }
      return false;
    }
  }
}

final authActionsControllerProvider = StateNotifierProvider.autoDispose
    .family<AuthActionsController, AuthActionState, AuthActionFlow>(
        (ref, flow) {
  return AuthActionsController(
    ref.watch(authRepositoryProvider),
    onVerificationPending: (email) {
      ref.read(pendingVerificationEmailProvider.notifier).state = email;
    },
    onRecoveryCompleted: () {
      final attempt =
          ref.read(authSessionProvider).valueOrNull?.passwordRecoveryAttempt;
      ref.read(completedPasswordRecoveryAttemptProvider.notifier).state =
          attempt;
    },
    onSignedOut: () {
      ref.read(pendingVerificationEmailProvider.notifier).state = null;
      ref.read(completedPasswordRecoveryAttemptProvider.notifier).state = null;
    },
  );
});
