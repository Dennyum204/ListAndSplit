import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

String communityUsernameValidationText(
  AppLocalizations localizations,
  ProfileValidationIssue issue,
) {
  return switch (issue) {
    ProfileValidationIssue.usernameRequired =>
      localizations.communityUsernameRequiredError,
    ProfileValidationIssue.usernameInvalid =>
      localizations.usernameInvalidError,
    ProfileValidationIssue.displayNameRequired ||
    ProfileValidationIssue.displayNameTooLong =>
      localizations.operationFailedMessage,
  };
}

String communitySearchMessageText(
  AppLocalizations localizations,
  CommunitySearchMessage message,
) {
  return switch (message) {
    CommunitySearchMessage.notFoundOrUnavailable =>
      localizations.communityNotFoundMessage,
    CommunitySearchMessage.blocked => localizations.communityBlockedMessage,
    CommunitySearchMessage.operationFailed =>
      localizations.operationFailedMessage,
  };
}

String blockedUsersMessageText(
  AppLocalizations localizations,
  BlockedUsersMessage message,
) {
  return switch (message) {
    BlockedUsersMessage.unblocked => localizations.communityUnblockedMessage,
    BlockedUsersMessage.operationFailed => localizations.operationFailedMessage,
  };
}
