import 'package:list_and_split/features/community/domain/friendship_summary.dart';

enum FriendshipFailureCode { unavailable, stale, generic }

class FriendshipFailure implements Exception {
  const FriendshipFailure(this.code);

  final FriendshipFailureCode code;
}

abstract interface class FriendshipRepository {
  Future<FriendshipSummary> getRelationshipSummary(String profileId);

  Future<List<FriendshipSummary>> listActiveRelationships();

  Future<void> sendFriendRequest(
    String profileId, {
    required int? expectedVersion,
  });

  Future<void> cancelFriendRequest(
    String profileId, {
    required int expectedVersion,
  });

  Future<void> acceptFriendRequest(
    String profileId, {
    required int expectedVersion,
  });

  Future<void> declineFriendRequest(
    String profileId, {
    required int expectedVersion,
  });

  Future<void> endFriendship(
    String profileId, {
    required int expectedVersion,
  });
}
