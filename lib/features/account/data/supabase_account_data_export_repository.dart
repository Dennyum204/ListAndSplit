import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AccountDataExportRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

typedef CurrentAccountUserId = String? Function();

class SupabaseAccountDataExportRepository
    implements AccountDataExportRepository {
  SupabaseAccountDataExportRepository(
    SupabaseClient client, {
    AccountDataExportRpc? rpc,
    CurrentAccountUserId? currentUserId,
  })  : _rpc = rpc ??
            ((functionName, {params}) async {
              return client.rpc<Object?>(functionName, params: params);
            }),
        _currentUserId = currentUserId ?? (() => client.auth.currentUser?.id);

  final AccountDataExportRpc _rpc;
  final CurrentAccountUserId _currentUserId;

  @override
  Future<AccountDataExportDocument> exportOwnAccountData() async {
    final expectedUserId = _currentUserId();
    if (expectedUserId == null) throw const AccountDataExportFailure();

    try {
      final response = await _rpc('export_own_account_data');
      if (response is! Map) throw const AccountDataExportFailure();
      final document = AccountDataExportDocument.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (document.authIdentity.id != expectedUserId ||
          _currentUserId() != expectedUserId) {
        throw const AccountDataExportFailure();
      }
      return document;
    } on AccountDataExportFailure {
      rethrow;
    } catch (_) {
      throw const AccountDataExportFailure();
    }
  }
}
