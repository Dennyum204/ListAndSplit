import 'package:list_and_split/features/profile/domain/user_profile.dart';

enum ProfileFailureCode { usernameUnavailable, generic }

class ProfileFailure implements Exception {
  const ProfileFailure(this.code);

  final ProfileFailureCode code;
}

abstract interface class ProfileRepository {
  Future<UserProfile> fetchOwnProfile();

  Future<UserProfile> completeOnboarding({
    required String username,
    required String displayName,
  });

  Future<UserProfile> updateDisplayName({required String displayName});
}
