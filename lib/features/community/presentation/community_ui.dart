import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_controller.dart';
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
    CommunitySearchMessage.requestSent =>
      localizations.friendRequestSentMessage,
    CommunitySearchMessage.requestCancelled =>
      localizations.friendRequestCancelledMessage,
    CommunitySearchMessage.requestAccepted =>
      localizations.friendRequestAcceptedMessage,
    CommunitySearchMessage.requestDeclined =>
      localizations.friendRequestDeclinedMessage,
    CommunitySearchMessage.relationshipChanged =>
      localizations.friendshipChangedMessage,
    CommunitySearchMessage.operationFailed =>
      localizations.operationFailedMessage,
  };
}

String friendshipManagementMessageText(
  AppLocalizations localizations,
  FriendshipManagementMessage message,
) {
  return switch (message) {
    FriendshipManagementMessage.requestAccepted =>
      localizations.friendRequestAcceptedMessage,
    FriendshipManagementMessage.requestDeclined =>
      localizations.friendRequestDeclinedMessage,
    FriendshipManagementMessage.requestCancelled =>
      localizations.friendRequestCancelledMessage,
    FriendshipManagementMessage.friendshipEnded =>
      localizations.friendshipEndedMessage,
    FriendshipManagementMessage.blocked =>
      localizations.communityBlockedMessage,
    FriendshipManagementMessage.relationshipChanged =>
      localizations.friendshipChangedMessage,
    FriendshipManagementMessage.operationFailed =>
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
