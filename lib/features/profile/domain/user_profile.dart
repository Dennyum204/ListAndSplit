class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.onboardingCompletedAt,
  });

  final String id;
  final String? username;
  final String? displayName;
  final DateTime? onboardingCompletedAt;

  bool get isOnboardingComplete =>
      username != null && displayName != null && onboardingCompletedAt != null;
}
