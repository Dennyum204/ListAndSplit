import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAccountRealtimeGateway implements AccountRealtimeGateway {
  SupabaseAccountRealtimeGateway(this._client);

  final SupabaseClient _client;

  @override
  AccountRealtimeSubscription subscribe({
    required String authenticatedProfileId,
    required void Function() onInvalidation,
    required void Function(AccountRealtimeStatus status) onStatus,
  }) {
    final channel = _client.channel(
      accountRealtimeTopic(authenticatedProfileId),
      opts: const RealtimeChannelConfig(private: true),
    );
    channel
        .onBroadcast(
          event: accountInvalidationEvent,
          callback: (envelope) {
            if (isAccountInvalidationEnvelope(envelope)) onInvalidation();
          },
        )
        .subscribe((status, _) => onStatus(_mapStatus(status)));
    return _SupabaseAccountRealtimeSubscription(_client, channel);
  }

  AccountRealtimeStatus _mapStatus(RealtimeSubscribeStatus status) =>
      switch (status) {
        RealtimeSubscribeStatus.subscribed => AccountRealtimeStatus.subscribed,
        RealtimeSubscribeStatus.channelError =>
          AccountRealtimeStatus.channelError,
        RealtimeSubscribeStatus.timedOut => AccountRealtimeStatus.timedOut,
        RealtimeSubscribeStatus.closed => AccountRealtimeStatus.closed,
      };
}

class _SupabaseAccountRealtimeSubscription
    implements AccountRealtimeSubscription {
  _SupabaseAccountRealtimeSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.removeChannel(_channel);
  }
}

final accountRealtimeGatewayProvider = Provider<AccountRealtimeGateway>(
  (ref) => SupabaseAccountRealtimeGateway(ref.watch(supabaseClientProvider)),
);
