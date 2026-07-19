import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';

enum AccountDeletionField { confirmation, password, finalConfirmation }

enum AccountDeletionFieldIssue {
  required,
  mismatch,
  finalConfirmationRequired,
}

enum AccountDeletionMessage {
  wrongPassword,
  confirmationMismatch,
  reauthenticationRequired,
  retryable,
  offline,
}

class AccountDeletionState {
  const AccountDeletionState({
    this.isSubmitting = false,
    this.fieldErrors = const {},
    this.message,
  });

  final bool isSubmitting;
  final Map<AccountDeletionField, AccountDeletionFieldIssue> fieldErrors;
  final AccountDeletionMessage? message;
}

class AccountDeletionController extends StateNotifier<AccountDeletionState> {
  AccountDeletionController(
    AccountDeletionRepository Function() repository, {
    required bool hasVerifiedUser,
    required void Function() onDeleted,
  })  : _repository = repository,
        _hasVerifiedUser = hasVerifiedUser,
        _onDeleted = onDeleted,
        super(const AccountDeletionState());

  final AccountDeletionRepository Function() _repository;
  final bool _hasVerifiedUser;
  final void Function() _onDeleted;

  void resetFeedback() {
    if (!state.isSubmitting) state = const AccountDeletionState();
  }

  Future<bool> deleteAccount({
    required String email,
    required String expectedConfirmation,
    required String confirmation,
    required String password,
    required bool isFinallyConfirmed,
  }) async {
    if (state.isSubmitting || !_hasVerifiedUser) return false;

    final errors = <AccountDeletionField, AccountDeletionFieldIssue>{};
    if (confirmation.isEmpty) {
      errors[AccountDeletionField.confirmation] =
          AccountDeletionFieldIssue.required;
    } else if (confirmation != expectedConfirmation) {
      errors[AccountDeletionField.confirmation] =
          AccountDeletionFieldIssue.mismatch;
    }
    if (password.isEmpty) {
      errors[AccountDeletionField.password] =
          AccountDeletionFieldIssue.required;
    }
    if (!isFinallyConfirmed) {
      errors[AccountDeletionField.finalConfirmation] =
          AccountDeletionFieldIssue.finalConfirmationRequired;
    }
    if (errors.isNotEmpty) {
      state = AccountDeletionState(fieldErrors: errors);
      return false;
    }

    state = const AccountDeletionState(isSubmitting: true);
    try {
      final repository = _repository();
      await repository.deleteOwnAccount(
        email: email,
        password: password,
        confirmation: confirmation,
      );
      await repository.clearLocalSession();
      if (!mounted) return true;
      state = const AccountDeletionState();
      _onDeleted();
      return true;
    } on AccountDeletionFailure catch (failure) {
      if (mounted) {
        state = AccountDeletionState(message: _message(failure.code));
      }
      return false;
    } catch (_) {
      if (mounted) {
        state = const AccountDeletionState(
          message: AccountDeletionMessage.retryable,
        );
      }
      return false;
    }
  }

  static AccountDeletionMessage _message(AccountDeletionFailureCode code) {
    return switch (code) {
      AccountDeletionFailureCode.wrongPassword =>
        AccountDeletionMessage.wrongPassword,
      AccountDeletionFailureCode.confirmationMismatch =>
        AccountDeletionMessage.confirmationMismatch,
      AccountDeletionFailureCode.reauthenticationRequired =>
        AccountDeletionMessage.reauthenticationRequired,
      AccountDeletionFailureCode.retryable => AccountDeletionMessage.retryable,
      AccountDeletionFailureCode.offline => AccountDeletionMessage.offline,
    };
  }
}
