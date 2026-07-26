import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/moderation/data/supabase_public_template_moderation_repository.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';

final publicTemplateModerationRepositoryProvider =
    Provider<PublicTemplateModerationRepository>(
  (ref) => SupabasePublicTemplateModerationRepository(
    ref.watch(supabaseClientProvider),
  ),
);

final moderationAccessControllerProvider = StateNotifierProvider.autoDispose<
    ModerationAccessController, AsyncValue<bool>>((ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = ModerationAccessController(
    ref.watch(publicTemplateModerationRepositoryProvider),
    hasAuthenticatedUser: userId != null,
  );
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});

final moderationQueueRefreshSignalProvider = StateProvider<int>((ref) => 0);

final moderationQueueControllerProvider = StateNotifierProvider.autoDispose<
    ModerationQueueController, ModerationQueueState>((ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  ref.watch(moderationQueueRefreshSignalProvider);
  final controller = ModerationQueueController(
    ref.watch(publicTemplateModerationRepositoryProvider),
    hasAuthenticatedUser: userId != null,
  );
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});

final moderationCaseControllerProvider = StateNotifierProvider.autoDispose
    .family<ModerationCaseController, ModerationCaseState, String>(
  (ref, groupId) {
    final userId = ref.watch(verifiedUserIdProvider);
    final controller = ModerationCaseController(
      ref.watch(publicTemplateModerationRepositoryProvider),
      groupId,
      hasAuthenticatedUser: userId != null,
      invalidateQueue: () {
        ref.read(moderationQueueRefreshSignalProvider.notifier).state++;
      },
      invalidateOwnerState: () {
        ref.read(invalidatePrivateTemplatesProvider)();
        ref.read(invalidateNotificationsProvider)();
      },
    );
    registerForReconciliation(ref, controller.reconcile);
    if (userId != null) unawaited(controller.load());
    return controller;
  },
);
