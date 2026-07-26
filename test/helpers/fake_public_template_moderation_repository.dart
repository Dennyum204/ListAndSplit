import 'dart:async';
import 'dart:collection';

import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

class FakePublicTemplateModerationRepository
    implements PublicTemplateModerationRepository {
  bool hasAccess = false;
  Object? accessFailure;
  Object? queueFailure;
  Object? caseFailure;
  Object? actionFailure;
  final Map<ModerationQueueFilter, Queue<ModerationQueuePage>> queuePages = {};
  final Queue<PublicTemplateModerationCase> caseResults = Queue();
  final List<ModerationQueueFilter> queueCalls = [];
  final List<ModerationQueueCursor?> queueCursors = [];
  final List<String> caseCalls = [];
  final List<FakeModerationActionCall> actionCalls = [];
  Completer<ModerationActionResult>? actionCompleter;

  @override
  Future<bool> isModerator() async {
    if (accessFailure != null) throw accessFailure!;
    return hasAccess;
  }

  @override
  Future<ModerationQueuePage> listQueue(
    ModerationQueueFilter filter, {
    int pageSize = 20,
    ModerationQueueCursor? cursor,
  }) async {
    queueCalls.add(filter);
    queueCursors.add(cursor);
    if (queueFailure != null) throw queueFailure!;
    final pages = queuePages[filter];
    if (pages == null || pages.isEmpty) {
      return ModerationQueuePage(
        filter: filter,
        cases: const [],
        nextCursor: null,
      );
    }
    return pages.length == 1 ? pages.first : pages.removeFirst();
  }

  @override
  Future<PublicTemplateModerationCase> getCase(String groupId) async {
    caseCalls.add(groupId);
    if (caseFailure != null) throw caseFailure!;
    if (caseResults.isEmpty) {
      throw const PublicTemplateModerationFailure(
        PublicTemplateModerationFailureCode.unavailable,
      );
    }
    return caseResults.length == 1
        ? caseResults.first
        : caseResults.removeFirst();
  }

  @override
  Future<ModerationActionResult> dismiss(
    String groupId, {
    required int expectedGroupVersion,
    required String privateNote,
    required String requestId,
  }) =>
      _act(
        FakeModerationActionCall(
          action: PublicTemplateModerationAction.dismiss,
          targetId: groupId,
          expectedGroupVersion: expectedGroupVersion,
          expectedTemplateVersion: null,
          expectedRestrictionVersion: null,
          ownerReason: null,
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
      _act(
        FakeModerationActionCall(
          action: PublicTemplateModerationAction.takeDown,
          targetId: groupId,
          expectedGroupVersion: expectedGroupVersion,
          expectedTemplateVersion: expectedTemplateVersion,
          expectedRestrictionVersion: null,
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
      _act(
        FakeModerationActionCall(
          action: PublicTemplateModerationAction.restore,
          targetId: templateId,
          expectedGroupVersion: null,
          expectedTemplateVersion: expectedTemplateVersion,
          expectedRestrictionVersion: expectedRestrictionVersion,
          ownerReason: null,
          privateNote: privateNote,
          requestId: requestId,
        ),
      );

  void queuePage(ModerationQueuePage page) {
    queuePages.putIfAbsent(page.filter, Queue.new).add(page);
  }

  Future<ModerationActionResult> _act(FakeModerationActionCall call) async {
    actionCalls.add(call);
    if (actionFailure != null) throw actionFailure!;
    final pending = actionCompleter;
    if (pending != null) return pending.future;
    return ModerationActionResult(
      eventId: '99999999-9999-4999-8999-999999999999',
      action: call.action,
      groupId: call.action == PublicTemplateModerationAction.restore
          ? null
          : call.targetId,
      groupVersion:
          call.action == PublicTemplateModerationAction.restore ? null : 2,
      restrictionVersion:
          call.action == PublicTemplateModerationAction.dismiss ? null : 2,
      templateVersion:
          call.action == PublicTemplateModerationAction.dismiss ? null : 6,
      createdAt: DateTime.utc(2026, 7, 26, 8),
    );
  }
}

class FakeModerationActionCall {
  const FakeModerationActionCall({
    required this.action,
    required this.targetId,
    required this.expectedGroupVersion,
    required this.expectedTemplateVersion,
    required this.expectedRestrictionVersion,
    required this.ownerReason,
    required this.privateNote,
    required this.requestId,
  });

  final PublicTemplateModerationAction action;
  final String targetId;
  final int? expectedGroupVersion;
  final int? expectedTemplateVersion;
  final int? expectedRestrictionVersion;
  final PublicTemplateReportReason? ownerReason;
  final String privateNote;
  final String requestId;
}
