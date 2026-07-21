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

class AccountDeletionListImpact {
  const AccountDeletionListImpact({
    required this.ownedSharedListCount,
    required this.affectedParticipantCount,
  });

  final int ownedSharedListCount;
  final int affectedParticipantCount;
}

abstract interface class AccountDeletionImpactRepository {
  Future<AccountDeletionListImpact> getListImpact();
}
