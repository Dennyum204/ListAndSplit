import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';

void main() {
  test('account topic and application contract are exact', () {
    expect(accountRealtimeTopic('profile-123'), 'account:profile-123');
    expect(accountInvalidationEvent, 'invalidate');
    expect(accountInvalidationPayload, {'v': 1});

    expect(
        isAccountInvalidationEnvelope({
          'payload': {'v': 1}
        }),
        isTrue);
    expect(
      isAccountInvalidationEnvelope({
        'event': 'invalidate',
        'meta': {'id': '00000000-0000-4000-8000-000000000001'},
        'payload': {
          'v': 1,
          'id': '00000000-0000-4000-8000-000000000001',
        },
        'type': 'broadcast',
      }),
      isTrue,
    );
    expect(
        isAccountInvalidationEnvelope({
          'payload': {'v': 2}
        }),
        isFalse);
    expect(
      isAccountInvalidationEnvelope({
        'payload': {'v': 1, 'list_id': 'must-not-be-accepted'},
      }),
      isFalse,
    );
    expect(isAccountInvalidationEnvelope({'v': 1}), isFalse);
    expect(isAccountInvalidationEnvelope({'payload': 'invalid'}), isFalse);
    expect(
      isAccountInvalidationEnvelope({
        'v': 1,
        'id': '00000000-0000-4000-8000-000000000001',
      }),
      isTrue,
    );
    expect(
      isAccountInvalidationEnvelope({'v': 1, 'id': 'not-a-transport-uuid'}),
      isFalse,
    );
    expect(
      isAccountInvalidationEnvelope({
        'meta': {'id': '00000000-0000-4000-8000-000000000002'},
        'payload': {
          'v': 1,
          'id': '00000000-0000-4000-8000-000000000001',
        },
      }),
      isFalse,
    );
  });

  test('transport errors become privacy-safe status context', () {
    const secretToken = 'secret-user-jwt';
    const accountId = '00000000-0000-4000-8000-000000000099';
    const topic = 'account:$accountId';
    const payload = '{"amount_minor":9900}';
    final update = AccountRealtimeStatusUpdate.fromTransport(
      AccountRealtimeStatus.channelError,
      error: Exception('$secretToken $topic $payload'),
    );
    final diagnostic = AccountRealtimeDiagnostic(
      update: update,
      action: AccountRealtimeRecoveryAction.recoveryScheduled,
    );

    expect(update.status, AccountRealtimeStatus.channelError);
    expect(update.errorReported, isTrue);
    expect(
      update.toString(),
      'AccountRealtimeStatusUpdate('
      'status: channelError, errorReported: true)',
    );
    expect(
      diagnostic.message,
      '[account-realtime] '
      'status=channelError '
      'error=reported '
      'action=recoveryScheduled',
    );
    for (final privateValue in [
      secretToken,
      accountId,
      topic,
      payload,
      '9900'
    ]) {
      expect(update.toString(), isNot(contains(privateValue)));
      expect(diagnostic.message, isNot(contains(privateValue)));
    }
  });

  test('missing transport error remains explicit without invented details', () {
    final update = AccountRealtimeStatusUpdate.fromTransport(
      AccountRealtimeStatus.timedOut,
    );

    expect(update.status, AccountRealtimeStatus.timedOut);
    expect(update.errorReported, isFalse);
    expect(update.toString(), contains('errorReported: false'));
  });

  test('only the Supabase adapter may access Realtime channel APIs', () {
    const adapter = 'lib/core/realtime/supabase_account_realtime_gateway.dart';
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final normalized = file.path.replaceAll('\\', '/');
      if (normalized == adapter) continue;
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('.channel(')),
        reason: '${file.path} must not create Supabase channels.',
      );
      expect(
        source,
        isNot(contains('RealtimeChannel')),
        reason: '${file.path} must stay behind the injected gateway.',
      );
      expect(
        source,
        isNot(contains('.sendBroadcastMessage(')),
        reason: '${file.path} must not expose an outbound Broadcast path.',
      );
    }

    final adapterSource = File(adapter).readAsStringSync();
    expect(adapterSource, contains('RealtimeChannelConfig(private: true)'));
    expect(adapterSource, contains('event: accountInvalidationEvent'));
    expect(
      adapterSource,
      contains('AccountRealtimeStatusUpdate.fromTransport'),
    );
    expect(adapterSource, isNot(contains('.send(')));
    expect(adapterSource, isNot(contains('onPresence')));
    expect(adapterSource, isNot(contains('onPostgresChanges')));
  });
}
