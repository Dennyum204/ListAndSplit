import 'package:list_and_split/features/auth/domain/auth_session.dart';

const authCallbackUri = 'com.ferbatech.listandsplit://auth-callback';

enum AuthFailureCode {
  verificationRequired,
  generic,
}

class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;
}

abstract interface class AuthRepository {
  Stream<AuthSessionState> observeSession();

  Future<void> signUp({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> resendVerification({required String email});

  Future<void> requestPasswordReset({required String email});

  Future<void> updatePassword({required String password});
}
