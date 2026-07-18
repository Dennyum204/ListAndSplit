class DiscoveredProfile {
  const DiscoveredProfile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;
}

class BlockedProfile {
  const BlockedProfile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;
}
