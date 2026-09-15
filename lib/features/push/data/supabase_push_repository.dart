import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/push_repository.dart';

class SupabasePushRepository implements PushRepository {
  const SupabasePushRepository(this._client);
  final SupabaseClient _client;
  Future<void> _write(String account, PushBinding binding, bool enabled) async {
    await _client.rpc('register_push_device', params: {
      'installation_key': binding.installation,
      'binding_id': binding.binding,
      'device_token': binding.token,
      'expected_account_id': account,
      'enable_delivery': enabled,
    }).timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> register(String account, PushBinding binding) =>
      _write(account, binding, true);
  @override
  Future<void> unregister(String account, PushBinding binding) =>
      _write(account, binding, false);
  @override
  Future<PushDestination?> resolve(PushTap tap) async {
    final value = await _client.rpc('resolve_push_destination', params: {
      'target_delivery_id': tap.delivery,
      'expected_binding_id': tap.binding
    }).timeout(const Duration(seconds: 10));
    if (value is! Map) return null;
    if (value['kind'] == 'notification' && value.length == 1) {
      return const PushDestination('notification');
    }
    final id = value['list_id'];
    if (value['kind'] == 'chat' &&
        value.length == 2 &&
        id is String &&
        RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
      return PushDestination('chat', listId: id);
    }
    return null;
  }
}
