import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/account/data/supabase_account_deletion_repository.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => SupabaseAccountDeletionRepository(
    ref.watch(supabaseClientProvider),
  ),
);

final accountDeletionImpactProvider =
    FutureProvider.autoDispose<AccountDeletionListImpact>((ref) async {
  final repository = ref.watch(accountDeletionRepositoryProvider);
  if (repository is AccountDeletionImpactRepository) {
    return (repository as AccountDeletionImpactRepository).getListImpact();
  }
  return const AccountDeletionListImpact(
    ownedSharedListCount: 0,
    affectedParticipantCount: 0,
  );
});

final accountDeletionControllerProvider = StateNotifierProvider.autoDispose<
    AccountDeletionController, AccountDeletionState>((ref) {
  final user = ref.watch(
    authSessionProvider.select((session) => session.valueOrNull?.user),
  );
  return AccountDeletionController(
    () => ref.read(accountDeletionRepositoryProvider),
    hasVerifiedUser: user?.isEmailVerified == true,
    onDeleted: ref.watch(resetSessionStateProvider),
  );
});
