import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/bounded_realtime_websocket_transport.dart';
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

      const transport = BoundedRealtimeWebSocketTransport();
      final realtimeOptions = RealtimeClientOptions(
        transport: transport.connect,
      );
      final admin = SupabaseClient(
        _localUrl,
        _localSecretKey,
        realtimeClientOptions: realtimeOptions,
      );
      final userA = SupabaseClient(
        _localUrl,
        _localPublishableKey,
        realtimeClientOptions: realtimeOptions,
      );
      final userB = SupabaseClient(
        _localUrl,
        _localPublishableKey,
        realtimeClientOptions: realtimeOptions,
      );
      final anonymous = SupabaseClient(
        _localUrl,
        _localPublishableKey,
        realtimeClientOptions: realtimeOptions,
      );
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

      final userAEvents = <Map<String, dynamic>>[];
      final ownTopic = userA.channel(
        accountRealtimeTopic(userAId),
        opts: const RealtimeChannelConfig(private: true, ack: true),
      );
      channels.add((userA, ownTopic));
      ownTopic.onBroadcast(
        event: accountInvalidationEvent,
        callback: (payload) {
          if (isAccountInvalidationEnvelope(payload)) userAEvents.add(payload);
        },
      );
      expect(await _terminalJoinStatus(ownTopic),
          RealtimeSubscribeStatus.subscribed);

      final userBEvents = <Map<String, dynamic>>[];
      final ownTopicB = userB.channel(
        accountRealtimeTopic(userBId),
        opts: const RealtimeChannelConfig(private: true),
      );
      channels.add((userB, ownTopicB));
      ownTopicB.onBroadcast(
        event: accountInvalidationEvent,
        callback: (payload) {
          if (isAccountInvalidationEnvelope(payload)) userBEvents.add(payload);
        },
      );
      expect(await _terminalJoinStatus(ownTopicB),
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
      await _waitFor(() => userAEvents.isNotEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(userBEvents, isEmpty);
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

      final createdRow = Map<String, dynamic>.from(created.single as Map);
      final listId = createdRow['list_id']! as String;
      await userA.rpc(
        'send_friend_request',
        params: {
          'target_profile_id': userBId,
          'expected_relationship_version': null,
        },
      );
      await userB.rpc(
        'accept_friend_request',
        params: {
          'target_profile_id': userAId,
          'expected_relationship_version': 1,
        },
      );
      final invited = await userA.rpc(
        'invite_active_list_member',
        params: {
          'target_list_id': listId,
          'target_profile_id': userBId,
          'expected_access_version': null,
        },
      ) as List<dynamic>;
      final accessVersion =
          Map<String, dynamic>.from(invited.single as Map)['access_version']!
              as int;
      await userB.rpc(
        'accept_active_list_invitation',
        params: {
          'target_list_id': listId,
          'expected_access_version': accessVersion,
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final ownerBeforeRename = userAEvents.length;
      final memberBeforeRename = userBEvents.length;
      final current = await userA.rpc(
        'get_active_list',
        params: {'target_list_id': listId},
      ) as List<dynamic>;
      final currentVersion =
          Map<String, dynamic>.from(current.single as Map)['version']! as int;
      await userA.rpc(
        'rename_active_list',
        params: {
          'target_list_id': listId,
          'new_title': 'Renamed for accepted member',
          'expected_list_version': currentVersion,
        },
      );

      await _waitFor(() => userAEvents.length > ownerBeforeRename);
      await _waitFor(() => userBEvents.length > memberBeforeRename);
      final memberProjection = await userB.rpc(
        'get_active_list',
        params: {'target_list_id': listId},
      ) as List<dynamic>;
      expect(
        Map<String, dynamic>.from(memberProjection.single as Map)['title'],
        'Renamed for accepted member',
      );
    },
    skip: _runLocalSmoke
        ? false
        : 'requires explicit local Supabase Realtime smoke configuration',
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected Realtime event was not received.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
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
