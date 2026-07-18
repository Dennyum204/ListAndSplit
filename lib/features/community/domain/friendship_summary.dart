enum FriendshipStatus {
  canSend,
  incomingPending,
  outgoingPending,
  friends,
  unavailable,
}

class FriendshipSummary {
  const FriendshipSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.status,
    required this.version,
    required this.stateChangedAt,
  });

  final String id;
  final String username;
  final String displayName;
  final FriendshipStatus status;
  final int? version;
  final DateTime? stateChangedAt;
}
