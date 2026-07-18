import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

String authValidationText(
  AppLocalizations localizations,
  AuthValidationIssue? issue,
) {
  return switch (issue) {
    AuthValidationIssue.emailRequired => localizations.emailRequiredError,
    AuthValidationIssue.emailInvalid => localizations.emailInvalidError,
    AuthValidationIssue.passwordRequired => localizations.passwordRequiredError,
    AuthValidationIssue.passwordTooShort => localizations.passwordTooShortError,
    AuthValidationIssue.passwordsDoNotMatch =>
      localizations.passwordsDoNotMatchError,
    null => '',
  };
}

String authMessageText(
  AppLocalizations localizations,
  AuthActionMessage message,
) {
  return switch (message) {
    AuthActionMessage.checkInboxToVerify => localizations.checkInboxMessage,
    AuthActionMessage.verificationSent => localizations.verificationSentMessage,
    AuthActionMessage.passwordResetSent =>
      localizations.passwordResetSentMessage,
    AuthActionMessage.passwordUpdated => localizations.passwordUpdatedMessage,
    AuthActionMessage.signInFailed => localizations.signInFailedMessage,
    AuthActionMessage.operationFailed => localizations.operationFailedMessage,
  };
}
