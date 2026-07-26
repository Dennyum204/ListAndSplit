import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/moderation/data/supabase_public_template_moderation_repository.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabasePublicTemplateModerationRepository repository;

  setUp(() {
    calls = [];
    response = null;
    failure = null;
    repository = SupabasePublicTemplateModerationRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('self-check uses only the protected parameterless RPC', () async {
    response = true;

    expect(await repository.isModerator(), isTrue);
    expect(calls.single.functionName, 'is_public_template_moderator');
    expect(calls.single.params, isNull);
  });

  test('maps a bounded grouped queue with exact keyset parameters', () async {
    response = _queueDocument();
    final cursor = ModerationQueueCursor(
      at: DateTime.utc(2026, 7, 26, 6, 0, 0, 123),
      groupId: _groupId,
    );

    final page = await repository.listQueue(
      ModerationQueueFilter.open,
      pageSize: 7,
      cursor: cursor,
    );

    expect(calls.single.functionName, 'list_public_template_moderation_queue');
    expect(calls.single.params, {
      'queue_filter': 'open',
      'requested_page_size': 7,
      'cursor_at': '2026-07-26T06:00:00.123Z',
      'cursor_group_id': _groupId,
    });
    expect(page.filter, ModerationQueueFilter.open);
    expect(page.cases.single.groupId, _groupId);
    expect(page.cases.single.reportCount, 2);
    expect(page.cases.single.sourceChanged, isTrue);
    expect(page.nextCursor?.groupId, _groupId);
  });

  test('maps immutable snapshot, current content and anonymized reporter',
      () async {
    response = _caseDocument(reporter: null);

    final detail = await repository.getCase(_groupId);

    expect(calls.single.functionName, 'get_public_template_moderation_case');
    expect(calls.single.params, {'target_group_id': _groupId});
    expect(detail.reportedSnapshot.name, 'Reported template');
    expect(detail.reportedSnapshot.items.single.name, 'Water');
    expect(
      detail.reportedSnapshot.items.single.quantity.thousandths,
      1500,
    );
    expect(detail.currentTemplate?.name, 'Edited template');
    expect(detail.reports.single.reporter, isNull);
    expect(detail.reports.single.explanation, 'Specific concern.');
    expect(response.toString(), isNot(contains('category')));
    expect(response.toString(), isNot(contains('email')));
    expect(response.toString(), isNot(contains('saved_copy')));
  });

  test('dismiss and takedown bind every decision field', () async {
    response = _actionDocument('dismiss');
    await repository.dismiss(
      _groupId,
      expectedGroupVersion: 3,
      privateNote: 'No policy violation.',
      requestId: _requestId,
    );
    expect(calls.single.functionName, 'moderate_public_template_report_group');
    expect(calls.single.params, {
      'target_group_id': _groupId,
      'moderation_action': 'dismiss',
      'expected_group_version': 3,
      'expected_template_version': null,
      'owner_reason_code': null,
      'private_note': 'No policy violation.',
      'request_id': _requestId,
    });

    calls.clear();
    response = _actionDocument('take_down');
    final result = await repository.takeDown(
      _groupId,
      expectedGroupVersion: 3,
      expectedTemplateVersion: 8,
      ownerReason: PublicTemplateReportReason.personalConfidentialInformation,
      privateNote: 'Personal information is exposed.',
      requestId: _requestId,
    );
    expect(calls.single.params, {
      'target_group_id': _groupId,
      'moderation_action': 'take_down',
      'expected_group_version': 3,
      'expected_template_version': 8,
      'owner_reason_code': 'personal_confidential_information',
      'private_note': 'Personal information is exposed.',
      'request_id': _requestId,
    });
    expect(result.action, PublicTemplateModerationAction.takeDown);
  });

  test('restore binds active restriction and template versions', () async {
    response = _actionDocument('restore');

    final result = await repository.restore(
      _templateId,
      expectedRestrictionVersion: 2,
      expectedTemplateVersion: 9,
      privateNote: 'Restriction no longer applies.',
      requestId: _requestId,
    );

    expect(calls.single.functionName, 'restore_public_template_moderation');
    expect(calls.single.params, {
      'target_template_id': _templateId,
      'expected_restriction_version': 2,
      'expected_template_version': 9,
      'private_note': 'Restriction no longer applies.',
      'request_id': _requestId,
    });
    expect(result.action, PublicTemplateModerationAction.restore);
  });

  test('strict parsing rejects private expansion and inconsistent state',
      () async {
    final leaked = _caseDocument()..['private_category'] = 'Never expose this';
    response = leaked;
    await expectLater(
      repository.getCase(_groupId),
      throwsA(isA<PublicTemplateModerationFailure>()),
    );

    final invalidQueue = _queueDocument();
    ((invalidQueue['cases'] as List).single
        as Map<String, dynamic>)['restriction_version'] = 2;
    response = invalidQueue;
    await expectLater(
      repository.listQueue(ModerationQueueFilter.open),
      throwsA(isA<PublicTemplateModerationFailure>()),
    );

    response = _actionDocument('dismiss')..['action'] = 'take_down';
    await expectLater(
      repository.dismiss(
        _groupId,
        expectedGroupVersion: 3,
        privateNote: 'No violation.',
        requestId: _requestId,
      ),
      throwsA(isA<PublicTemplateModerationFailure>()),
    );
  });

  test('maps stable SQLSTATEs without exposing server details', () async {
    for (final entry in const {
      '22023': PublicTemplateModerationFailureCode.invalid,
      'P0002': PublicTemplateModerationFailureCode.unavailable,
      '40001': PublicTemplateModerationFailureCode.stale,
      '23505': PublicTemplateModerationFailureCode.retryConflict,
      '42501': PublicTemplateModerationFailureCode.revoked,
    }.entries) {
      failure = PostgrestException(
        message: 'private queue information',
        code: entry.key,
      );
      await expectLater(
        repository.listQueue(ModerationQueueFilter.open),
        throwsA(
          isA<PublicTemplateModerationFailure>()
              .having((value) => value.code, 'code', entry.value)
              .having(
                (value) => value.toString(),
                'message',
                isNot(contains('private queue information')),
              ),
        ),
      );
    }
  });
}

Map<String, dynamic> _queueDocument() => {
      'filter': 'open',
      'cases': [
        {
          'group_id': _groupId,
          'template_id': _templateId,
          'template_name': 'Reported template',
          'reported_revision': 5,
          'report_count': 2,
          'status': 'open',
          'version': 3,
          'first_reported_at': '2026-07-26T06:00:00.000Z',
          'closed_at': null,
          'source_changed': true,
          'source_unpublished': false,
          'source_deleted': false,
          'source_moderated': false,
          'is_restricted': false,
          'restriction_version': null,
        },
      ],
      'next_cursor': {
        'at': '2026-07-26T06:00:00.000Z',
        'group_id': _groupId,
      },
    };

Map<String, dynamic> _caseDocument({
  Map<String, dynamic>? reporter = const {
    'profile_id': _reporterId,
    'username': 'reporter_user',
    'display_name': 'Reporter',
  },
}) =>
    {
      'group': {
        'group_id': _groupId,
        'template_id': _templateId,
        'reported_revision': 5,
        'status': 'open',
        'version': 3,
        'first_reported_at': '2026-07-26T06:00:00.000Z',
        'closed_at': null,
        'source_changed': true,
        'source_unpublished': false,
        'source_deleted': false,
        'source_moderated': false,
      },
      'reported_snapshot': {
        'name': 'Reported template',
        'items': [
          {'name': 'Water', 'quantity_thousandths': 1500},
        ],
      },
      'reports': [
        {
          'report_id': _reportId,
          'reason_code': 'other',
          'explanation': 'Specific concern.',
          'created_at': '2026-07-26T06:00:00.000Z',
          'reporter': reporter,
        },
      ],
      'current_template': {
        'template_id': _templateId,
        'name': 'Edited template',
        'version': 8,
        'is_public': true,
        'items': [
          {'name': 'Water bottles', 'quantity_thousandths': 2000},
        ],
      },
      'restriction': null,
    };

Map<String, dynamic> _actionDocument(String action) => {
      'event_id': _eventId,
      'action': action,
      'group_id': action == 'restore' ? null : _groupId,
      'group_version': action == 'restore' ? null : 4,
      'restriction_version': action == 'dismiss' ? null : 2,
      'template_version': action == 'dismiss' ? null : 9,
      'created_at': '2026-07-26T07:00:00.000Z',
    };

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}

const _groupId = '11111111-1111-4111-8111-111111111111';
const _templateId = '22222222-2222-4222-8222-222222222222';
const _reportId = '33333333-3333-4333-8333-333333333333';
const _reporterId = '44444444-4444-4444-8444-444444444444';
const _eventId = '55555555-5555-4555-8555-555555555555';
const _requestId = '66666666-6666-4666-8666-666666666666';
