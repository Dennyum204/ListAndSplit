import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/community/data/supabase_friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';

final friendshipRepositoryProvider = Provider<FriendshipRepository>(
  (ref) => SupabaseFriendshipRepository(ref.watch(supabaseClientProvider)),
);

/// Incremented by search mutations so an open friendship-management surface
/// reconstructs and reloads without depending on the search controller.
final friendshipManagementRefreshSignalProvider =
    StateProvider<int>((ref) => 0);

/// Incremented by management mutations so an open exact-search result can
/// refresh without depending on the management controller.
final communitySearchRefreshSignalProvider = StateProvider<int>((ref) => 0);

final invalidateFriendshipManagementProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(friendshipManagementRefreshSignalProvider.notifier).update(
          (revision) => revision + 1,
        );
  };
});

final invalidateCommunitySearchProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(communitySearchRefreshSignalProvider.notifier).update(
          (revision) => revision + 1,
        );
  };
});
