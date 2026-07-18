enum AuthValidationIssue {
  emailRequired,
  emailInvalid,
  passwordRequired,
  passwordTooShort,
  passwordsDoNotMatch,
}

abstract final class AuthValidation {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static AuthValidationIssue? email(String value) {
    final normalized = normalizeEmail(value);
    if (normalized.isEmpty) return AuthValidationIssue.emailRequired;
    if (!_emailPattern.hasMatch(normalized)) {
      return AuthValidationIssue.emailInvalid;
    }
    return null;
  }

  static AuthValidationIssue? password(String value) {
    if (value.isEmpty) return AuthValidationIssue.passwordRequired;
    if (value.length < 6) return AuthValidationIssue.passwordTooShort;
    return null;
  }

  static AuthValidationIssue? passwordConfirmation(
    String password,
    String confirmation,
  ) {
    if (confirmation.isEmpty) return AuthValidationIssue.passwordRequired;
    if (password != confirmation) {
      return AuthValidationIssue.passwordsDoNotMatch;
    }
    return null;
  }
}
