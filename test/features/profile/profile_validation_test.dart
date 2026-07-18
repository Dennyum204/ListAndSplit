import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';

void main() {
  group('ProfileValidation', () {
    test('canonicalizes a valid username', () {
      expect(
        ProfileValidation.normalizeUsername('  Fernando_1 '),
        'fernando_1',
      );
      expect(ProfileValidation.username('  Fernando_1 '), isNull);
    });

    test('rejects usernames outside the durable format', () {
      for (final username in ['1starts_wrong', 'ab', 'has-dash', 'a' * 25]) {
        expect(
          ProfileValidation.username(username),
          ProfileValidationIssue.usernameInvalid,
          reason: username,
        );
      }
    });

    test('trims display names and enforces the 1 to 50 range', () {
      expect(
          ProfileValidation.normalizeDisplayName('  Fernando  '), 'Fernando');
      expect(
        ProfileValidation.displayName('   '),
        ProfileValidationIssue.displayNameRequired,
      );
      expect(
        ProfileValidation.displayName('x' * 51),
        ProfileValidationIssue.displayNameTooLong,
      );
      expect(ProfileValidation.displayName('😀' * 50), isNull);
    });
  });
}
