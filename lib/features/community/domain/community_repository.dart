import 'package:list_and_split/features/community/domain/community_profile.dart';

class CommunityFailure implements Exception {
  const CommunityFailure();
}

abstract interface class CommunityRepository {
  Future<DiscoveredProfile?> findProfileByUsername(String username);

  Future<void> blockProfile(String profileId);

  Future<void> unblockProfile(String profileId);

  Future<List<BlockedProfile>> listBlockedProfiles();
}
