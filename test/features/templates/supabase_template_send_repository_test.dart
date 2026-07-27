import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/templates/data/supabase_template_send_repository.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Map<String, Object?> responses;
  late Object? failure;
  late SupabaseTemplateSendRepository repository;

  setUp(() {
    calls = [];
    responses = {};
    failure = null;
    repository = SupabaseTemplateSendRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return responses[functionName] ?? const [];
      },
    );
  });

  test('lists eligible recipients with the exact keyset contract', () async {
    responses['list_eligible_template_send_recipients'] = [
      _profileRow(),
    ];
    const cursor = TemplateSendRecipientCursor(
      username: 'alpha_friend',
      profileId: _cursorProfileId,
    );

    final recipients = await repository.listEligibleRecipients(
      _sourceTemplateId,
      pageSize: 7,
      cursor: cursor,
    );

    expect(calls.single.functionName, 'list_eligible_template_send_recipients');
    expect(calls.single.params, {
      'target_template_id': _sourceTemplateId,
      'page_size': 7,
      'after_username': 'alpha_friend',
      'after_profile_id': _cursorProfileId,
    });
    expect(recipients.single.id, _senderProfileId);
    expect(recipients.single.username, 'beta_friend');
  });

  test('sends one template with payload-bound version and request identity',
      () async {
    responses['send_template_to_friend'] = [
      _sendResultRow(),
    ];

    final result = await repository.sendTemplate(
      _sourceTemplateId,
      _recipientProfileId,
      expectedTemplateVersion: 4,
      requestId: _requestId,
    );

    expect(calls.single.functionName, 'send_template_to_friend');
    expect(calls.single.params, {
      'source_template_id': _sourceTemplateId,
      'recipient_profile_id': _recipientProfileId,
      'expected_template_version': 4,
      'request_id': _requestId,
    });
    expect(result.id, _templateSendId);
    expect(result.state, TemplateSendState.pending);
    expect(result.snapshotName, 'Beach trip');
    expect(result.itemCount, 2);
  });

  test('lists received and sent projections without copy provenance', () async {
    responses['list_received_template_sends'] = [
      _receivedRow(),
    ];
    final received = await repository.listReceived();

    expect(calls.single.params, {
      'state_filter': 'pending',
      'page_size': 20,
      'before_state_changed_at': null,
      'before_template_send_id': null,
    });
    expect(received.single.sender.id, _senderProfileId);
    expect(received.single.state, TemplateSendState.pending);

    calls.clear();
    responses['list_sent_template_sends'] = [
      _sentRow(state: 'accepted', version: 2),
    ];
    final sent = await repository.listSent(
      filter: TemplateSendHistoryFilter.history,
      cursor: TemplateSendCursor(
        stateChangedAt: DateTime.utc(2026, 7, 28),
        templateSendId: _cursorSendId,
      ),
    );

    expect(calls.single.params, {
      'state_filter': 'history',
      'page_size': 20,
      'before_state_changed_at': '2026-07-28T00:00:00.000Z',
      'before_template_send_id': _cursorSendId,
    });
    expect(sent.single.recipient.id, _recipientProfileId);
    expect(sent.single.state, TemplateSendState.accepted);
  });

  test('loads strict received detail with immutable ordered snapshot items',
      () async {
    responses['get_received_template_send'] = _detailDocument();

    final detail = await repository.getReceived(_templateSendId);

    expect(calls.single.functionName, 'get_received_template_send');
    expect(calls.single.params, {
      'target_template_send_id': _templateSendId,
    });
    expect(detail.summary.sender.username, 'beta_friend');
    expect(detail.acceptedTemplateId, isNull);
    expect(detail.items.map((item) => item.name), ['Water', 'Water']);
    expect(
      detail.items.map((item) => item.quantity.thousandths),
      [1500, 2000],
    );
  });

  test('accepts once and parses only the recipient copy identity', () async {
    responses['accept_template_send'] = [
      {
        'template_send_id': _templateSendId,
        'state': 'accepted',
        'version': 2,
        'accepted_template_id': _acceptedTemplateId,
        'state_changed_at': '2026-07-27T12:00:00.000Z',
      },
    ];

    final result = await repository.accept(
      _templateSendId,
      expectedVersion: 1,
      requestId: _requestId,
    );

    expect(calls.single.functionName, 'accept_template_send');
    expect(calls.single.params, {
      'target_template_send_id': _templateSendId,
      'expected_template_send_version': 1,
      'request_id': _requestId,
    });
    expect(result.state, TemplateSendState.accepted);
    expect(result.acceptedTemplateId, _acceptedTemplateId);
  });

  test('declines and revokes through their exact terminal RPCs', () async {
    responses['decline_template_send'] = [
      _terminalResultRow('declined'),
    ];
    final declined = await repository.decline(
      _templateSendId,
      expectedVersion: 1,
      requestId: _requestId,
    );
    expect(declined.state, TemplateSendState.declined);
    expect(calls.single.functionName, 'decline_template_send');

    calls.clear();
    responses['revoke_template_send'] = [
      _terminalResultRow('revoked'),
    ];
    final revoked = await repository.revoke(
      _templateSendId,
      expectedVersion: 1,
      requestId: _requestId,
    );
    expect(revoked.state, TemplateSendState.revoked);
    expect(calls.single.functionName, 'revoke_template_send');
  });

  test('rejects response fields that would expose source provenance', () async {
    responses['list_sent_template_sends'] = [
      _sentRow()..['source_template_id'] = _sourceTemplateId,
    ];

    await expectLater(
      repository.listSent(),
      throwsA(
        isA<TemplateSendFailure>().having(
          (value) => value.code,
          'code',
          TemplateSendFailureCode.generic,
        ),
      ),
    );

    responses['get_received_template_send'] = _detailDocument()
      ..['source_template_id'] = _sourceTemplateId;
    await expectLater(
      repository.getReceived(_templateSendId),
      throwsA(isA<TemplateSendFailure>()),
    );
  });

  test('rejects oversized, inconsistent, duplicated and unstable pages',
      () async {
    responses['list_received_template_sends'] = [
      _receivedRow(),
      _receivedRow(),
    ];
    await expectLater(
      repository.listReceived(),
      throwsA(isA<TemplateSendFailure>()),
    );

    responses['list_received_template_sends'] = [
      _receivedRow(state: 'declined'),
    ];
    await expectLater(
      repository.listReceived(),
      throwsA(isA<TemplateSendFailure>()),
    );

    responses['list_sent_template_sends'] = [
      _sentRow(),
      _sentRow()
        ..['template_send_id'] = _cursorSendId
        ..['state_changed_at'] = '2026-07-27T13:00:00.000Z',
    ];
    await expectLater(
      repository.listSent(),
      throwsA(isA<TemplateSendFailure>()),
    );

    responses['list_eligible_template_send_recipients'] = [
      _profileRow(),
      _profileRow(),
    ];
    await expectLater(
      repository.listEligibleRecipients(_sourceTemplateId),
      throwsA(isA<TemplateSendFailure>()),
    );
  });

  test('rejects invalid detail counts, item ordering and accepted state',
      () async {
    responses['get_received_template_send'] = _detailDocument()
      ..['snapshot_item_count'] = 1;
    await expectLater(
      repository.getReceived(_templateSendId),
      throwsA(isA<TemplateSendFailure>()),
    );

    final unordered = _detailDocument();
    ((unordered['items']! as List)[1] as Map<String, dynamic>)['position'] = 1;
    responses['get_received_template_send'] = unordered;
    await expectLater(
      repository.getReceived(_templateSendId),
      throwsA(isA<TemplateSendFailure>()),
    );

    responses['accept_template_send'] = [
      {
        'template_send_id': _templateSendId,
        'state': 'accepted',
        'version': 2,
        'accepted_template_id': null,
        'state_changed_at': '2026-07-27T12:00:00.000Z',
      },
    ];
    await expectLater(
      repository.accept(
        _templateSendId,
        expectedVersion: 1,
        requestId: _requestId,
      ),
      throwsA(isA<TemplateSendFailure>()),
    );
  });

  test('maps every stable SQLSTATE without exposing backend details', () async {
    for (final entry in const {
      '22023': TemplateSendFailureCode.invalid,
      'P0002': TemplateSendFailureCode.unavailable,
      '42501': TemplateSendFailureCode.unavailable,
      '40001': TemplateSendFailureCode.stale,
      '23505': TemplateSendFailureCode.retryConflict,
      '54000': TemplateSendFailureCode.capacity,
      '55000': TemplateSendFailureCode.noLongerPending,
    }.entries) {
      failure = PostgrestException(
        message: 'private database detail',
        code: entry.key,
      );
      await expectLater(
        repository.listReceived(),
        throwsA(
          isA<TemplateSendFailure>()
              .having((value) => value.code, 'code', entry.value)
              .having(
                (value) => value.toString(),
                'message',
                isNot(contains('private database detail')),
              ),
        ),
      );
    }
  });

  test('maps the reviewed pending-send uniqueness error distinctly', () async {
    failure = const PostgrestException(
      message: 'pending template send already exists',
      code: '23505',
    );

    await expectLater(
      repository.sendTemplate(
        _sourceTemplateId,
        _recipientProfileId,
        expectedTemplateVersion: 3,
        requestId: _requestId,
      ),
      throwsA(
        isA<TemplateSendFailure>().having(
          (value) => value.code,
          'code',
          TemplateSendFailureCode.duplicatePending,
        ),
      ),
    );
  });

  test('maps malformed data separately from transport failures', () async {
    responses['list_received_template_sends'] = 'not rows';
    await expectLater(
      repository.listReceived(),
      throwsA(
        isA<TemplateSendFailure>().having(
          (value) => value.code,
          'code',
          TemplateSendFailureCode.generic,
        ),
      ),
    );

    failure = StateError('offline');
    await expectLater(
      repository.listReceived(),
      throwsA(
        isA<TemplateSendFailure>().having(
          (value) => value.code,
          'code',
          TemplateSendFailureCode.transport,
        ),
      ),
    );
  });
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}

Map<String, dynamic> _profileRow() => {
      'profile_id': _senderProfileId,
      'username': 'beta_friend',
      'display_name': 'Beta Friend',
    };

Map<String, dynamic> _sendResultRow() => {
      'template_send_id': _templateSendId,
      'state': 'pending',
      'version': 1,
      'snapshot_name': 'Beach trip',
      'snapshot_item_count': 2,
      'created_at': '2026-07-27T11:00:00.000Z',
      'state_changed_at': '2026-07-27T11:00:00.000Z',
    };

Map<String, dynamic> _receivedRow({
  String state = 'pending',
  int version = 1,
}) =>
    {
      'template_send_id': _templateSendId,
      'sender_profile_id': _senderProfileId,
      'sender_username': 'beta_friend',
      'sender_display_name': 'Beta Friend',
      'snapshot_name': 'Beach trip',
      'snapshot_item_count': 2,
      'state': state,
      'version': version,
      'created_at': '2026-07-27T11:00:00.000Z',
      'state_changed_at': '2026-07-27T11:00:00.000Z',
    };

Map<String, dynamic> _sentRow({
  String state = 'pending',
  int version = 1,
}) =>
    {
      'template_send_id': _templateSendId,
      'recipient_profile_id': _recipientProfileId,
      'recipient_username': 'recipient_friend',
      'recipient_display_name': 'Recipient Friend',
      'snapshot_name': 'Beach trip',
      'snapshot_item_count': 2,
      'state': state,
      'version': version,
      'created_at': '2026-07-27T11:00:00.000Z',
      'state_changed_at': '2026-07-27T11:00:00.000Z',
    };

Map<String, dynamic> _detailDocument() => {
      'template_send_id': _templateSendId,
      'sender': _profileRow(),
      'snapshot_name': 'Beach trip',
      'snapshot_item_count': 2,
      'state': 'pending',
      'version': 1,
      'accepted_template_id': null,
      'created_at': '2026-07-27T11:00:00.000Z',
      'state_changed_at': '2026-07-27T11:00:00.000Z',
      'items': [
        {
          'name': 'Water',
          'quantity_thousandths': 1500,
          'position': 1,
        },
        {
          'name': 'Water',
          'quantity_thousandths': 2000,
          'position': 2,
        },
      ],
    };

Map<String, dynamic> _terminalResultRow(String state) => {
      'template_send_id': _templateSendId,
      'state': state,
      'version': 2,
      'state_changed_at': '2026-07-27T12:00:00.000Z',
    };

const _sourceTemplateId = '11111111-1111-4111-8111-111111111111';
const _templateSendId = '22222222-2222-4222-8222-222222222222';
const _cursorSendId = '33333333-3333-4333-8333-333333333333';
const _senderProfileId = '44444444-4444-4444-8444-444444444444';
const _recipientProfileId = '55555555-5555-4555-8555-555555555555';
const _cursorProfileId = '33333333-3333-4333-8333-333333333333';
const _acceptedTemplateId = '66666666-6666-4666-8666-666666666666';
const _requestId = '77777777-7777-4777-8777-777777777777';
