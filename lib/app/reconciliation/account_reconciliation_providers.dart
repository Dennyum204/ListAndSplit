import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_coordinator.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/realtime/supabase_account_realtime_gateway.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

final realtimeAccountIdProvider = Provider<String?>((ref) {
  final authenticatedId = ref.watch(verifiedUserIdProvider);
  final profile = ref.watch(ownProfileProvider).valueOrNull;
  if (authenticatedId == null ||
      profile?.id != authenticatedId ||
      profile?.isOnboardingComplete != true) {
    return null;
  }
  return authenticatedId;
});

final accountReconciliationCoordinatorProvider =
    Provider<AccountReconciliationCoordinator>((ref) {
  final coordinator = AccountReconciliationCoordinator(
    ref.watch(accountRealtimeGatewayProvider),
    ref.watch(reconciliationRegistryProvider),
  );
  ref.listen<String?>(
    realtimeAccountIdProvider,
    (_, accountId) => coordinator.setAccount(accountId),
    fireImmediately: true,
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});
