import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_controller.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeAccountDeletionRepository repository;
  late int resetCalls;
  late AccountDeletionController controller;

  setUp(() {
    repository = FakeAccountDeletionRepository();
    resetCalls = 0;
    controller = AccountDeletionController(
      () => repository,
      hasVerifiedUser: true,
      onDeleted: () => resetCalls += 1,
    );
  });

  tearDown(() {
    if (controller.mounted) controller.dispose();
  });

  test('completed profile accepts the exact canonical username', () async {
    expect(
      await _delete(
        controller,
        expectedConfirmation: 'exact_name',
        confirmation: 'exact_name',
      ),
      isTrue,
    );
    expect(repository.lastConfirmation, 'exact_name');
  });

  test('incomplete profile accepts the exact Auth email', () async {
    expect(
      await _delete(
        controller,
        email: 'Exact.Person@example.com',
        expectedConfirmation: 'Exact.Person@example.com',
        confirmation: 'Exact.Person@example.com',
      ),
      isTrue,
    );
    expect(repository.lastEmail, 'Exact.Person@example.com');
    expect(repository.lastConfirmation, 'Exact.Person@example.com');
  });

  for (final confirmation in ['Exact_Name', 'exact_name ', ' exact_name']) {
    test('rejects non-exact confirmation "$confirmation" locally', () async {
      expect(
        await _delete(
          controller,
          expectedConfirmation: 'exact_name',
          confirmation: confirmation,
        ),
        isFalse,
      );
      expect(repository.deletionCalls, 0);
      expect(
        controller.state.fieldErrors[AccountDeletionField.confirmation],
        AccountDeletionFieldIssue.mismatch,
      );
    });
  }

  test('forwards password unchanged without storing it in state', () async {
    expect(
      await _delete(controller, password: ' Pass Word '),
      isTrue,
    );
    expect(repository.lastPassword, ' Pass Word ');
    expect(controller.state.toString(), isNot(contains('Pass Word')));
  });

  test('requires confirmation, password and final acknowledgement', () async {
    expect(
      await controller.deleteAccount(
        email: 'person@example.com',
        expectedConfirmation: 'exact_name',
        confirmation: '',
        password: '',
        isFinallyConfirmed: false,
      ),
      isFalse,
    );
    expect(
      controller.state.fieldErrors,
      {
        AccountDeletionField.confirmation: AccountDeletionFieldIssue.required,
        AccountDeletionField.password: AccountDeletionFieldIssue.required,
        AccountDeletionField.finalConfirmation:
            AccountDeletionFieldIssue.finalConfirmationRequired,
      },
    );
  });

  test('guards rapid duplicate submissions', () async {
    final completer = Completer<void>();
    repository.deletionCompleter = completer;

    final first = _delete(controller);
    expect(controller.state.isSubmitting, isTrue);
    expect(await _delete(controller), isFalse);
    expect(repository.deletionCalls, 1);

    completer.complete();
    expect(await first, isTrue);
    expect(repository.clearSessionCalls, 1);
  });

  test('success clears local state and session-scoped providers', () async {
    expect(await _delete(controller), isTrue);
    expect(repository.clearSessionCalls, 1);
    expect(resetCalls, 1);
    expect(controller.state.isSubmitting, isFalse);
  });

  test('server failure retains the account and supports retry', () async {
    repository.deletionFailure = const AccountDeletionFailure(
      AccountDeletionFailureCode.retryable,
    );

    expect(await _delete(controller), isFalse);
    expect(repository.clearSessionCalls, 0);
    expect(resetCalls, 0);
    expect(controller.state.message, AccountDeletionMessage.retryable);

    repository.deletionFailure = null;
    expect(await _delete(controller), isTrue);
    expect(repository.deletionCalls, 2);
  });

  test('offline reconciliation never clears a valid local session', () async {
    repository.deletionFailure = const AccountDeletionFailure(
      AccountDeletionFailureCode.offline,
    );

    expect(await _delete(controller), isFalse);
    expect(repository.clearSessionCalls, 0);
    expect(controller.state.message, AccountDeletionMessage.offline);
  });

  test('does not invoke deletion without a verified user', () async {
    controller.dispose();
    controller = AccountDeletionController(
      () => repository,
      hasVerifiedUser: false,
      onDeleted: () => resetCalls += 1,
    );

    expect(await _delete(controller), isFalse);
    expect(repository.deletionCalls, 0);
  });
}

Future<bool> _delete(
  AccountDeletionController controller, {
  String email = 'person@example.com',
  String expectedConfirmation = 'exact_name',
  String confirmation = 'exact_name',
  String password = 'password',
}) {
  return controller.deleteAccount(
    email: email,
    expectedConfirmation: expectedConfirmation,
    confirmation: confirmation,
    password: password,
    isFinallyConfirmed: true,
  );
}
