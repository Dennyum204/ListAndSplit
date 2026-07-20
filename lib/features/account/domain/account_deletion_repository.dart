enum AccountDeletionFailureCode {
  wrongPassword,
  confirmationMismatch,
  reauthenticationRequired,
  retryable,
  offline,
}

class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.code);

  final AccountDeletionFailureCode code;
}

enum AuthoritativeAccountState {
  valid,
  missing,
  invalidSession,
  transientFailure,
}

abstract interface class AccountDeletionRepository {
  Future<void> deleteOwnAccount({
    required String email,
    required String password,
    required String confirmation,
  });

  Future<AuthoritativeAccountState> validateCurrentAccount();

  Future<void> clearLocalSession();
}
