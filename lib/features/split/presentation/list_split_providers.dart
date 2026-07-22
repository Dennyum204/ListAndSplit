import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/split/data/supabase_list_split_repository.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';
import 'package:list_and_split/features/split/presentation/list_split_controller.dart';

final listSplitRepositoryProvider = Provider<ListSplitRepository>(
  (ref) => SupabaseListSplitRepository(ref.watch(supabaseClientProvider)),
);

final listSplitRefreshSignalProvider =
    StateProvider.autoDispose.family<int, String>((ref, _) => 0);

final listSplitControllerProvider = StateNotifierProvider.autoDispose
    .family<ListSplitController, ListSplitState, String>((ref, listId) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = ListSplitController(
    ref.watch(listSplitRepositoryProvider),
    listId,
    authenticatedProfileId: userId ?? '',
    invalidateLists: ref.watch(invalidateActiveListsProvider),
  );
  ref.listen<int>(listSplitRefreshSignalProvider(listId), (_, __) {
    unawaited(controller.reconcile());
  });
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});
