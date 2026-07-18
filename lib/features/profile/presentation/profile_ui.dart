import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

String profileValidationText(
  AppLocalizations localizations,
  ProfileValidationIssue? issue,
) {
  return switch (issue) {
    ProfileValidationIssue.usernameRequired =>
      localizations.usernameRequiredError,
    ProfileValidationIssue.usernameInvalid =>
      localizations.usernameInvalidError,
    ProfileValidationIssue.displayNameRequired =>
      localizations.displayNameRequiredError,
    ProfileValidationIssue.displayNameTooLong =>
      localizations.displayNameTooLongError,
    null => '',
  };
}

String profileMessageText(
  AppLocalizations localizations,
  ProfileActionMessage message,
) {
  return switch (message) {
    ProfileActionMessage.usernameUnavailable =>
      localizations.usernameUnavailableMessage,
    ProfileActionMessage.saved => localizations.profileSavedMessage,
    ProfileActionMessage.operationFailed =>
      localizations.operationFailedMessage,
  };
}
