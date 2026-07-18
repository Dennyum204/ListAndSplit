import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';

void main() {
  test('mobile auth callback stays aligned with platform registration', () {
    expect(
      authCallbackUri,
      'com.ferbatech.listandsplit://auth-callback',
    );
  });

  group('AuthValidation', () {
    test('normalizes email without exposing account existence', () {
      expect(
        AuthValidation.normalizeEmail('  Person@Example.COM '),
        'person@example.com',
      );
      expect(
        AuthValidation.email('not-an-email'),
        AuthValidationIssue.emailInvalid,
      );
    });

    test('uses the configured six-character minimum for new passwords', () {
      expect(
        AuthValidation.password('12345'),
        AuthValidationIssue.passwordTooShort,
      );
      expect(AuthValidation.password('123456'), isNull);
    });

    test('requires matching password confirmation', () {
      expect(
        AuthValidation.passwordConfirmation('secret', 'different'),
        AuthValidationIssue.passwordsDoNotMatch,
      );
    });
  });
}
