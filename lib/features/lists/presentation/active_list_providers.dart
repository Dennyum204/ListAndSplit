import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/lists/data/supabase_active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

final activeListRepositoryProvider = Provider<ActiveListRepository>(
  (ref) => SupabaseActiveListRepository(ref.watch(supabaseClientProvider)),
);

final activeListsRefreshSignalProvider = StateProvider<int>((ref) => 0);

final invalidateActiveListsProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(activeListsRefreshSignalProvider.notifier).state += 1;
  };
});

final activeListsControllerProvider =
    StateNotifierProvider.autoDispose<ActiveListsController, ActiveListsState>(
        (ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  ref.watch(activeListsRefreshSignalProvider);
  final controller = ActiveListsController(
    ref.watch(activeListRepositoryProvider),
    hasAuthenticatedUser: userId != null,
  );
  if (userId != null) unawaited(controller.loadAll());
  return controller;
});

final activeListDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ActiveListDetailController, ActiveListDetailState, String>(
  (ref, listId) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = ActiveListDetailController(
      ref.watch(activeListRepositoryProvider),
      listId,
      invalidateLists: ref.watch(invalidateActiveListsProvider),
    );
    if (userId != null) unawaited(controller.load());
    return controller;
  },
);
