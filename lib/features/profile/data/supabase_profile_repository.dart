import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  static const _profileColumns =
      'id, username, display_name, onboarding_completed_at';

  @override
  Future<UserProfile> fetchOwnProfile() async {
    try {
      final response = await _client
          .from('profiles')
          .select(_profileColumns)
          .eq('id', _currentUserId)
          .single();
      return _mapProfile(response);
    } catch (_) {
      throw const ProfileFailure(ProfileFailureCode.generic);
    }
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String username,
    required String displayName,
  }) =>
      _update({
        'username': username,
        'display_name': displayName,
      });

  @override
  Future<UserProfile> updateDisplayName({required String displayName}) =>
      _update({'display_name': displayName});

  String get _currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const ProfileFailure(ProfileFailureCode.generic);
    return id;
  }

  Future<UserProfile> _update(Map<String, dynamic> values) async {
    try {
      final response = await _client
          .from('profiles')
          .update(values)
          .eq('id', _currentUserId)
          .select(_profileColumns)
          .single();
      return _mapProfile(response);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const ProfileFailure(ProfileFailureCode.usernameUnavailable);
      }
      throw const ProfileFailure(ProfileFailureCode.generic);
    } catch (_) {
      throw const ProfileFailure(ProfileFailureCode.generic);
    }
  }

  UserProfile _mapProfile(Map<String, dynamic> json) => UserProfile(
        id: json['id']! as String,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        onboardingCompletedAt: json['onboarding_completed_at'] == null
            ? null
            : DateTime.parse(json['onboarding_completed_at']! as String),
      );
}
