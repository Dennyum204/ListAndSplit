import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_controller.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

void main() {
  test('access self-check publishes server authorization and safe failure',
      () async {
    final repository = _FakeModerationRepository()..isModeratorResult = true;
    final controller = ModerationAccessController(
      repository,
      hasAuthenticatedUser: true,
    );

    await controller.load();
    expect(controller.state.value, isTrue);

    repository.failure = const PublicTemplateModerationFailure(
      PublicTemplateModerationFailureCode.transport,
    );
    await controller.reconcile();
    expect(controller.state, isA<AsyncError<bool>>());
    controller.dispose();
  });

  test('queue filters, keyset-paginates and deduplicates immutable groups',
      () async {
    final repository = _FakeModerationRepository()
      ..queuePages.add(
        _page(
          ModerationQueueFilter.open,
          cases: [_summary(_groupId)],
          nextCursor: _cursor,
        ),
      )
      ..queuePages.add(
        _page(
          ModerationQueueFilter.open,
          cases: [_summary(_groupId), _summary(_secondGroupId)],
        ),
      )
      ..queuePages.add(_page(ModerationQueueFilter.closed));
    final controller = ModerationQueueController(
      repository,
      hasAuthenticatedUser: true,
    );

    await controller.load();
    await controller.loadMore();

    expect(
      controller.state.page.value!.cases.map((entry) => entry.groupId),
      [_groupId, _secondGroupId],
    );
    expect(repository.queueCalls[1].cursor, _cursor);

    await controller.selectFilter(ModerationQueueFilter.closed);
    expect(controller.state.filter, ModerationQueueFilter.closed);
    expect(repository.queueCalls.last.filter, ModerationQueueFilter.closed);
    controller.dispose();
  });

  test('revoked queue access immediately clears cached protected data',
      () async {
    final repository = _FakeModerationRepository()
      ..queuePages.add(
        _page(
          ModerationQueueFilter.open,
          cases: [_summary(_groupId)],
        ),
      );
    final controller = ModerationQueueController(
      repository,
      hasAuthenticatedUser: true,
    );
    await controller.load();

    repository.failure = const PublicTemplateModerationFailure(
      PublicTemplateModerationFailureCode.revoked,
    );
    await controller.reconcile();

    expect(
      controller.state.page,
      isA<AsyncError<ModerationQueuePage>>(),
    );
    expect(controller.state.message, ModerationMessage.accessRevoked);
    controller.dispose();
  });

  test('actions use exact versions, invalidate projections and guard repeats',
      () async {
    final completion = Completer<ModerationActionResult>();
    final repository = _FakeModerationRepository()
      ..caseResult = _case()
      ..actionCompleter = completion;
    var queueInvalidations = 0;
    var ownerInvalidations = 0;
    final controller = _caseController(
      repository,
      invalidateQueue: () => queueInvalidations++,
      invalidateOwnerState: () => ownerInvalidations++,
    );
    await controller.load();

    final first = controller.takeDown(
      PublicTemplateReportReason.illegalRegulated,
      'Reviewed against the policy.',
    );
    final second = controller.takeDown(
      PublicTemplateReportReason.illegalRegulated,
      'Reviewed against the policy.',
    );

    expect(await second, isFalse);
    expect(repository.actionCalls, hasLength(1));
    final call = repository.actionCalls.single;
    expect(call.action, PublicTemplateModerationAction.takeDown);
    expect(call.expectedGroupVersion, 3);
    expect(call.expectedTemplateVersion, 8);
    expect(call.ownerReason, PublicTemplateReportReason.illegalRegulated);
    expect(call.privateNote, 'Reviewed against the policy.');

    repository.actionCompleter = null;
    completion.complete(_action(PublicTemplateModerationAction.takeDown));
    expect(await first, isTrue);
    expect(queueInvalidations, 1);
    expect(ownerInvalidations, 1);
    expect(controller.state.message, ModerationMessage.takenDown);
    controller.dispose();
  });

  test('transport-uncertain retry keeps its payload-bound request ID',
      () async {
    final repository = _FakeModerationRepository()
      ..caseResult = _case()
      ..actionFailures.add(
        const PublicTemplateModerationFailure(
          PublicTemplateModerationFailureCode.transport,
        ),
      );
    var generated = 0;
    final controller = _caseController(
      repository,
      requestIdGenerator: () => 'request-${++generated}',
    );
    await controller.load();

    expect(await controller.dismiss('No policy violation found.'), isFalse);
    expect(await controller.dismiss('No policy violation found.'), isTrue);

    expect(repository.actionCalls, hasLength(2));
    expect(
      repository.actionCalls.map((call) => call.requestId),
      ['request-1', 'request-1'],
    );
    expect(generated, 1);
    controller.dispose();
  });

  test('stale action refreshes while revocation clears the entire case',
      () async {
    final repository = _FakeModerationRepository()
      ..caseResult = _case()
      ..actionFailures.add(
        const PublicTemplateModerationFailure(
          PublicTemplateModerationFailureCode.stale,
        ),
      );
    final controller = _caseController(repository);
    await controller.load();

    expect(await controller.dismiss('No violation.'), isFalse);
    expect(controller.state.message, ModerationMessage.staleRefreshed);
    expect(repository.getCaseCalls, 2);

    repository.actionFailures.add(
      const PublicTemplateModerationFailure(
        PublicTemplateModerationFailureCode.revoked,
      ),
    );
    expect(await controller.dismiss('No violation.'), isFalse);
    expect(
      controller.state.detail,
      isA<AsyncError<PublicTemplateModerationCase>>(),
    );
    expect(controller.state.message, ModerationMessage.accessRevoked);
    controller.dispose();
  });

  test('restore requires active restriction and uses restriction version',
      () async {
    final repository = _FakeModerationRepository()
      ..caseResult = _case(restricted: true);
    final controller = _caseController(repository);
    await controller.load();

    expect(await controller.restore('Restriction no longer applies.'), isTrue);

    final call = repository.actionCalls.single;
    expect(call.action, PublicTemplateModerationAction.restore);
    expect(call.templateId, _templateId);
    expect(call.expectedRestrictionVersion, 2);
    expect(call.expectedTemplateVersion, 8);
    controller.dispose();
  });
}

ModerationCaseController _caseController(
  _FakeModerationRepository repository, {
  void Function()? invalidateQueue,
  void Function()? invalidateOwnerState,
  String Function()? requestIdGenerator,
}) =>
    ModerationCaseController(
      repository,
      _groupId,
      hasAuthenticatedUser: true,
      invalidateQueue: invalidateQueue ?? () {},
      invalidateOwnerState: invalidateOwnerState ?? () {},
      requestIdGenerator: requestIdGenerator ?? (() => _requestId),
    );

class _FakeModerationRepository implements PublicTemplateModerationRepository {
  final Queue<ModerationQueuePage> queuePages = Queue();
  final Queue<Object> actionFailures = Queue();
  final List<_QueueCall> queueCalls = [];
  final List<_ActionCall> actionCalls = [];
  bool isModeratorResult = false;
  PublicTemplateModerationCase? caseResult;
  Object? failure;
  Completer<ModerationActionResult>? actionCompleter;
  int getCaseCalls = 0;

  @override
  Future<bool> isModerator() async {
    if (failure != null) throw failure!;
    return isModeratorResult;
  }

  @override
  Future<ModerationQueuePage> listQueue(
    ModerationQueueFilter filter, {
    int pageSize = 20,
    ModerationQueueCursor? cursor,
  }) async {
    queueCalls.add(_QueueCall(filter, cursor));
    if (failure != null) throw failure!;
    return queuePages.removeFirst();
  }

  @override
  Future<PublicTemplateModerationCase> getCase(String groupId) async {
    getCaseCalls++;
    if (failure != null) throw failure!;
    return caseResult!;
  }

  @override
  Future<ModerationActionResult> dismiss(
    String groupId, {
    required int expectedGroupVersion,
    required String privateNote,
    required String requestId,
  }) =>
      _actionCall(
        _ActionCall(
          action: PublicTemplateModerationAction.dismiss,
          groupId: groupId,
          expectedGroupVersion: expectedGroupVersion,
          privateNote: privateNote,
          requestId: requestId,
        ),
      );

  @override
  Future<ModerationActionResult> takeDown(
    String groupId, {
    required int expectedGroupVersion,
    required int expectedTemplateVersion,
    required PublicTemplateReportReason ownerReason,
    required String privateNote,
    required String requestId,
  }) =>
      _actionCall(
        _ActionCall(
          action: PublicTemplateModerationAction.takeDown,
          groupId: groupId,
          expectedGroupVersion: expectedGroupVersion,
          expectedTemplateVersion: expectedTemplateVersion,
          ownerReason: ownerReason,
          privateNote: privateNote,
          requestId: requestId,
        ),
      );

  @override
  Future<ModerationActionResult> restore(
    String templateId, {
    required int expectedRestrictionVersion,
    required int expectedTemplateVersion,
    required String privateNote,
    required String requestId,
  }) =>
      _actionCall(
        _ActionCall(
          action: PublicTemplateModerationAction.restore,
          templateId: templateId,
          expectedRestrictionVersion: expectedRestrictionVersion,
          expectedTemplateVersion: expectedTemplateVersion,
          privateNote: privateNote,
          requestId: requestId,
        ),
      );

  Future<ModerationActionResult> _actionCall(_ActionCall call) async {
    actionCalls.add(call);
    if (actionFailures.isNotEmpty) throw actionFailures.removeFirst();
    final pending = actionCompleter;
    if (pending != null) return pending.future;
    return _action(call.action);
  }
}

class _QueueCall {
  const _QueueCall(this.filter, this.cursor);

  final ModerationQueueFilter filter;
  final ModerationQueueCursor? cursor;
}

class _ActionCall {
  const _ActionCall({
    required this.action,
    required this.privateNote,
    required this.requestId,
    this.groupId,
    this.templateId,
    this.expectedGroupVersion,
    this.expectedRestrictionVersion,
    this.expectedTemplateVersion,
    this.ownerReason,
  });

  final PublicTemplateModerationAction action;
  final String? groupId;
  final String? templateId;
  final int? expectedGroupVersion;
  final int? expectedRestrictionVersion;
  final int? expectedTemplateVersion;
  final PublicTemplateReportReason? ownerReason;
  final String privateNote;
  final String requestId;
}

ModerationQueuePage _page(
  ModerationQueueFilter filter, {
  List<ModerationQueueCase> cases = const [],
  ModerationQueueCursor? nextCursor,
}) =>
    ModerationQueuePage(
      filter: filter,
      cases: cases,
      nextCursor: nextCursor,
    );

ModerationQueueCase _summary(String groupId) => ModerationQueueCase(
      groupId: groupId,
      templateId: _templateId,
      templateName: 'Reported template',
      reportedRevision: 5,
      reportCount: 2,
      status: 'open',
      version: 3,
      firstReportedAt: DateTime.utc(2026, 7, 26, 6),
      closedAt: null,
      sourceChanged: true,
      sourceUnpublished: false,
      sourceDeleted: false,
      sourceModerated: false,
      isRestricted: false,
      restrictionVersion: null,
    );

PublicTemplateModerationCase _case({bool restricted = false}) =>
    PublicTemplateModerationCase(
      summary: ModerationQueueCase(
        groupId: _groupId,
        templateId: _templateId,
        templateName: 'Reported template',
        reportedRevision: 5,
        reportCount: 1,
        status: restricted ? 'taken_down' : 'open',
        version: 3,
        firstReportedAt: DateTime.utc(2026, 7, 26, 6),
        closedAt: restricted ? DateTime.utc(2026, 7, 26, 7) : null,
        sourceChanged: true,
        sourceUnpublished: restricted,
        sourceDeleted: false,
        sourceModerated: restricted,
        isRestricted: restricted,
        restrictionVersion: restricted ? 2 : null,
      ),
      reportedSnapshot: ModerationTemplateSnapshot(
        name: 'Reported template',
        items: [
          ModerationSnapshotItem(
            name: 'Water',
            quantity: ListQuantity.fromThousandths(1500),
            position: 1,
          ),
        ],
      ),
      reports: [
        ModerationReport(
          id: _reportId,
          reason: PublicTemplateReportReason.spamScamDeceptive,
          explanation: null,
          createdAt: DateTime.utc(2026, 7, 26, 6),
          reporter: const ModerationReporterProfile(
            id: _reporterId,
            username: 'reporter_user',
            displayName: 'Reporter',
          ),
        ),
      ],
      currentTemplate: ModerationCurrentTemplate(
        id: _templateId,
        name: 'Current template',
        version: 8,
        isPublic: !restricted,
        items: const [],
      ),
      restriction: restricted
          ? ModerationRestriction(
              active: true,
              version: 2,
              reason: PublicTemplateReportReason.spamScamDeceptive,
              imposedAt: DateTime.utc(2026, 7, 26, 7),
              restoredAt: null,
              sourceDeletedAt: null,
            )
          : null,
    );

ModerationActionResult _action(PublicTemplateModerationAction action) =>
    ModerationActionResult(
      eventId: _eventId,
      action: action,
      groupId:
          action == PublicTemplateModerationAction.restore ? null : _groupId,
      groupVersion: action == PublicTemplateModerationAction.restore ? null : 4,
      restrictionVersion:
          action == PublicTemplateModerationAction.dismiss ? null : 2,
      templateVersion:
          action == PublicTemplateModerationAction.dismiss ? null : 9,
      createdAt: DateTime.utc(2026, 7, 26, 7),
    );

final _cursor = ModerationQueueCursor(
  at: DateTime.utc(2026, 7, 26, 6),
  groupId: _groupId,
);

const _groupId = '11111111-1111-4111-8111-111111111111';
const _secondGroupId = '22222222-2222-4222-8222-222222222222';
const _templateId = '33333333-3333-4333-8333-333333333333';
const _reportId = '44444444-4444-4444-8444-444444444444';
const _reporterId = '55555555-5555-4555-8555-555555555555';
const _eventId = '66666666-6666-4666-8666-666666666666';
const _requestId = '77777777-7777-4777-8777-777777777777';
