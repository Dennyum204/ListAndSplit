import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/data/supabase_private_template_repository.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_templates_controller.dart';

final privateTemplateRepositoryProvider = Provider<PrivateTemplateRepository>(
  (ref) => SupabasePrivateTemplateRepository(
    ref.watch(supabaseClientProvider),
  ),
);

final privateTemplatesRefreshSignalProvider = StateProvider<int>((ref) => 0);
final privateTemplateDetailRefreshSignalProvider =
    StateProvider.autoDispose.family<int, String>((ref, _) => 0);

final invalidatePrivateTemplatesProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(privateTemplatesRefreshSignalProvider.notifier).state += 1;
  };
});

final privateTemplatesControllerProvider =
    StateNotifierProvider<PrivateTemplatesController, PrivateTemplatesState>(
        (ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = PrivateTemplatesController(
    ref.watch(privateTemplateRepositoryProvider),
    hasAuthenticatedUser: userId != null,
  );
  ref.listen<int>(privateTemplatesRefreshSignalProvider, (_, __) {
    unawaited(controller.reconcile());
  });
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});

final privateTemplateDetailControllerProvider =
    StateNotifierProvider.autoDispose.family<PrivateTemplateDetailController,
        PrivateTemplateDetailState, String>(
  (ref, templateId) {
    final controller = PrivateTemplateDetailController(
      ref.watch(privateTemplateRepositoryProvider),
      ref.watch(activeListRepositoryProvider),
      templateId,
      invalidateTemplates: ref.watch(invalidatePrivateTemplatesProvider),
      invalidateLists: ref.watch(invalidateActiveListsProvider),
      invalidateListDetail: (listId) {
        ref
            .read(activeListDetailRefreshSignalProvider(listId).notifier)
            .state += 1;
      },
    );
    ref.listen<int>(privateTemplateDetailRefreshSignalProvider(templateId),
        (_, __) {
      unawaited(controller.reconcile());
    });
    registerForReconciliation(ref, controller.reconcile);
    if (ref.watch(verifiedUserIdProvider) != null) unawaited(controller.load());
    return controller;
  },
);
