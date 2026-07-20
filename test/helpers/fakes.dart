import 'dart:async';

import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_repository.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';

class FakeAccountDataExportRepository implements AccountDataExportRepository {
  AccountDataExportDocument? document;
  Object? failure;
  Completer<AccountDataExportDocument>? completer;
  int exportCalls = 0;

  @override
  Future<AccountDataExportDocument> exportOwnAccountData() async {
    exportCalls += 1;
    if (failure != null) throw failure!;
    final pending = completer;
    if (pending != null) return pending.future;
    final result = document;
    if (result == null) throw const AccountDataExportFailure();
    return result;
  }
}

class FakeAccountDataExportShareService
    implements AccountDataExportShareService {
  AccountDataShareResult result = AccountDataShareResult.shared;
  Object? failure;
  Completer<AccountDataShareResult>? completer;
  AccountDataExportDocument? lastDocument;
  AccountDataShareOrigin? lastOrigin;
  int shareCalls = 0;

  @override
  Future<AccountDataShareResult> share(
    AccountDataExportDocument document, {
    AccountDataShareOrigin? origin,
  }) async {
    shareCalls += 1;
    lastDocument = document;
    lastOrigin = origin;
    if (failure != null) throw failure!;
    final pending = completer;
    if (pending != null) return pending.future;
    return result;
  }
}

class FakeAccountDeletionRepository implements AccountDeletionRepository {
  Object? deletionFailure;
  Completer<void>? deletionCompleter;
  AuthoritativeAccountState validationResult = AuthoritativeAccountState.valid;
  Completer<AuthoritativeAccountState>? validationCompleter;

  String? lastEmail;
  String? lastPassword;
  String? lastConfirmation;
  int deletionCalls = 0;
  int validationCalls = 0;
  int clearSessionCalls = 0;

  @override
  Future<void> deleteOwnAccount({
    required String email,
    required String password,
    required String confirmation,
  }) async {
    deletionCalls += 1;
    lastEmail = email;
    lastPassword = password;
    lastConfirmation = confirmation;
    if (deletionFailure != null) throw deletionFailure!;
    await deletionCompleter?.future;
  }

  @override
  Future<AuthoritativeAccountState> validateCurrentAccount() async {
    validationCalls += 1;
    final pending = validationCompleter;
    if (pending != null) return pending.future;
    return validationResult;
  }

  @override
  Future<void> clearLocalSession() async {
    clearSessionCalls += 1;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.session = const AuthSessionState.signedOut(),
  });

  AuthSessionState session;
  final _sessions = StreamController<AuthSessionState>.broadcast();
  AuthFailure? signInFailure;
  Object? operationFailure;
  Completer<void>? signUpCompleter;

  String? lastEmail;
  String? lastPassword;
  int signUpCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;
  int resendCalls = 0;
  int resetCalls = 0;
  int updatePasswordCalls = 0;

  @override
  Stream<AuthSessionState> observeSession() async* {
    yield session;
    yield* _sessions.stream;
  }

  void emit(AuthSessionState value) {
    session = value;
    _sessions.add(value);
  }

  Future<void> close() => _sessions.close();

  @override
  Future<void> signUp({required String email, required String password}) async {
    signUpCalls += 1;
    lastEmail = email;
    lastPassword = password;
    if (operationFailure != null) throw operationFailure!;
    await signUpCompleter?.future;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls += 1;
    lastEmail = email;
    lastPassword = password;
    if (signInFailure != null) throw signInFailure!;
    if (operationFailure != null) throw operationFailure!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    if (operationFailure != null) throw operationFailure!;
    emit(const AuthSessionState.signedOut());
  }

  @override
  Future<void> resendVerification({required String email}) async {
    resendCalls += 1;
    lastEmail = email;
    if (operationFailure != null) throw operationFailure!;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    resetCalls += 1;
    lastEmail = email;
    if (operationFailure != null) throw operationFailure!;
  }

  @override
  Future<void> updatePassword({required String password}) async {
    updatePasswordCalls += 1;
    lastPassword = password;
    if (operationFailure != null) throw operationFailure!;
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({UserProfile? profile})
      : profile = profile ?? incompleteProfile;

  static const incompleteProfile = UserProfile(
    id: 'user-1',
    username: null,
    displayName: null,
    onboardingCompletedAt: null,
  );

  static final completeProfile = UserProfile(
    id: 'user-1',
    username: 'fernando_1',
    displayName: 'Fernando',
    onboardingCompletedAt: DateTime.utc(2026, 7, 18),
  );

  UserProfile profile;
  Object? failure;
  String? lastUsername;
  String? lastDisplayName;
  int fetchCalls = 0;
  int completeCalls = 0;
  int updateCalls = 0;

  @override
  Future<UserProfile> fetchOwnProfile() async {
    fetchCalls += 1;
    if (failure != null) throw failure!;
    return profile;
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String username,
    required String displayName,
  }) async {
    completeCalls += 1;
    lastUsername = username;
    lastDisplayName = displayName;
    if (failure != null) throw failure!;
    profile = UserProfile(
      id: profile.id,
      username: username,
      displayName: displayName,
      onboardingCompletedAt: DateTime.utc(2026, 7, 18),
    );
    return profile;
  }

  @override
  Future<UserProfile> updateDisplayName({required String displayName}) async {
    updateCalls += 1;
    lastDisplayName = displayName;
    if (failure != null) throw failure!;
    profile = UserProfile(
      id: profile.id,
      username: profile.username,
      displayName: displayName,
      onboardingCompletedAt: profile.onboardingCompletedAt,
    );
    return profile;
  }
}

class FakeCommunityRepository implements CommunityRepository {
  DiscoveredProfile? searchResult;
  List<BlockedProfile> blockedProfiles = [];
  Object? searchFailure;
  Object? blockFailure;
  Object? unblockFailure;
  Object? listFailure;
  Completer<DiscoveredProfile?>? searchCompleter;
  Completer<List<BlockedProfile>>? listCompleter;

  String? lastUsername;
  String? lastBlockedProfileId;
  String? lastUnblockedProfileId;
  int searchCalls = 0;
  int blockCalls = 0;
  int unblockCalls = 0;
  int listCalls = 0;

  @override
  Future<DiscoveredProfile?> findProfileByUsername(String username) async {
    searchCalls += 1;
    lastUsername = username;
    if (searchFailure != null) throw searchFailure!;
    final completer = searchCompleter;
    if (completer != null) return completer.future;
    return searchResult;
  }

  @override
  Future<void> blockProfile(String profileId) async {
    blockCalls += 1;
    lastBlockedProfileId = profileId;
    if (blockFailure != null) throw blockFailure!;
    final result = searchResult;
    if (result != null &&
        result.id == profileId &&
        !blockedProfiles.any((profile) => profile.id == profileId)) {
      blockedProfiles = [
        ...blockedProfiles,
        BlockedProfile(
          id: result.id,
          username: result.username,
          displayName: result.displayName,
        ),
      ];
    }
  }

  @override
  Future<void> unblockProfile(String profileId) async {
    unblockCalls += 1;
    lastUnblockedProfileId = profileId;
    if (unblockFailure != null) throw unblockFailure!;
    blockedProfiles = blockedProfiles
        .where((profile) => profile.id != profileId)
        .toList(growable: false);
  }

  @override
  Future<List<BlockedProfile>> listBlockedProfiles() async {
    listCalls += 1;
    if (listFailure != null) throw listFailure!;
    final completer = listCompleter;
    if (completer != null) return completer.future;
    return List.unmodifiable(blockedProfiles);
  }
}

class FakeFriendshipRepository implements FriendshipRepository {
  FriendshipSummary? summaryResult;
  List<FriendshipSummary> activeRelationships = [];
  Object? summaryFailure;
  Object? listFailure;
  Object? mutationFailure;
  Completer<FriendshipSummary>? summaryCompleter;
  Completer<List<FriendshipSummary>>? friendshipListCompleter;
  Completer<void>? mutationCompleter;
  final List<Completer<void>> queuedMutationCompleters = [];
  final List<List<FriendshipSummary>> queuedRelationshipLists = [];

  String? lastSummaryProfileId;
  int summaryCalls = 0;
  int friendshipListCalls = 0;
  final List<FriendshipMutationCall> mutationCalls = [];

  @override
  Future<FriendshipSummary> getRelationshipSummary(String profileId) async {
    summaryCalls += 1;
    lastSummaryProfileId = profileId;
    if (summaryFailure != null) throw summaryFailure!;
    final completer = summaryCompleter;
    if (completer != null) return completer.future;
    final result = summaryResult;
    if (result == null) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
    return result;
  }

  @override
  Future<List<FriendshipSummary>> listActiveRelationships() async {
    friendshipListCalls += 1;
    if (listFailure != null) throw listFailure!;
    final completer = friendshipListCompleter;
    if (completer != null) return completer.future;
    if (queuedRelationshipLists.isNotEmpty) {
      return List.unmodifiable(queuedRelationshipLists.removeAt(0));
    }
    return List.unmodifiable(activeRelationships);
  }

  @override
  Future<void> sendFriendRequest(
    String profileId, {
    required int? expectedVersion,
  }) =>
      _mutate('send', profileId, expectedVersion);

  @override
  Future<void> cancelFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _mutate('cancel', profileId, expectedVersion);

  @override
  Future<void> acceptFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _mutate('accept', profileId, expectedVersion);

  @override
  Future<void> declineFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _mutate('decline', profileId, expectedVersion);

  @override
  Future<void> endFriendship(
    String profileId, {
    required int expectedVersion,
  }) =>
      _mutate('end', profileId, expectedVersion);

  Future<void> _mutate(
    String operation,
    String profileId,
    int? expectedVersion,
  ) async {
    mutationCalls.add(
      FriendshipMutationCall(operation, profileId, expectedVersion),
    );
    if (mutationFailure != null) throw mutationFailure!;
    if (queuedMutationCompleters.isNotEmpty) {
      await queuedMutationCompleters.removeAt(0).future;
      return;
    }
    await mutationCompleter?.future;
  }
}

class FriendshipMutationCall {
  const FriendshipMutationCall(
    this.operation,
    this.profileId,
    this.expectedVersion,
  );

  final String operation;
  final String profileId;
  final int? expectedVersion;
}

class FakeNotificationRepository implements NotificationRepository {
  List<InAppNotification> notifications = [];
  final List<List<InAppNotification>> queuedPages = [];
  int unreadCount = 0;
  Object? listFailure;
  Object? unreadFailure;
  Object? markFailure;
  Completer<List<InAppNotification>>? listCompleter;
  Completer<void>? markCompleter;
  final List<NotificationListCall> listCalls = [];
  final List<List<String>> markCalls = [];
  int unreadCalls = 0;

  @override
  Future<List<InAppNotification>> listNotifications({
    required int limit,
    NotificationCursor? before,
  }) async {
    listCalls.add(NotificationListCall(limit, before));
    if (listFailure != null) throw listFailure!;
    final completer = listCompleter;
    if (completer != null) return completer.future;
    if (queuedPages.isNotEmpty) {
      return List.unmodifiable(queuedPages.removeAt(0));
    }
    return List.unmodifiable(notifications);
  }

  @override
  Future<int> getUnreadCount() async {
    unreadCalls += 1;
    if (unreadFailure != null) throw unreadFailure!;
    return unreadCount;
  }

  @override
  Future<void> markRead(List<String> notificationIds) async {
    markCalls.add(List.unmodifiable(notificationIds));
    if (markFailure != null) throw markFailure!;
    await markCompleter?.future;
  }
}

class FakeActiveListRepository implements ActiveListRepository {
  List<ActiveListSummary> activeLists = [];
  List<ActiveListSummary> archivedLists = [];
  final Map<String, List<ActiveListItem>> itemsByList = {};
  final Map<String, List<ActiveListParticipant>> participantsByList = {};
  final Map<String, List<ActiveListAccessProfile>> pendingByList = {};
  final Map<String, List<ActiveListAccessProfile>> eligibleByList = {};
  Object? failure;
  Completer<ActiveListPage>? pageCompleter;
  Completer<ActiveListSummary>? createCompleter;
  int listCalls = 0;
  int createCalls = 0;
  int mutationCalls = 0;
  final List<String> createRequestIds = [];
  final List<String> itemRequestIds = [];

  ActiveListSummary _find(String listId) => [...activeLists, ...archivedLists]
      .firstWhere((entry) => entry.id == listId);

  void _replace(ActiveListSummary summary) {
    activeLists = activeLists
        .where((entry) => entry.id != summary.id)
        .toList(growable: true);
    archivedLists = archivedLists
        .where((entry) => entry.id != summary.id)
        .toList(growable: true);
    (summary.status == ActiveListStatus.active ? activeLists : archivedLists)
        .add(summary);
  }

  @override
  Future<ActiveListPage> listLists({
    required ActiveListStatus status,
    required int limit,
    ActiveListCursor? before,
  }) async {
    listCalls += 1;
    if (failure != null) throw failure!;
    if (pageCompleter != null) return pageCompleter!.future;
    final source =
        status == ActiveListStatus.active ? activeLists : archivedLists;
    return ActiveListPage(lists: source.take(limit).toList(), hasMore: false);
  }

  @override
  Future<ActiveListSummary> getList(String listId) async {
    if (failure != null) throw failure!;
    return _find(listId);
  }

  @override
  Future<List<ActiveListItem>> listItems(String listId) async {
    if (failure != null) throw failure!;
    return List.unmodifiable(itemsByList[listId] ?? const []);
  }

  @override
  Future<List<ActiveListParticipant>> listParticipants(String listId) async {
    if (failure != null) throw failure!;
    return List.unmodifiable(participantsByList[listId] ?? const []);
  }

  @override
  Future<List<ActiveListAccessProfile>> listPendingInvitations(
    String listId,
  ) async {
    if (failure != null) throw failure!;
    return List.unmodifiable(pendingByList[listId] ?? const []);
  }

  @override
  Future<List<ActiveListAccessProfile>> listEligibleInvitees(
    String listId,
  ) async {
    if (failure != null) throw failure!;
    return List.unmodifiable(eligibleByList[listId] ?? const []);
  }

  @override
  Future<ActiveListInvitation> getInvitation(String listId) async {
    if (failure != null) throw failure!;
    final summary = _find(listId);
    return ActiveListInvitation(
      listId: listId,
      listTitle: summary.title,
      listStatus: summary.status,
      owner: ActiveListParticipant(
        profileId: summary.ownerProfileId ?? 'owner-1',
        username: summary.ownerUsername ?? 'owner',
        displayName: summary.ownerDisplayName ?? 'Owner',
        isOwner: true,
      ),
      accessVersion: summary.callerAccessVersion ?? 1,
      createdAt: summary.createdAt,
      stateChangedAt: summary.updatedAt,
    );
  }

  @override
  Future<ActiveListSummary> createList(
    String title, {
    required String requestId,
  }) async {
    createCalls += 1;
    createRequestIds.add(requestId);
    if (failure != null) throw failure!;
    if (createCompleter != null) return createCompleter!.future;
    final now = DateTime.utc(2026, 7, 20, 12, createCalls);
    final summary = ActiveListSummary(
      id: 'list-$createCalls',
      title: title,
      status: ActiveListStatus.active,
      version: 1,
      itemCount: 0,
      completedItemCount: 0,
      createdAt: now,
      updatedAt: now,
      archivedAt: null,
    );
    activeLists.insert(0, summary);
    return summary;
  }

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final current = _find(listId);
    final updated = current.copyWith(
      title: title,
      version: current.version + 1,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<ActiveListSummary> setArchived(
    String listId, {
    required bool archived,
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final current = _find(listId);
    final now = current.updatedAt.add(const Duration(seconds: 1));
    final updated = current.copyWith(
      status: archived ? ActiveListStatus.archived : ActiveListStatus.active,
      version: current.version + 1,
      updatedAt: now,
      archivedAt: archived ? now : null,
      clearArchivedAt: !archived,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> deleteList(String listId, {required int expectedVersion}) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    activeLists.removeWhere((entry) => entry.id == listId);
    archivedLists.removeWhere((entry) => entry.id == listId);
    itemsByList.remove(listId);
  }

  @override
  Future<ActiveListItem> createItem(
    String listId,
    String name, {
    required int expectedListVersion,
    ListQuantity quantity = ListQuantity.one,
    ListUnit? unit,
    required String requestId,
  }) async {
    mutationCalls += 1;
    itemRequestIds.add(requestId);
    if (failure != null) throw failure!;
    final entries = itemsByList.putIfAbsent(listId, () => []);
    final now = DateTime.utc(2026, 7, 20, 13, entries.length);
    final item = ActiveListItem(
      id: 'item-${entries.length + 1}',
      name: name,
      quantity: quantity,
      unit: unit,
      position: entries.length + 1,
      version: 1,
      completedAt: null,
      completedBy: null,
      createdAt: now,
      updatedAt: now,
    );
    entries.add(item);
    return item;
  }

  @override
  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final entries = itemsByList[listId]!;
    final index = entries.indexWhere((entry) => entry.id == itemId);
    final current = entries[index];
    final updated = ActiveListItem(
      id: current.id,
      name: name,
      quantity: quantity,
      unit: unit,
      position: current.position,
      version: current.version + 1,
      completedAt: current.completedAt,
      completedBy: current.completedBy,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(seconds: 1)),
    );
    entries[index] = updated;
    return updated;
  }

  @override
  Future<ActiveListItem> setItemCompleted(
    String listId,
    String itemId, {
    required bool completed,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final entries = itemsByList[listId]!;
    final index = entries.indexWhere((entry) => entry.id == itemId);
    final current = entries[index];
    final now = current.updatedAt.add(const Duration(seconds: 1));
    final updated = ActiveListItem(
      id: current.id,
      name: current.name,
      quantity: current.quantity,
      unit: current.unit,
      position: current.position,
      version: current.version + 1,
      completedAt: completed ? now : null,
      completedBy: completed ? 'user-1' : null,
      createdAt: current.createdAt,
      updatedAt: now,
    );
    entries[index] = updated;
    return updated;
  }

  @override
  Future<int> deleteItem(
    String listId,
    String itemId, {
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    itemsByList[listId]!.removeWhere((entry) => entry.id == itemId);
    return expectedListVersion + 1;
  }

  @override
  Future<int> reorderItems(
    String listId,
    List<String> orderedItemIds, {
    required int expectedListVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final byId = {for (final item in itemsByList[listId]!) item.id: item};
    itemsByList[listId] = [for (final id in orderedItemIds) byId[id]!];
    return expectedListVersion + 1;
  }

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    return (expectedAccessVersion ?? 0) + 1;
  }

  @override
  Future<int> cancelInvitation(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    pendingByList[listId]?.removeWhere((entry) => entry.profileId == profileId);
    return expectedAccessVersion + 1;
  }

  @override
  Future<int> acceptInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    return expectedAccessVersion + 1;
  }

  @override
  Future<int> declineInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    return expectedAccessVersion + 1;
  }

  @override
  Future<int> removeMember(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    participantsByList[listId]
        ?.removeWhere((entry) => entry.profileId == profileId);
    return expectedAccessVersion + 1;
  }

  @override
  Future<int> leaveList(
    String listId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    activeLists.removeWhere((entry) => entry.id == listId);
    archivedLists.removeWhere((entry) => entry.id == listId);
    return expectedAccessVersion + 1;
  }
}

class NotificationListCall {
  const NotificationListCall(this.limit, this.before);

  final int limit;
  final NotificationCursor? before;
}

const verifiedSession = AuthSessionState(
  user: AuthenticatedUser(
    id: 'user-1',
    email: 'person@example.com',
    isEmailVerified: true,
  ),
);

const unverifiedSession = AuthSessionState(
  user: AuthenticatedUser(
    id: 'user-1',
    email: 'person@example.com',
    isEmailVerified: false,
  ),
);

const recoverySession = AuthSessionState(
  user: AuthenticatedUser(
    id: 'user-1',
    email: 'person@example.com',
    isEmailVerified: true,
  ),
  isPasswordRecovery: true,
  passwordRecoveryAttempt: 1,
);
