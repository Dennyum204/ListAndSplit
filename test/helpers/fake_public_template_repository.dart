import 'dart:async';
import 'dart:collection';

import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';

class FakePublicTemplateRepository implements PublicTemplateRepository {
  final Map<String, Queue<PublicTemplatePage>> pagesByProfile = {};
  final Map<String, PublicTemplateDetail> detailsByTemplate = {};
  final List<PublicTemplateCursor?> cursors = [];
  final List<String> copiedTemplateIds = [];
  final List<String> copyRequestIds = [];
  final List<String> reportedTemplateIds = [];
  final List<int> reportedTemplateVersions = [];
  final List<PublicTemplateReportReason> reportReasons = [];
  final List<String?> reportExplanations = [];

  Object? listFailure;
  Object? detailFailure;
  Object? copyFailure;
  Object? reportFailure;
  Completer<PublicTemplateCopyResult>? copyCompleter;
  Completer<PublicTemplateReportResult>? reportCompleter;
  PublicTemplateCopyResult? copyResult;
  int listCalls = 0;
  int detailCalls = 0;
  int copyCalls = 0;
  int reportCalls = 0;

  void queuePage(String profileId, PublicTemplatePage page) {
    pagesByProfile.putIfAbsent(profileId, Queue.new).add(page);
  }

  @override
  Future<PublicTemplatePage> listProfileTemplates(
    String profileId, {
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  }) async {
    listCalls += 1;
    cursors.add(cursor);
    if (listFailure != null) throw listFailure!;
    final pages = pagesByProfile[profileId];
    if (pages == null || pages.isEmpty) {
      throw const PublicTemplateFailure(PublicTemplateFailureCode.unavailable);
    }
    if (pages.length == 1) return pages.first;
    return pages.removeFirst();
  }

  @override
  Future<PublicTemplateDetail> getTemplate(
    String profileId,
    String templateId,
  ) async {
    detailCalls += 1;
    if (detailFailure != null) throw detailFailure!;
    final detail = detailsByTemplate[templateId];
    if (detail == null || detail.profile.id != profileId) {
      throw const PublicTemplateFailure(PublicTemplateFailureCode.unavailable);
    }
    return detail;
  }

  @override
  Future<PublicTemplateCopyResult> copyTemplate(
    String templateId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    copyCalls += 1;
    copiedTemplateIds.add(templateId);
    copyRequestIds.add(requestId);
    if (copyFailure != null) throw copyFailure!;
    final pending = copyCompleter;
    if (pending != null) return pending.future;
    final result = copyResult;
    if (result == null) {
      throw const PublicTemplateFailure(PublicTemplateFailureCode.generic);
    }
    return result;
  }

  @override
  Future<PublicTemplateReportResult> reportTemplate(
    String templateId, {
    required int expectedVersion,
    required PublicTemplateReportReason reason,
    String? explanation,
  }) async {
    reportCalls += 1;
    reportedTemplateIds.add(templateId);
    reportedTemplateVersions.add(expectedVersion);
    reportReasons.add(reason);
    reportExplanations.add(explanation);
    if (reportFailure != null) throw reportFailure!;
    final pending = reportCompleter;
    if (pending != null) return pending.future;
    return PublicTemplateReportResult(
      reportId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      groupId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      reportedRevision: expectedVersion,
      createdAt: DateTime.utc(2026, 7, 26),
    );
  }
}
