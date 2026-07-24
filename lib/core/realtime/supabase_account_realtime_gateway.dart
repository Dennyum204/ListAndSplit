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
    required void Function(AccountRealtimeStatusUpdate update) onStatus,
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
        .subscribe(
          (status, error) => onStatus(
            AccountRealtimeStatusUpdate.fromTransport(
              _mapStatus(status),
              error: error,
            ),
          ),
        );
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
  Future<void>? _closeFuture;
  bool _closed = false;

  @override
  Future<void> close() {
    if (_closed) return Future<void>.value();
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      // Coordinator replacement supersedes the SDK's pending socket retry.
      // Cancel it before teardown so it cannot race the replacement channel.
      _client.realtime.reconnectTimer.reset();
      await _channel.unsubscribe();
      if (_client.realtime.getChannels().isEmpty) {
        // The application owns one account channel. Awaiting disconnect here
        // serializes replacement behind teardown; the configured transport's
        // bounded ready deadline also bounds a disconnect from a stalled
        // handshake. The pinned client does not discard pushes buffered by a
        // connection that never opened, so clear that receive-only channel's
        // stale join before creating its replacement.
        await _client.realtime.disconnect();
        _client.realtime.sendBuffer.clear();
      }
      _closed = true;
    } finally {
      _closeFuture = null;
    }
  }
}

final accountRealtimeGatewayProvider = Provider<AccountRealtimeGateway>(
  (ref) => SupabaseAccountRealtimeGateway(ref.watch(supabaseClientProvider)),
);
