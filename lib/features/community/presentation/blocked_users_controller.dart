import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

enum BlockedUsersMessage { unblocked, operationFailed }

class BlockedUsersState {
  const BlockedUsersState({
    required this.profiles,
    this.unblockingProfileId,
    this.message,
  });

  const BlockedUsersState.loading()
      : profiles = const AsyncLoading(),
        unblockingProfileId = null,
        message = null;

  final AsyncValue<List<BlockedProfile>> profiles;
  final String? unblockingProfileId;
  final BlockedUsersMessage? message;
}

class BlockedUsersController extends StateNotifier<BlockedUsersState> {
  BlockedUsersController(this._repository)
      : super(const BlockedUsersState.loading());

  final CommunityRepository _repository;

  Future<void> load() async {
    state = const BlockedUsersState.loading();
    try {
      final profiles = await _repository.listBlockedProfiles();
      if (!mounted) return;
      state = BlockedUsersState(
        profiles: AsyncData(profiles),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = BlockedUsersState(
        profiles: AsyncError(error, stackTrace),
        message: BlockedUsersMessage.operationFailed,
      );
    }
  }

  Future<bool> unblock(BlockedProfile profile) async {
    final currentProfiles = state.profiles.valueOrNull;
    if (currentProfiles == null || state.unblockingProfileId != null) {
      return false;
    }

    state = BlockedUsersState(
      profiles: AsyncData(currentProfiles),
      unblockingProfileId: profile.id,
    );
    try {
      await _repository.unblockProfile(profile.id);
      if (!mounted) return false;
      state = BlockedUsersState(
        profiles: AsyncData(
          currentProfiles
              .where((blockedProfile) => blockedProfile.id != profile.id)
              .toList(growable: false),
        ),
        message: BlockedUsersMessage.unblocked,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = BlockedUsersState(
        profiles: AsyncData(currentProfiles),
        message: BlockedUsersMessage.operationFailed,
      );
      return false;
    }
  }
}

final blockedUsersControllerProvider = StateNotifierProvider.autoDispose<
    BlockedUsersController, BlockedUsersState>((ref) {
  ref.watch(verifiedUserIdProvider);
  final controller =
      BlockedUsersController(ref.watch(communityRepositoryProvider));
  unawaited(controller.load());
  return controller;
});
