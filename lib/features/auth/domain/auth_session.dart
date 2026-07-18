class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.email,
    required this.isEmailVerified,
  });

  final String id;
  final String? email;
  final bool isEmailVerified;
}

class AuthSessionState {
  const AuthSessionState({
    required this.user,
    this.isPasswordRecovery = false,
    this.passwordRecoveryAttempt = 0,
  });

  const AuthSessionState.signedOut()
      : user = null,
        isPasswordRecovery = false,
        passwordRecoveryAttempt = 0;

  final AuthenticatedUser? user;
  final bool isPasswordRecovery;
  final int passwordRecoveryAttempt;

  bool get isAuthenticated => user != null;
}
