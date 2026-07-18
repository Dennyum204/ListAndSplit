import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef CommunityRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseCommunityRepository implements CommunityRepository {
  SupabaseCommunityRepository(
    SupabaseClient client, {
    CommunityRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) async {
              return client.rpc<Object?>(functionName, params: params);
            });

  final CommunityRpc _rpc;

  @override
  Future<DiscoveredProfile?> findProfileByUsername(String username) async {
    try {
      final rows = _rows(
        await _rpc(
          'find_profile_by_username',
          params: {'search_username': username},
        ),
      );
      if (rows.isEmpty) return null;
      if (rows.length != 1) throw const CommunityFailure();
      return _mapDiscoveredProfile(rows.single);
    } on CommunityFailure {
      rethrow;
    } catch (_) {
      throw const CommunityFailure();
    }
  }

  @override
  Future<void> blockProfile(String profileId) async {
    await _runMutation('block_profile', profileId);
  }

  @override
  Future<void> unblockProfile(String profileId) async {
    await _runMutation('unblock_profile', profileId);
  }

  @override
  Future<List<BlockedProfile>> listBlockedProfiles() async {
    try {
      final rows = _rows(await _rpc('list_blocked_profiles'));
      return rows.map(_mapBlockedProfile).toList(growable: false);
    } on CommunityFailure {
      rethrow;
    } catch (_) {
      throw const CommunityFailure();
    }
  }

  Future<void> _runMutation(String functionName, String profileId) async {
    try {
      await _rpc(
        functionName,
        params: {'target_profile_id': profileId},
      );
    } catch (_) {
      throw const CommunityFailure();
    }
  }

  List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) throw const CommunityFailure();
    return response.map((row) {
      if (row is! Map) throw const CommunityFailure();
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  DiscoveredProfile _mapDiscoveredProfile(Map<String, dynamic> json) {
    try {
      return DiscoveredProfile(
        id: json['profile_id']! as String,
        username: json['username']! as String,
        displayName: json['display_name']! as String,
      );
    } catch (_) {
      throw const CommunityFailure();
    }
  }

  BlockedProfile _mapBlockedProfile(Map<String, dynamic> json) {
    try {
      return BlockedProfile(
        id: json['profile_id']! as String,
        username: json['username']! as String,
        displayName: json['display_name']! as String,
      );
    } catch (_) {
      throw const CommunityFailure();
    }
  }
}
