import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeAuthRepository repository;
  late String? pendingEmail;
  late bool recoveryCompleted;
  late bool signedOut;
  late AuthActionsController controller;

  setUp(() {
    repository = FakeAuthRepository();
    pendingEmail = null;
    recoveryCompleted = false;
    signedOut = false;
    controller = AuthActionsController(
      repository,
      onVerificationPending: (email) => pendingEmail = email,
      onRecoveryCompleted: () => recoveryCompleted = true,
      onSignedOut: () => signedOut = true,
    );
  });

  tearDown(() {
    controller.dispose();
    repository.close();
  });

  test('sign-up validates locally and canonicalizes email', () async {
    expect(
      await controller.signUp(
        email: 'bad',
        password: '123',
        passwordConfirmation: 'different',
      ),
      isFalse,
    );
    expect(
      controller.state.fieldErrors[AuthField.email],
      AuthValidationIssue.emailInvalid,
    );
    expect(repository.signUpCalls, 0);

    expect(
      await controller.signUp(
        email: ' Person@Example.COM ',
        password: 'secret',
        passwordConfirmation: 'secret',
      ),
      isTrue,
    );
    expect(repository.lastEmail, 'person@example.com');
    expect(pendingEmail, 'person@example.com');
    expect(controller.state.message, AuthActionMessage.checkInboxToVerify);
  });

  test('loading state prevents duplicate sign-up submission', () async {
    final completer = Completer<void>();
    repository.signUpCompleter = completer;

    final first = controller.signUp(
      email: 'person@example.com',
      password: 'secret',
      passwordConfirmation: 'secret',
    );
    expect(controller.state.isSubmitting, isTrue);

    final second = await controller.signUp(
      email: 'person@example.com',
      password: 'secret',
      passwordConfirmation: 'secret',
    );
    expect(second, isFalse);
    expect(repository.signUpCalls, 1);

    completer.complete();
    expect(await first, isTrue);
  });

  test('sign-in uses a generic failure and routes unverified accounts',
      () async {
    repository.signInFailure = const AuthFailure(AuthFailureCode.generic);
    expect(
      await controller.signIn(
        email: 'person@example.com',
        password: 'secret',
      ),
      isFalse,
    );
    expect(controller.state.message, AuthActionMessage.signInFailed);
    expect(pendingEmail, isNull);

    repository.signInFailure =
        const AuthFailure(AuthFailureCode.verificationRequired);
    expect(
      await controller.signIn(
        email: ' Person@Example.com ',
        password: 'secret',
      ),
      isFalse,
    );
    expect(pendingEmail, 'person@example.com');
    expect(controller.state.message, AuthActionMessage.checkInboxToVerify);
  });

  test('sign-in validates email and requires but does not regrade password',
      () async {
    expect(
      await controller.signIn(email: 'bad', password: ''),
      isFalse,
    );
    expect(
      controller.state.fieldErrors[AuthField.email],
      AuthValidationIssue.emailInvalid,
    );
    expect(
      controller.state.fieldErrors[AuthField.password],
      AuthValidationIssue.passwordRequired,
    );

    expect(
      await controller.signIn(
        email: ' Person@Example.com ',
        password: 'six777',
      ),
      isTrue,
    );
    expect(repository.signInCalls, 1);
    expect(repository.lastEmail, 'person@example.com');
  });

  test('resend and forgot-password results do not reveal account existence',
      () async {
    expect(
      await controller.resendVerification(' Person@Example.com '),
      isTrue,
    );
    expect(controller.state.message, AuthActionMessage.verificationSent);
    expect(repository.lastEmail, 'person@example.com');

    expect(
      await controller.requestPasswordReset(' Nobody@Example.com '),
      isTrue,
    );
    expect(controller.state.message, AuthActionMessage.passwordResetSent);
    expect(repository.lastEmail, 'nobody@example.com');
  });

  test('password recovery validates, updates, and releases recovery routing',
      () async {
    expect(
      await controller.updatePassword(
        password: 'short',
        passwordConfirmation: 'wrong',
      ),
      isFalse,
    );
    expect(recoveryCompleted, isFalse);

    expect(
      await controller.updatePassword(
        password: 'new-password',
        passwordConfirmation: 'new-password',
      ),
      isTrue,
    );
    expect(repository.updatePasswordCalls, 1);
    expect(recoveryCompleted, isTrue);
    expect(controller.state.message, AuthActionMessage.passwordUpdated);
  });

  test('sign-out delegates once and clears navigation state', () async {
    expect(await controller.signOut(), isTrue);
    expect(repository.signOutCalls, 1);
    expect(signedOut, isTrue);
  });
}
