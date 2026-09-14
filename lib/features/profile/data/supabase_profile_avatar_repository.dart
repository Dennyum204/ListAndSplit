import 'dart:typed_data';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AvatarInvoke = Future<FunctionResponse> Function(String method,
    Map<String, String> headers, Uint8List? body, Map<String, String>? query);

class SupabaseProfileAvatarRepository implements ProfileAvatarRepository {
  SupabaseProfileAvatarRepository(this.client,
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
  final AvatarInvoke _invoke;
  final Session? Function() _session;
  final Duration _requestTimeout;
  @override
  Future<ProfileAvatarMetadata> metadata() async {
    final actor = _session()?.user.id;
    if (actor == null) throw const AvatarFailure(AvatarFailureKind.unavailable);
    try {
      final result = await client
          .rpc<Object?>('get_own_profile_avatar')
          .timeout(_requestTimeout);
      if (_session()?.user.id != actor) throw const AvatarFailure();
      return ProfileAvatarMetadata.fromJson(result);
    } catch (_) {
      throw const AvatarFailure();
    }
  }

  @override
  Future<Uint8List?> read(AvatarTarget target) async {
    final session = _session();
    if (session == null) return null;
    try {
      final response = await _invoke(
          'get',
          {'Authorization': 'Bearer ${session.accessToken}'},
          null,
          {'kind': target.kind, 'id': target.id}).timeout(_requestTimeout);
      if (_session()?.user.id != session.user.id) return null;
      if (response.status == 404) return null;
      if (response.status != 200 ||
          response.data is! Uint8List ||
          (response.data as Uint8List).length < 57 ||
          (response.data as Uint8List).length > 327680) {
        throw const AvatarFailure();
      }
      return response.data as Uint8List;
    } on FunctionException catch (error) {
      if (error.status == 404 || error.status == 401 || error.status == 403) {
        return null;
      }
      throw const AvatarFailure();
    } catch (_) {
      throw const AvatarFailure();
    }
  }

  Future<ProfileAvatarMetadata> _mutate(String method, Uint8List? bytes,
      int version, String requestId, String expectedUser) async {
    final session = _session();
    if (session == null || session.user.id != expectedUser) {
      throw const AvatarFailure(AvatarFailureKind.unavailable);
    }
    try {
      final response = await _invoke(
              method,
              {
                'Authorization': 'Bearer ${session.accessToken}',
                'if-match': version.toString(),
                'x-request-id': requestId,
                // FunctionsClient checks this exact spelling before choosing its
                // default binary MIME. Lowercase is overwritten as octet-stream.
                if (bytes != null) 'Content-Type': 'image/png',
              },
              bytes,
              null)
          .timeout(_requestTimeout);
      if (_session()?.user.id != expectedUser || response.status != 200) {
        throw const AvatarFailure();
      }
      return ProfileAvatarMetadata.fromJson(response.data);
    } on FunctionException catch (error) {
      final code =
          error.details is Map ? (error.details as Map)['error'] : null;
      throw AvatarFailure(switch (code) {
        'stale' => AvatarFailureKind.stale,
        'busy' => AvatarFailureKind.busy,
        'invalid_image' => AvatarFailureKind.invalidImage,
        _ => AvatarFailureKind.retryable,
      });
    } on AvatarFailure {
      rethrow;
    } catch (_) {
      throw const AvatarFailure();
    }
  }

  @override
  Future<ProfileAvatarMetadata> replace(
          Uint8List png, int version, String requestId, String expectedUser) =>
      _mutate('put', png, version, requestId, expectedUser);
  @override
  Future<ProfileAvatarMetadata> remove(
          int version, String requestId, String expectedUser) =>
      _mutate('delete', null, version, requestId, expectedUser);
}
