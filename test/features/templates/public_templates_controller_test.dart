import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/public_templates_controller.dart';

void main() {
  test(
      'profile paging deduplicates immutable IDs and refreshes authoritatively',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..pages.add(
        _page(
          templates: [_summary(_templateId, version: 1)],
          nextCursor: _cursor,
        ),
      )
      ..pages.add(
        _page(
          templates: [
            _summary(_templateId, version: 1),
            _summary(_secondTemplateId, version: 1),
          ],
        ),
      )
      ..pages.add(
        _page(
          templates: [_summary(_templateId, version: 2)],
        ),
      );
    final controller = PublicProfileTemplatesController(
      repository,
      _FakeCommunityRepository(),
      _profileId,
      hasAuthenticatedUser: true,
      canBlock: true,
      invalidateCommunity: () {},
      invalidateNotifications: () {},
    );

    await controller.load();
    await controller.loadMore();

    expect(
      controller.state.page.value!.templates.map((entry) => entry.id),
      [_templateId, _secondTemplateId],
    );
    expect(repository.cursors, [null, _cursor]);

    await controller.reconcile();
    expect(controller.state.page.value!.templates.single.version, 2);
    controller.dispose();
  });

  test('profile block is guarded and produces one generic access-loss state',
      () async {
    final repository = _FakePublicTemplateRepository()..pages.add(_page());
    final community = _FakeCommunityRepository();
    var communityInvalidations = 0;
    var notificationInvalidations = 0;
    final controller = PublicProfileTemplatesController(
      repository,
      community,
      _profileId,
      hasAuthenticatedUser: true,
      canBlock: true,
      invalidateCommunity: () => communityInvalidations += 1,
      invalidateNotifications: () => notificationInvalidations += 1,
    );
    await controller.load();

    expect(await controller.blockProfile(), isTrue);
    expect(await controller.blockProfile(), isFalse);
    expect(community.blockedIds, [_profileId]);
    expect(communityInvalidations, 1);
    expect(notificationInvalidations, 1);
    expect(controller.state.message, PublicTemplatesMessage.unavailable);
    controller.dispose();
  });

  test('copy reuses one request ID after a transport-uncertain response',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail(version: 4)
      ..copyFailures.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.transport),
      );
    var generated = 0;
    final controller = _detailController(
      repository,
      requestIdGenerator: () => 'request-${++generated}',
    );
    await controller.load();

    expect(await controller.copyTemplate(), isNull);
    expect(controller.state.message, PublicTemplatesMessage.operationFailed);
    expect(await controller.copyTemplate(), _copiedTemplateId);

    expect(repository.copyRequestIds, ['request-1', 'request-1']);
    expect(generated, 1);
    expect(controller.state.message, PublicTemplatesMessage.copied);
    expect(controller.state.detail.value, isNotNull);
    controller.dispose();
  });

  test('quota rejection keeps the authoritative detail and is retryable',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..copyFailures.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.capacity),
      );
    final controller = _detailController(repository);
    await controller.load();

    expect(await controller.copyTemplate(), isNull);
    expect(controller.state.message, PublicTemplatesMessage.capacity);
    expect(controller.state.detail.value?.summary.id, _templateId);

    expect(await controller.copyTemplate(), _copiedTemplateId);
    expect(repository.copyRequestIds, [_requestId, _requestId]);
    controller.dispose();
  });

  test('rapid repeated copy submissions call the repository once', () async {
    final completion = Completer<PublicTemplateCopyResult>();
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..copyHandler = (_, __, ___) => completion.future;
    final controller = _detailController(repository);
    await controller.load();

    final first = controller.copyTemplate();
    final second = controller.copyTemplate();
    expect(await second, isNull);
    expect(repository.copyRequestIds, hasLength(1));

    completion.complete(_copyResult());
    expect(await first, _copiedTemplateId);
    controller.dispose();
  });

  test('report sends exact revision and reconciles only after confirmation',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail(version: 4);
    final controller = _detailController(repository);
    await controller.load();

    expect(
      await controller.reportTemplate(
        PublicTemplateReportReason.copyrightTrademark,
        'Specific ownership concern.',
      ),
      PublicTemplateReportOutcome.submitted,
    );

    expect(repository.reportCalls, hasLength(1));
    expect(repository.reportCalls.single.templateId, _templateId);
    expect(repository.reportCalls.single.expectedVersion, 4);
    expect(
      repository.reportCalls.single.reason,
      PublicTemplateReportReason.copyrightTrademark,
    );
    expect(
      repository.reportCalls.single.explanation,
      'Specific ownership concern.',
    );
    expect(controller.state.isMutating, isFalse);
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('stale report refreshes and inaccessible report stays privacy-safe',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail(version: 4)
      ..reportFailures.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.stale),
      );
    final controller = _detailController(repository);
    await controller.load();
    repository.detail = _detail(version: 5);

    expect(
      await controller.reportTemplate(
        PublicTemplateReportReason.spamScamDeceptive,
        null,
      ),
      PublicTemplateReportOutcome.stale,
    );
    await pumpEventQueue();
    expect(controller.state.detail.value!.summary.version, 5);
    expect(controller.state.isMutating, isFalse);
    expect(controller.state.message, isNull);

    repository.reportFailures.add(
      const PublicTemplateFailure(PublicTemplateFailureCode.unavailable),
    );
    expect(
      await controller.reportTemplate(
        PublicTemplateReportReason.spamScamDeceptive,
        null,
      ),
      PublicTemplateReportOutcome.unavailable,
    );
    expect(controller.state.isMutating, isFalse);
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('rapid report confirmation submits once and blocking stays separate',
      () async {
    final completion = Completer<PublicTemplateReportResult>();
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..reportHandler = (_, __, ___, ____) => completion.future;
    final community = _FakeCommunityRepository();
    final controller = PublicTemplateDetailController(
      repository,
      community,
      _profileId,
      _templateId,
      canBlock: true,
      invalidatePrivateTemplates: () {},
      invalidateCommunity: () {},
      invalidateNotifications: () {},
    );
    await controller.load();

    final first = controller.reportTemplate(
      PublicTemplateReportReason.other,
      'Specific concern.',
    );
    final second = controller.reportTemplate(
      PublicTemplateReportReason.other,
      'Specific concern.',
    );
    expect(await second, PublicTemplateReportOutcome.failed);
    expect(repository.reportCalls, hasLength(1));
    expect(community.blockedIds, isEmpty);

    completion.complete(_reportResult());
    expect(await first, PublicTemplateReportOutcome.submitted);
    expect(community.blockedIds, isEmpty);
    expect(await controller.blockProfile(), isTrue);
    expect(community.blockedIds, [_profileId]);
    controller.dispose();
  });

  test('stale report clears busy before authoritative refresh completes',
      () async {
    final refresh = Completer<PublicTemplateDetail>();
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail(version: 4)
      ..reportFailures.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.stale),
      );
    final controller = _detailController(repository);
    await controller.load();
    repository.detailCompleter = refresh;

    expect(
      await controller.reportTemplate(
        PublicTemplateReportReason.spamScamDeceptive,
        null,
      ),
      PublicTemplateReportOutcome.stale,
    );

    expect(controller.state.isMutating, isFalse);
    expect(controller.state.detail.value!.summary.version, 4);
    refresh.complete(_detail(version: 5));
    await pumpEventQueue();
    expect(controller.state.detail.value!.summary.version, 5);
    controller.dispose();
  });

  test('report timeout and unexpected errors always clear mutation state',
      () async {
    final pending = Completer<PublicTemplateReportResult>();
    final timeoutRepository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..reportHandler = (_, __, ___, ____) => pending.future;
    final timeoutController = _detailController(
      timeoutRepository,
      requestTimeout: const Duration(milliseconds: 1),
    );
    await timeoutController.load();

    expect(
      await timeoutController.reportTemplate(
        PublicTemplateReportReason.spamScamDeceptive,
        null,
      ),
      PublicTemplateReportOutcome.failed,
    );
    expect(timeoutController.state.isMutating, isFalse);
    expect(timeoutController.state.message, isNull);
    timeoutController.dispose();

    final errorRepository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..reportFailures.add(StateError('unexpected client failure'));
    final errorController = _detailController(errorRepository);
    await errorController.load();
    expect(
      await errorController.reportTemplate(
        PublicTemplateReportReason.spamScamDeceptive,
        null,
      ),
      PublicTemplateReportOutcome.failed,
    );
    expect(errorController.state.isMutating, isFalse);
    expect(errorController.state.message, isNull);
    errorController.dispose();
  });

  test('late report failure after disposal does not update state', () async {
    final completion = Completer<PublicTemplateReportResult>();
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..reportHandler = (_, __, ___, ____) => completion.future;
    final controller = _detailController(repository);
    await controller.load();
    final operation = controller.reportTemplate(
      PublicTemplateReportReason.spamScamDeceptive,
      null,
    );
    expect(controller.state.isMutating, isTrue);

    controller.dispose();
    completion.completeError(
      const PublicTemplateFailure(PublicTemplateFailureCode.stale),
    );

    expect(await operation, PublicTemplateReportOutcome.failed);
  });

  test('stale copy refreshes and requires review with a new request ID',
      () async {
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail(version: 4)
      ..copyFailures.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.stale),
      );
    var generated = 0;
    final controller = _detailController(
      repository,
      requestIdGenerator: () => 'request-${++generated}',
    );
    await controller.load();
    repository.detail = _detail(version: 5);

    expect(await controller.copyTemplate(), isNull);
    expect(controller.state.detail.value!.summary.version, 5);
    expect(controller.state.message, PublicTemplatesMessage.staleReview);

    expect(await controller.copyTemplate(), _copiedTemplateId);
    expect(repository.copyRequestIds, ['request-1', 'request-2']);
    controller.dispose();
  });

  test('unavailable reconciliation keeps no optimistic success', () async {
    final repository = _FakePublicTemplateRepository()..detail = _detail();
    final controller = _detailController(repository);
    await controller.load();
    repository.getFailure =
        const PublicTemplateFailure(PublicTemplateFailureCode.unavailable);

    await controller.reconcile();

    expect(controller.state.message, PublicTemplatesMessage.unavailable);
    expect(controller.state.copiedTemplateId, isNull);
    controller.dispose();
  });

  test('late copy completion after disposal does not update state', () async {
    final completion = Completer<PublicTemplateCopyResult>();
    final repository = _FakePublicTemplateRepository()
      ..detail = _detail()
      ..copyHandler = (_, __, ___) => completion.future;
    final controller = _detailController(repository);
    await controller.load();
    final operation = controller.copyTemplate();

    controller.dispose();
    completion.complete(_copyResult());

    expect(await operation, isNull);
  });

  test('mounted owner and viewer projections reconcile independently',
      () async {
    final ownerRepository = _FakePublicTemplateRepository()
      ..pages.add(_page())
      ..pages.add(_page(templates: [_summary(_secondTemplateId)]));
    final viewerRepository = _FakePublicTemplateRepository()
      ..pages.add(_page())
      ..pages.add(_page(templates: [_summary(_templateId, version: 2)]));
    final owner = PublicProfileTemplatesController(
      ownerRepository,
      _FakeCommunityRepository(),
      _profileId,
      hasAuthenticatedUser: true,
      canBlock: false,
      invalidateCommunity: () {},
      invalidateNotifications: () {},
    );
    final viewer = PublicProfileTemplatesController(
      viewerRepository,
      _FakeCommunityRepository(),
      _profileId,
      hasAuthenticatedUser: true,
      canBlock: true,
      invalidateCommunity: () {},
      invalidateNotifications: () {},
    );
    await Future.wait([owner.load(), viewer.load()]);

    await Future.wait([owner.reconcile(), viewer.reconcile()]);

    expect(owner.state.page.value!.templates.single.id, _secondTemplateId);
    expect(viewer.state.page.value!.templates.single.version, 2);
    expect(ownerRepository.listCalls, 2);
    expect(viewerRepository.listCalls, 2);
    owner.dispose();
    viewer.dispose();
  });
}

PublicTemplateDetailController _detailController(
  _FakePublicTemplateRepository repository, {
  String Function()? requestIdGenerator,
  Duration requestTimeout = const Duration(seconds: 15),
}) {
  return PublicTemplateDetailController(
    repository,
    _FakeCommunityRepository(),
    _profileId,
    _templateId,
    canBlock: true,
    invalidatePrivateTemplates: () {},
    invalidateCommunity: () {},
    invalidateNotifications: () {},
    requestIdGenerator: requestIdGenerator ?? (() => _requestId),
    requestTimeout: requestTimeout,
  );
}

class _FakePublicTemplateRepository implements PublicTemplateRepository {
  final Queue<PublicTemplatePage> pages = Queue();
  final Queue<Object> copyFailures = Queue();
  final List<PublicTemplateCursor?> cursors = [];
  final List<String> copyRequestIds = [];
  final Queue<Object> reportFailures = Queue();
  final List<_ReportCall> reportCalls = [];
  PublicTemplateDetail? detail;
  Completer<PublicTemplateDetail>? detailCompleter;
  Object? getFailure;
  int listCalls = 0;
  Future<PublicTemplateCopyResult> Function(String, int, String)? copyHandler;
  Future<PublicTemplateReportResult> Function(
    String,
    int,
    PublicTemplateReportReason,
    String?,
  )? reportHandler;

  @override
  Future<PublicTemplatePage> listProfileTemplates(
    String profileId, {
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  }) async {
    listCalls += 1;
    cursors.add(cursor);
    return pages.removeFirst();
  }

  @override
  Future<PublicTemplateDetail> getTemplate(
    String profileId,
    String templateId,
  ) async {
    if (getFailure != null) throw getFailure!;
    final pending = detailCompleter;
    if (pending != null) return pending.future;
    return detail!;
  }

  @override
  Future<PublicTemplateCopyResult> copyTemplate(
    String templateId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    copyRequestIds.add(requestId);
    if (copyFailures.isNotEmpty) throw copyFailures.removeFirst();
    final handler = copyHandler;
    if (handler != null) {
      return handler(templateId, expectedVersion, requestId);
    }
    return _copyResult();
  }

  @override
  Future<PublicTemplateReportResult> reportTemplate(
    String templateId, {
    required int expectedVersion,
    required PublicTemplateReportReason reason,
    String? explanation,
  }) async {
    reportCalls.add(
      _ReportCall(
        templateId,
        expectedVersion,
        reason,
        explanation,
      ),
    );
    if (reportFailures.isNotEmpty) throw reportFailures.removeFirst();
    final handler = reportHandler;
    if (handler != null) {
      return handler(templateId, expectedVersion, reason, explanation);
    }
    return _reportResult(expectedVersion: expectedVersion);
  }
}

class _ReportCall {
  const _ReportCall(
    this.templateId,
    this.expectedVersion,
    this.reason,
    this.explanation,
  );

  final String templateId;
  final int expectedVersion;
  final PublicTemplateReportReason reason;
  final String? explanation;
}

class _FakeCommunityRepository implements CommunityRepository {
  final List<String> blockedIds = [];

  @override
  Future<void> blockProfile(String profileId) async {
    blockedIds.add(profileId);
  }

  @override
  Future<DiscoveredProfile?> findProfileByUsername(String username) async =>
      null;

  @override
  Future<List<BlockedProfile>> listBlockedProfiles() async => const [];

  @override
  Future<void> unblockProfile(String profileId) async {}
}

PublicTemplatePage _page({
  List<PublicTemplateSummary>? templates,
  PublicTemplateCursor? nextCursor,
}) =>
    PublicTemplatePage(
      profile: _profile,
      templates: templates ?? [_summary(_templateId)],
      nextCursor: nextCursor,
    );

PublicTemplateSummary _summary(
  String id, {
  int version = 1,
}) =>
    PublicTemplateSummary(
      id: id,
      name: 'Public kit',
      version: version,
      itemCount: 0,
      publishedAt: DateTime.utc(2026, 7, 25, 19, 33, 6),
    );

PublicTemplateDetail _detail({int version = 1}) => PublicTemplateDetail(
      profile: _profile,
      summary: _summary(_templateId, version: version),
      items: const [],
    );

PublicTemplateCopyResult _copyResult() => PublicTemplateCopyResult(
      template: PrivateTemplateSummary(
        id: _copiedTemplateId,
        categoryId: null,
        categoryName: null,
        name: 'Public kit',
        version: 1,
        itemCount: 0,
        createdAt: DateTime.utc(2026, 7, 25, 20),
        updatedAt: DateTime.utc(2026, 7, 25, 20),
      ),
    );

PublicTemplateReportResult _reportResult({int expectedVersion = 1}) =>
    PublicTemplateReportResult(
      reportId: '66666666-6666-4666-8666-666666666666',
      groupId: '77777777-7777-4777-8777-777777777777',
      reportedRevision: expectedVersion,
      createdAt: DateTime.utc(2026, 7, 26),
    );

const _profile = PublicTemplateProfile(
  id: _profileId,
  username: 'public_owner',
  displayName: 'Public Owner',
);
final _cursor = PublicTemplateCursor(
  publishedAt: DateTime.utc(2026, 7, 25, 19, 33, 6),
  templateId: _templateId,
);

const _profileId = '11111111-1111-4111-8111-111111111111';
const _templateId = '22222222-2222-4222-8222-222222222222';
const _secondTemplateId = '33333333-3333-4333-8333-333333333333';
const _copiedTemplateId = '44444444-4444-4444-8444-444444444444';
const _requestId = '55555555-5555-4555-8555-555555555555';
