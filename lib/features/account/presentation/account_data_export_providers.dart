import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/account/data/supabase_account_data_export_repository.dart';
import 'package:list_and_split/features/account/data/temporary_account_data_export_share_service.dart';
import 'package:list_and_split/features/account/domain/account_data_export_repository.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

final accountDataExportRepositoryProvider =
    Provider<AccountDataExportRepository>(
  (ref) => SupabaseAccountDataExportRepository(
    ref.watch(supabaseClientProvider),
  ),
);

final accountDataExportShareServiceProvider =
    Provider<AccountDataExportShareService>(
  (ref) => TemporaryAccountDataExportShareService(),
);

final accountDataExportControllerProvider = StateNotifierProvider.autoDispose<
    AccountDataExportController, AccountDataExportState>((ref) {
  final verifiedUserId = ref.watch(verifiedUserIdProvider);
  return AccountDataExportController(
    ref.watch(accountDataExportRepositoryProvider),
    ref.watch(accountDataExportShareServiceProvider),
    hasVerifiedUser: verifiedUserId != null,
  );
});
