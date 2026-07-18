import 'dart:async';

import 'package:list_and_split/features/auth/data/password_recovery_marker.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client,
    PasswordRecoveryMarker recoveryMarker, {
    Stream<AuthState>? authStateChanges,
  })  : _authStateChanges = authStateChanges ?? _client.auth.onAuthStateChange,
        _recovery = PasswordRecoveryLifecycle(recoveryMarker);

  final SupabaseClient _client;
  final Stream<AuthState> _authStateChanges;
  final PasswordRecoveryLifecycle _recovery;

  @override
  Stream<AuthSessionState> observeSession() async* {
    await for (final authState in _resilientAuthStateChanges()) {
      await _recovery.handle(_mapSessionEvent(authState.event));

      final user = authState.session?.user;
      yield AuthSessionState(
        user: user == null
            ? null
            : AuthenticatedUser(
                id: user.id,
                email: user.email,
                isEmailVerified: user.emailConfirmedAt != null,
              ),
        isPasswordRecovery: user != null && _recovery.isPending,
        passwordRecoveryAttempt: _recovery.attempt,
      );
    }
  }

  Stream<AuthState> _resilientAuthStateChanges() {
    AuthState? lastState;
    return _authStateChanges.transform(
      StreamTransformer<AuthState, AuthState>.fromHandlers(
        handleData: (state, sink) {
          lastState = state;
          sink.add(state);
        },
        handleError: (error, stackTrace, sink) {
          sink.add(
            AuthState(
              AuthChangeEvent.tokenRefreshed,
              lastState?.session ?? _client.auth.currentSession,
            ),
          );
        },
      ),
    );
  }

  @override
  Future<void> signUp({required String email, required String password}) =>
      _protect(
        () => _client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: authCallbackUri,
        ),
      );

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      await _recovery.handle(PasswordRecoverySessionEvent.signedIn);
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        throw const AuthFailure(AuthFailureCode.verificationRequired);
      }
      throw const AuthFailure(AuthFailureCode.generic);
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.generic);
    }
  }

  @override
  Future<void> signOut() async {
    await _protect(_client.auth.signOut);
    await _recovery.handle(PasswordRecoverySessionEvent.signedOut);
  }

  @override
  Future<void> resendVerification({required String email}) => _protect(
        () => _client.auth.resend(
          email: email,
          type: OtpType.signup,
          emailRedirectTo: authCallbackUri,
        ),
      );

  @override
  Future<void> requestPasswordReset({required String email}) => _protect(
        () => _client.auth.resetPasswordForEmail(
          email,
          redirectTo: authCallbackUri,
        ),
      );

  @override
  Future<void> updatePassword({required String password}) async {
    await _protect(
      () => _client.auth.updateUser(UserAttributes(password: password)),
    );
    await _recovery.complete();
  }

  Future<void> _protect(Future<dynamic> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      throw const AuthFailure(AuthFailureCode.generic);
    }
  }

  PasswordRecoverySessionEvent _mapSessionEvent(AuthChangeEvent event) {
    return switch (event) {
      AuthChangeEvent.initialSession =>
        PasswordRecoverySessionEvent.initialSession,
      AuthChangeEvent.passwordRecovery =>
        PasswordRecoverySessionEvent.passwordRecovery,
      AuthChangeEvent.signedIn => PasswordRecoverySessionEvent.signedIn,
      AuthChangeEvent.signedOut => PasswordRecoverySessionEvent.signedOut,
      AuthChangeEvent.tokenRefreshed =>
        PasswordRecoverySessionEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated => PasswordRecoverySessionEvent.userUpdated,
      _ => PasswordRecoverySessionEvent.other,
    };
  }
}
