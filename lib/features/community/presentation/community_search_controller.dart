import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

enum CommunitySearchMessage { notFoundOrUnavailable, blocked, operationFailed }

class CommunitySearchState {
  const CommunitySearchState({
    this.isSearching = false,
    this.isBlocking = false,
    this.usernameError,
    this.result,
    this.message,
  });

  final bool isSearching;
  final bool isBlocking;
  final ProfileValidationIssue? usernameError;
  final DiscoveredProfile? result;
  final CommunitySearchMessage? message;

  bool get isBusy => isSearching || isBlocking;
}

class CommunitySearchController extends StateNotifier<CommunitySearchState> {
  CommunitySearchController(this._repository)
      : super(const CommunitySearchState());

  final CommunityRepository _repository;

  void clearResultForEditedQuery() {
    if (!state.isBusy &&
        (state.result != null ||
            state.message != null ||
            state.usernameError != null)) {
      state = const CommunitySearchState();
    }
  }

  Future<bool> search(String username) async {
    if (state.isBusy) return false;
    final validationIssue = ProfileValidation.username(username);
    if (validationIssue != null) {
      state = CommunitySearchState(usernameError: validationIssue);
      return false;
    }

    state = const CommunitySearchState(isSearching: true);
    try {
      final result = await _repository.findProfileByUsername(
        ProfileValidation.normalizeUsername(username),
      );
      if (!mounted) return false;
      state = CommunitySearchState(
        result: result,
        message: result == null
            ? CommunitySearchMessage.notFoundOrUnavailable
            : null,
      );
      return result != null;
    } catch (_) {
      if (!mounted) return false;
      state = const CommunitySearchState(
        message: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }

  Future<bool> blockResult() async {
    final result = state.result;
    if (result == null || state.isBusy) return false;

    state = CommunitySearchState(isBlocking: true, result: result);
    try {
      await _repository.blockProfile(result.id);
      if (!mounted) return false;
      state = const CommunitySearchState(
        message: CommunitySearchMessage.blocked,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = CommunitySearchState(
        result: result,
        message: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }
}

final communitySearchControllerProvider = StateNotifierProvider.autoDispose<
    CommunitySearchController, CommunitySearchState>((ref) {
  ref.watch(verifiedUserIdProvider);
  return CommunitySearchController(ref.watch(communityRepositoryProvider));
});
