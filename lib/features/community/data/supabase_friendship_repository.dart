import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef FriendshipRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseFriendshipRepository implements FriendshipRepository {
  SupabaseFriendshipRepository(
    SupabaseClient client, {
    FriendshipRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) async {
              return client.rpc<Object?>(functionName, params: params);
            });

  final FriendshipRpc _rpc;

  @override
  Future<FriendshipSummary> getRelationshipSummary(String profileId) async {
    try {
      final rows = _rows(
        await _rpc(
          'get_relationship_summary',
          params: {'target_profile_id': profileId},
        ),
      );
      if (rows.length != 1) {
        throw const FriendshipFailure(FriendshipFailureCode.generic);
      }
      return _mapSummary(rows.single);
    } on FriendshipFailure {
      rethrow;
    } catch (_) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
  }

  @override
  Future<List<FriendshipSummary>> listActiveRelationships() async {
    try {
      final rows = _rows(await _rpc('list_active_relationships'));
      final relationships = rows.map(_mapSummary).toList(growable: false);
      if (relationships.any(
        (relationship) =>
            relationship.status == FriendshipStatus.canSend ||
            relationship.status == FriendshipStatus.unavailable ||
            relationship.version == null ||
            relationship.stateChangedAt == null,
      )) {
        throw const FriendshipFailure(FriendshipFailureCode.generic);
      }
      return relationships;
    } on FriendshipFailure {
      rethrow;
    } catch (_) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
  }

  @override
  Future<void> sendFriendRequest(
    String profileId, {
    required int? expectedVersion,
  }) =>
      _runMutation(
        'send_friend_request',
        profileId,
        expectedVersion,
      );

  @override
  Future<void> cancelFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _runMutation(
        'cancel_friend_request',
        profileId,
        expectedVersion,
      );

  @override
  Future<void> acceptFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _runMutation(
        'accept_friend_request',
        profileId,
        expectedVersion,
      );

  @override
  Future<void> declineFriendRequest(
    String profileId, {
    required int expectedVersion,
  }) =>
      _runMutation(
        'decline_friend_request',
        profileId,
        expectedVersion,
      );

  @override
  Future<void> endFriendship(
    String profileId, {
    required int expectedVersion,
  }) =>
      _runMutation(
        'end_friendship',
        profileId,
        expectedVersion,
      );

  Future<void> _runMutation(
    String functionName,
    String profileId,
    int? expectedVersion,
  ) async {
    try {
      await _rpc(
        functionName,
        params: {
          'target_profile_id': profileId,
          'expected_relationship_version': expectedVersion,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == '40001') {
        throw const FriendshipFailure(FriendshipFailureCode.stale);
      }
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    } catch (_) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
  }

  List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
    return response.map((row) {
      if (row is! Map) {
        throw const FriendshipFailure(FriendshipFailureCode.generic);
      }
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  FriendshipSummary _mapSummary(Map<String, dynamic> json) {
    try {
      final version = json['version'] as int?;
      if (version != null && version <= 0) {
        throw const FormatException();
      }
      final status = _mapStatus(json['relationship_status']! as String);
      final stateChangedAt = _mapTimestamp(json['state_changed_at']);
      final isActive = status == FriendshipStatus.incomingPending ||
          status == FriendshipStatus.outgoingPending ||
          status == FriendshipStatus.friends;
      if ((isActive && version == null) ||
          (status == FriendshipStatus.unavailable &&
              (version != null || stateChangedAt != null))) {
        throw const FormatException();
      }

      return FriendshipSummary(
        id: json['profile_id']! as String,
        username: json['username']! as String,
        displayName: json['display_name']! as String,
        status: status,
        version: version,
        stateChangedAt: stateChangedAt,
      );
    } catch (_) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
  }

  FriendshipStatus _mapStatus(String status) => switch (status) {
        'can-send' => FriendshipStatus.canSend,
        'incoming-pending' => FriendshipStatus.incomingPending,
        'outgoing-pending' => FriendshipStatus.outgoingPending,
        'friends' => FriendshipStatus.friends,
        'unavailable' => FriendshipStatus.unavailable,
        _ => throw const FriendshipFailure(FriendshipFailureCode.generic),
      };

  DateTime? _mapTimestamp(Object? value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }
}
