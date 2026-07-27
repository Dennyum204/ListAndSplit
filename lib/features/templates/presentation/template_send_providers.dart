import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/data/supabase_template_send_repository.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/template_sends_controller.dart';

final templateSendRepositoryProvider = Provider<TemplateSendRepository>(
  (ref) => SupabaseTemplateSendRepository(ref.watch(supabaseClientProvider)),
);

final templateSendsRefreshSignalProvider = StateProvider<int>((ref) => 0);
final templateSendDetailRefreshSignalProvider =
    StateProvider.autoDispose.family<int, String>((ref, _) => 0);

final invalidateTemplateSendsProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(templateSendsRefreshSignalProvider.notifier).state += 1;
  };
});

final sharedTemplateSendsControllerProvider = StateNotifierProvider<
    SharedTemplateSendsController, SharedTemplateSendsState>((ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = SharedTemplateSendsController(
    ref.watch(templateSendRepositoryProvider),
    hasAuthenticatedUser: userId != null,
    invalidateNotifications: ref.watch(invalidateNotificationsProvider),
  );
  ref.listen<int>(templateSendsRefreshSignalProvider, (_, __) {
    unawaited(controller.reconcile());
  });
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});

final templateSendComposerControllerProvider = StateNotifierProvider.autoDispose
    .family<TemplateSendComposerController, TemplateSendComposerState, String>(
  (ref, templateId) {
    final controller = TemplateSendComposerController(
      ref.watch(templateSendRepositoryProvider),
      templateId,
      invalidateShared: ref.watch(invalidateTemplateSendsProvider),
      invalidateNotifications: ref.watch(invalidateNotificationsProvider),
    );
    if (ref.watch(verifiedUserIdProvider) != null) {
      unawaited(controller.loadRecipients());
    }
    return controller;
  },
);

final receivedTemplateSendControllerProvider = StateNotifierProvider.autoDispose
    .family<ReceivedTemplateSendController, ReceivedTemplateSendState, String>(
  (ref, templateSendId) {
    final controller = ReceivedTemplateSendController(
      ref.watch(templateSendRepositoryProvider),
      templateSendId,
      invalidateShared: ref.watch(invalidateTemplateSendsProvider),
      invalidateTemplates: ref.watch(invalidatePrivateTemplatesProvider),
      invalidateNotifications: ref.watch(invalidateNotificationsProvider),
    );
    ref.listen<int>(
      templateSendDetailRefreshSignalProvider(templateSendId),
      (_, __) => unawaited(controller.reconcile()),
    );
    registerForReconciliation(ref, controller.reconcile);
    if (ref.watch(verifiedUserIdProvider) != null) {
      unawaited(controller.load());
    }
    return controller;
  },
);
