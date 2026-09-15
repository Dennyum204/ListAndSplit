import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/profile/data/supabase_profile_avatar_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvatarAccountDataExportRepository implements AccountDataExportRepository {
  AvatarAccountDataExportRepository(this.client,
      {AvatarInvoke? invoke,
      Session? Function()? session,
      Duration requestTimeout = const Duration(seconds: 30)})
      : _session = session ?? (() => client.auth.currentSession),
        _requestTimeout = requestTimeout,
        _invoke = invoke ??
            ((method, headers, body, query) => client.functions.invoke(
                'profile-avatar',
                method: HttpMethod.values.byName(method),
                headers: headers,
                body: body,
                queryParameters: query));
  final SupabaseClient client;
  final Session? Function() _session;
  final AvatarInvoke _invoke;
  final Duration _requestTimeout;
  @override
  Future<AccountDataExportDocument> exportOwnAccountData() async {
    final session = _session();
    if (session == null) throw const AccountDataExportFailure();
    try {
      final response = await _invoke(
              'post',
              {
                'Authorization': 'Bearer ${session.accessToken}',
                'x-request-id': secureCreationRequestId()
              },
              null,
              null)
          .timeout(_requestTimeout);
      if (response.status != 200 ||
          response.data is! Map ||
          _session()?.user.id != session.user.id) {
        throw const AccountDataExportFailure();
      }
      final document = AccountDataExportDocument.fromJson(
          Map<String, dynamic>.from(response.data as Map));
      if (document.schemaVersion != 13 ||
          document.authIdentity.id != session.user.id) {
        throw const AccountDataExportFailure();
      }
      return document;
    } catch (_) {
      throw const AccountDataExportFailure();
    }
  }
}
