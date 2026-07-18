enum ProfileValidationIssue {
  usernameRequired,
  usernameInvalid,
  displayNameRequired,
  displayNameTooLong,
}

abstract final class ProfileValidation {
  static final _usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,23}$');

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static String normalizeDisplayName(String value) => value.trim();

  static ProfileValidationIssue? username(String value) {
    final normalized = normalizeUsername(value);
    if (normalized.isEmpty) return ProfileValidationIssue.usernameRequired;
    if (!_usernamePattern.hasMatch(normalized)) {
      return ProfileValidationIssue.usernameInvalid;
    }
    return null;
  }

  static ProfileValidationIssue? displayName(String value) {
    final normalized = normalizeDisplayName(value);
    if (normalized.isEmpty) return ProfileValidationIssue.displayNameRequired;
    if (normalized.runes.length > 50) {
      return ProfileValidationIssue.displayNameTooLong;
    }
    return null;
  }
}
