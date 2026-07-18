import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/profile/data/supabase_profile_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);

final verifiedUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authSessionProvider.select((session) {
      final user = session.valueOrNull?.user;
      return user?.isEmailVerified == true ? user?.id : null;
    }),
  );
});

final ownProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = ref.watch(verifiedUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchOwnProfile();
});
