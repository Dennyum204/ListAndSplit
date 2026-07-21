import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _runLocalSmoke = bool.fromEnvironment('RUN_LOCAL_REALTIME_SMOKE');
const _localUrl = String.fromEnvironment('LOCAL_SUPABASE_URL');
const _localPublishableKey =
    String.fromEnvironment('LOCAL_SUPABASE_PUBLISHABLE_KEY');
const _localSecretKey = String.fromEnvironment('LOCAL_SUPABASE_SECRET_KEY');

void main() {
  test(
    'local private Broadcast authorization and mutation transport smoke',
    () async {
      expect(_localUrl, isNotEmpty);
      expect(_localPublishableKey, isNotEmpty);
      expect(_localSecretKey, isNotEmpty);

      final admin = SupabaseClient(_localUrl, _localSecretKey);
      final userA = SupabaseClient(_localUrl, _localPublishableKey);
      final userB = SupabaseClient(_localUrl, _localPublishableKey);
      final anonymous = SupabaseClient(_localUrl, _localPublishableKey);
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final emailA = 'realtime-a-$suffix@local.test';
      final emailB = 'realtime-b-$suffix@local.test';
      const password = 'local-test-password';
      String? userAId;
      String? userBId;
      final channels = <(SupabaseClient, RealtimeChannel)>[];

      addTearDown(() async {
        for (final entry in channels.reversed) {
          await entry.$1.removeChannel(entry.$2);
        }
        if (userAId != null) await admin.auth.admin.deleteUser(userAId);
        if (userBId != null) await admin.auth.admin.deleteUser(userBId);
        await userA.dispose();
        await userB.dispose();
        await anonymous.dispose();
        await admin.dispose();
      });

      userAId = (await admin.auth.admin.createUser(
        AdminUserAttributes(
          email: emailA,
          password: password,
          emailConfirm: true,
        ),
      ))
          .user!
          .id;
      userBId = (await admin.auth.admin.createUser(
        AdminUserAttributes(
          email: emailB,
          password: password,
          emailConfirm: true,
        ),
      ))
          .user!
          .id;
      await userA.auth.signInWithPassword(email: emailA, password: password);
      await userB.auth.signInWithPassword(email: emailB, password: password);
      await userA.from('profiles').update({
        'username': 'rt_a_${suffix.toString().substring(6)}',
        'display_name': 'Realtime A',
      }).eq('id', userAId);
      await userB.from('profiles').update({
        'username': 'rt_b_${suffix.toString().substring(6)}',
        'display_name': 'Realtime B',
      }).eq('id', userBId);

      final wrongTopic = userA.channel(
        accountRealtimeTopic(userBId),
        opts: const RealtimeChannelConfig(private: true),
      );
      channels.add((userA, wrongTopic));
      expect(await _terminalJoinStatus(wrongTopic),
          RealtimeSubscribeStatus.channelError);

      final anonymousTopic = anonymous.channel(
        accountRealtimeTopic(userAId),
        opts: const RealtimeChannelConfig(private: true),
      );
      channels.add((anonymous, anonymousTopic));
      expect(await _terminalJoinStatus(anonymousTopic),
          RealtimeSubscribeStatus.channelError);

      final userAEvent = Completer<Map<String, dynamic>>();
      final ownTopic = userA.channel(
        accountRealtimeTopic(userAId),
        opts: const RealtimeChannelConfig(private: true, ack: true),
      );
      channels.add((userA, ownTopic));
      ownTopic.onBroadcast(
        event: accountInvalidationEvent,
        callback: (payload) {
          if (!userAEvent.isCompleted) userAEvent.complete(payload);
        },
      );
      expect(await _terminalJoinStatus(ownTopic),
          RealtimeSubscribeStatus.subscribed);

      final userBEvent = Completer<Map<String, dynamic>>();
      final unrelatedTopic = userB.channel(
        accountRealtimeTopic(userBId),
        opts: const RealtimeChannelConfig(private: true),
      );
      channels.add((userB, unrelatedTopic));
      unrelatedTopic.onBroadcast(
        event: accountInvalidationEvent,
        callback: (payload) {
          if (!userBEvent.isCompleted) userBEvent.complete(payload);
        },
      );
      expect(await _terminalJoinStatus(unrelatedTopic),
          RealtimeSubscribeStatus.subscribed);

      final outbound = await ownTopic.sendBroadcastMessage(
        event: accountInvalidationEvent,
        payload: {'v': 1},
      );
      expect(outbound, isNot(ChannelResponse.ok));

      final requestId = secureCreationRequestId();
      final created = await userA.rpc(
        'create_active_list',
        params: {
          'new_title': 'Local Realtime smoke',
          'creation_request_id': requestId,
        },
      ) as List<dynamic>;
      expect(created, hasLength(1));
      final envelope = await userAEvent.future.timeout(
        const Duration(seconds: 10),
      );
      expect(
        isAccountInvalidationEnvelope(envelope),
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(userBEvent.isCompleted, isFalse);
      final authoritative = await userA.rpc(
        'list_active_lists',
        params: {'requested_status': 'active', 'page_size': 20},
      ) as List<dynamic>;
      expect(
        authoritative.cast<Map<String, dynamic>>().any(
              (row) => row['title'] == 'Local Realtime smoke',
            ),
        isTrue,
      );
    },
    skip: _runLocalSmoke
        ? false
        : 'requires explicit local Supabase Realtime smoke configuration',
  );
}

Future<RealtimeSubscribeStatus> _terminalJoinStatus(
  RealtimeChannel channel,
) {
  final result = Completer<RealtimeSubscribeStatus>();
  channel.subscribe((status, _) {
    if (!result.isCompleted && status != RealtimeSubscribeStatus.closed) {
      result.complete(status);
    }
  });
  return result.future.timeout(const Duration(seconds: 10));
}
