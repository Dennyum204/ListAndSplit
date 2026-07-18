import 'dart:async';

import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';

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
