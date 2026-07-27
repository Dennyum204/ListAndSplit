import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';
import 'package:list_and_split/features/templates/presentation/template_sends_controller.dart';

void main() {
  test('composer blocks rapid taps and sends one payload-bound request',
      () async {
    final repository = _FakeTemplateSendRepository();
    final completer = Completer<TemplateSendMutationResult>();
    repository.sendHandler = (_, __, ___, ____) => completer.future;
    var sharedInvalidations = 0;
    var notificationInvalidations = 0;
    final controller = TemplateSendComposerController(
      repository,
      _templateId,
      invalidateShared: () => sharedInvalidations += 1,
      invalidateNotifications: () => notificationInvalidations += 1,
      requestIdGenerator: () => _requestId,
    );
    await controller.loadRecipients();

    final first = controller.send(
      recipientProfileId: _recipientId,
      expectedTemplateVersion: 4,
    );
    final second = await controller.send(
      recipientProfileId: _recipientId,
      expectedTemplateVersion: 4,
    );

    expect(second, isFalse);
    expect(repository.sendCalls, hasLength(1));
    expect(repository.sendCalls.single.requestId, _requestId);
    completer.complete(_mutation(TemplateSendState.pending));
    expect(await first, isTrue);
    expect(sharedInvalidations, 1);
    expect(notificationInvalidations, 1);
    expect(controller.state.message, TemplateSendMessage.sent);
    controller.dispose();
  });

  test('transport timeout retains the request ID for a safe retry', () async {
    final repository = _FakeTemplateSendRepository();
    var requestIdsGenerated = 0;
    repository.sendHandler =
        (_, __, ___, ____) => Future.error(TimeoutException('lost response'));
    final controller = TemplateSendComposerController(
      repository,
      _templateId,
      invalidateShared: () {},
      invalidateNotifications: () {},
      requestIdGenerator: () => 'request-${++requestIdsGenerated}',
    );
    await controller.loadRecipients();

    expect(
      await controller.send(
        recipientProfileId: _recipientId,
        expectedTemplateVersion: 4,
      ),
      isFalse,
    );
    final firstRequestId = repository.sendCalls.single.requestId;
    repository.sendHandler =
        (_, __, ___, ____) async => _mutation(TemplateSendState.pending);

    expect(
      await controller.send(
        recipientProfileId: _recipientId,
        expectedTemplateVersion: 4,
      ),
      isTrue,
    );
    expect(repository.sendCalls[1].requestId, firstRequestId);
    expect(requestIdsGenerated, 1);
    controller.dispose();
  });

  test('accept capacity failure remains pending and stops loading', () async {
    final repository = _FakeTemplateSendRepository()
      ..acceptFailure = const TemplateSendFailure(
        TemplateSendFailureCode.capacity,
      );
    final controller = ReceivedTemplateSendController(
      repository,
      _sendId,
      invalidateShared: () {},
      invalidateTemplates: () {},
      invalidateNotifications: () {},
    );
    await controller.load();

    expect(await controller.accept(), isFalse);
    expect(controller.state.isMutating, isFalse);
    expect(controller.state.message, TemplateSendMessage.capacity);
    expect(
      controller.state.detail.valueOrNull?.summary.state,
      TemplateSendState.pending,
    );
    expect(repository.acceptCalls, 1);
    controller.dispose();
  });

  test('stale accept reloads terminal state without creating another copy',
      () async {
    final repository = _FakeTemplateSendRepository()
      ..acceptFailure = const TemplateSendFailure(
        TemplateSendFailureCode.stale,
      );
    final controller = ReceivedTemplateSendController(
      repository,
      _sendId,
      invalidateShared: () {},
      invalidateTemplates: () {},
      invalidateNotifications: () {},
    );
    await controller.load();
    repository.detail = _detail(
      state: TemplateSendState.accepted,
      version: 2,
      acceptedTemplateId: _acceptedTemplateId,
    );

    expect(await controller.accept(), isFalse);
    expect(controller.state.message, TemplateSendMessage.stale);
    expect(
      controller.state.detail.valueOrNull?.acceptedTemplateId,
      _acceptedTemplateId,
    );
    expect(await controller.accept(), isFalse);
    expect(repository.acceptCalls, 1);
    controller.dispose();
  });

  test('access loss clears cached received detail and disables every action',
      () async {
    final repository = _FakeTemplateSendRepository();
    final controller = ReceivedTemplateSendController(
      repository,
      _sendId,
      invalidateShared: () {},
      invalidateTemplates: () {},
      invalidateNotifications: () {},
    );
    await controller.load();
    repository.detailFailure = const TemplateSendFailure(
      TemplateSendFailureCode.unavailable,
    );

    await controller.reconcile();

    expect(controller.state.detail.hasError, isTrue);
    expect(controller.state.message, TemplateSendMessage.unavailable);
    expect(await controller.accept(), isFalse);
    expect(repository.acceptCalls, 0);
    controller.dispose();
  });

  test('Realtime reconciliation refreshes all four persistent projections',
      () async {
    final repository = _FakeTemplateSendRepository();
    final controller = SharedTemplateSendsController(
      repository,
      hasAuthenticatedUser: true,
      invalidateNotifications: () {},
    );

    await controller.load();
    await controller.reconcile();

    expect(repository.receivedCalls, 4);
    expect(repository.sentCalls, 4);
    expect(controller.state.data.hasValue, isTrue);
    controller.dispose();
  });

  test('eligible recipients use the reviewed keyset pagination contract',
      () async {
    final repository = _FakeTemplateSendRepository()
      ..recipientPages.addAll([
        [
          for (var index = 0; index < 20; index += 1)
            TemplateSendProfile(
              id: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
              username: 'friend_${index.toString().padLeft(2, '0')}',
              displayName: 'Friend $index',
            ),
        ],
        const [
          TemplateSendProfile(
            id: _recipientId,
            username: 'friend_20',
            displayName: 'Friend 20',
          ),
        ],
      ]);
    final controller = TemplateSendComposerController(
      repository,
      _templateId,
      invalidateShared: () {},
      invalidateNotifications: () {},
    );

    await controller.loadRecipients();
    expect(controller.state.hasMore, isTrue);
    await controller.loadMoreRecipients();

    expect(controller.state.recipients.valueOrNull, hasLength(21));
    expect(controller.state.hasMore, isFalse);
    expect(repository.recipientCursors, hasLength(2));
    expect(repository.recipientCursors.last?.username, 'friend_19');
    controller.dispose();
  });
}

class _FakeTemplateSendRepository implements TemplateSendRepository {
  ReceivedTemplateSendDetail detail = _detail();
  TemplateSendFailure? acceptFailure;
  TemplateSendFailure? detailFailure;
  int acceptCalls = 0;
  int receivedCalls = 0;
  int sentCalls = 0;
  final List<
      ({
        String templateId,
        String recipientId,
        int version,
        String requestId,
      })> sendCalls = [];
  final List<List<TemplateSendProfile>> recipientPages = [];
  final List<TemplateSendRecipientCursor?> recipientCursors = [];
  Future<TemplateSendMutationResult> Function(
    String templateId,
    String recipientId,
    int version,
    String requestId,
  )? sendHandler;

  @override
  Future<List<TemplateSendProfile>> listEligibleRecipients(
    String templateId, {
    int pageSize = 20,
    TemplateSendRecipientCursor? cursor,
  }) async {
    recipientCursors.add(cursor);
    if (recipientPages.isNotEmpty) return recipientPages.removeAt(0);
    return const [
      TemplateSendProfile(
        id: _recipientId,
        username: 'friend_user',
        displayName: 'Friend User',
      ),
    ];
  }

  @override
  Future<TemplateSendMutationResult> sendTemplate(
    String templateId,
    String recipientProfileId, {
    required int expectedTemplateVersion,
    required String requestId,
  }) {
    sendCalls.add((
      templateId: templateId,
      recipientId: recipientProfileId,
      version: expectedTemplateVersion,
      requestId: requestId,
    ));
    return sendHandler!(
      templateId,
      recipientProfileId,
      expectedTemplateVersion,
      requestId,
    );
  }

  @override
  Future<List<ReceivedTemplateSendSummary>> listReceived({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    receivedCalls += 1;
    return const [];
  }

  @override
  Future<List<SentTemplateSendSummary>> listSent({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    sentCalls += 1;
    return const [];
  }

  @override
  Future<ReceivedTemplateSendDetail> getReceived(
    String templateSendId,
  ) async {
    if (detailFailure != null) throw detailFailure!;
    return detail;
  }

  @override
  Future<TemplateSendMutationResult> accept(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    acceptCalls += 1;
    if (acceptFailure != null) throw acceptFailure!;
    return _mutation(
      TemplateSendState.accepted,
      acceptedTemplateId: _acceptedTemplateId,
    );
  }

  @override
  Future<TemplateSendMutationResult> decline(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async =>
      _mutation(TemplateSendState.declined);

  @override
  Future<TemplateSendMutationResult> revoke(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async =>
      _mutation(TemplateSendState.revoked);
}

ReceivedTemplateSendDetail _detail({
  TemplateSendState state = TemplateSendState.pending,
  int version = 1,
  String? acceptedTemplateId,
}) {
  return ReceivedTemplateSendDetail(
    summary: ReceivedTemplateSendSummary(
      id: _sendId,
      sender: const TemplateSendProfile(
        id: _senderId,
        username: 'sender_user',
        displayName: 'Sender User',
      ),
      snapshotName: 'Beach trip',
      itemCount: 0,
      state: state,
      version: version,
      createdAt: DateTime.utc(2026, 7, 27, 8),
      stateChangedAt: DateTime.utc(2026, 7, 27, 8),
    ),
    acceptedTemplateId: acceptedTemplateId,
    items: const [],
  );
}

TemplateSendMutationResult _mutation(
  TemplateSendState state, {
  String? acceptedTemplateId,
}) {
  return TemplateSendMutationResult(
    id: _sendId,
    state: state,
    version: state == TemplateSendState.pending ? 1 : 2,
    stateChangedAt: DateTime.utc(2026, 7, 27, 8),
    acceptedTemplateId: acceptedTemplateId,
    snapshotName: state == TemplateSendState.pending ? 'Beach trip' : null,
    itemCount: state == TemplateSendState.pending ? 0 : null,
    createdAt: state == TemplateSendState.pending
        ? DateTime.utc(2026, 7, 27, 8)
        : null,
  );
}

const _templateId = '11111111-1111-4111-8111-111111111111';
const _sendId = '22222222-2222-4222-8222-222222222222';
const _senderId = '33333333-3333-4333-8333-333333333333';
const _recipientId = '44444444-4444-4444-8444-444444444444';
const _acceptedTemplateId = '55555555-5555-4555-8555-555555555555';
const _requestId = '66666666-6666-4666-8666-666666666666';
