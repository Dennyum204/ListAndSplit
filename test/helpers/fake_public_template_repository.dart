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

  Object? listFailure;
  Object? detailFailure;
  Object? copyFailure;
  Completer<PublicTemplateCopyResult>? copyCompleter;
  PublicTemplateCopyResult? copyResult;
  int listCalls = 0;
  int detailCalls = 0;
  int copyCalls = 0;

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
}
