import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/lists/data/supabase_active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

final activeListChatRepositoryProvider = Provider<ActiveListChatRepository>(
  (ref) => SupabaseActiveListChatRepository(ref.watch(supabaseClientProvider)),
);

final activeListChatControllerProvider = StateNotifierProvider.autoDispose
    .family<ActiveListChatController, ActiveListChatState, String>(
  (ref, listId) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = ActiveListChatController(
      ref.watch(activeListChatRepositoryProvider),
      listId,
      refreshUnread: () => ref
          .read(activeListChatUnreadControllerProvider(listId).notifier)
          .reconcile(),
    );
    if (userId != null) {
      registerForReconciliation(
        ref,
        controller.reconcile,
        scope: ReconciliationScope.chat,
      );
      unawaited(controller.load());
    }
    return controller;
  },
);

final activeListChatUnreadControllerProvider = StateNotifierProvider.autoDispose
    .family<ActiveListChatUnreadController,
        AsyncValue<ActiveListChatUnreadCount>, String>(
  (ref, listId) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = ActiveListChatUnreadController(
      ref.watch(activeListChatRepositoryProvider),
      listId,
    );
    if (userId != null) {
      registerForReconciliation(
        ref,
        controller.reconcile,
        scope: ReconciliationScope.chat,
      );
      unawaited(controller.load());
    }
    return controller;
  },
);
