import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/moderation/presentation/moderation_case_screen.dart';
import 'package:list_and_split/features/moderation/presentation/moderation_queue_screen.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_public_template_moderation_repository.dart';

void main() {
  for (final configuration in [
    (
      locale: const Locale('en'),
      dark: false,
      filters: const ['Open', 'Taken down', 'Closed'],
      status: 'Content changed after reporting',
    ),
    (
      locale: const Locale('pt'),
      dark: true,
      filters: const ['Abertos', 'Removidos', 'Fechados'],
      status: 'Conteúdo alterado após a denúncia',
    ),
  ]) {
    testWidgets(
        'queue is localized, semantic and overflow-free at 200 percent '
        '(${configuration.locale.languageCode}, ${configuration.dark ? 'dark' : 'light'})',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakePublicTemplateModerationRepository()
        ..queuePage(
          _page(
            ModerationQueueFilter.open,
            cases: [
              _summary(
                groupId: _groupId,
                reportCount: 2,
                sourceChanged: true,
              ),
            ],
            nextCursor: _cursor,
          ),
        )
        ..queuePage(
          _page(
            ModerationQueueFilter.open,
            cases: [_summary(groupId: _secondGroupId)],
          ),
        )
        ..queuePage(_page(ModerationQueueFilter.closed));

      await _pumpScreen(
        tester,
        repository: repository,
        locale: configuration.locale,
        dark: configuration.dark,
        textScale: 2,
        child: const ModerationQueueScreen(),
      );

      for (final filter in configuration.filters) {
        expect(find.text(filter), findsOneWidget);
      }
      expect(
        find.bySemanticsLabel(
          RegExp('Reported template.*2.*${configuration.status}'),
        ),
        findsOneWidget,
      );
      final loadMore = find.byKey(const Key('loadMoreModerationCasesButton'));
      await tester.ensureVisible(loadMore);
      expect(tester.getSize(loadMore).height, greaterThanOrEqualTo(48));
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('moderationCase-$_groupId')), findsOneWidget);
      expect(
        find.byKey(const Key('moderationCase-$_secondGroupId')),
        findsOneWidget,
      );
      expect(repository.queueCursors[1]?.groupId, _groupId);

      await tester.tap(
        find.byKey(const Key('moderationFilter-closed')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('moderationQueueEmpty')),
        findsOneWidget,
      );
      expect(repository.queueCalls.last, ModerationQueueFilter.closed);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets(
      'queue routes by immutable group ID and shows snapshot beside current data',
      (tester) async {
    final repository = FakePublicTemplateModerationRepository()
      ..queuePage(
        _page(
          ModerationQueueFilter.open,
          cases: [_summary(groupId: _groupId, reportCount: 2)],
        ),
      )
      ..caseResults.add(_case());
    final router = _moderationRouter();
    addTearDown(router.dispose);

    await _pumpRouter(tester, repository: repository, router: router);
    final routeCase = find.byKey(const Key('moderationCase-$_groupId'));
    await tester.ensureVisible(routeCase);
    expect(tester.widget<ListTile>(routeCase).onTap, isNotNull);
    router.go(AppRoutes.moderationCase(_groupId));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.moderationCase(_groupId));
    expect(repository.caseCalls, [_groupId]);
    expect(find.text('Reported template'), findsWidgets);
    expect(find.text('Current edited template'), findsOneWidget);
    expect(find.byKey(const Key('moderationReportedSnapshot')), findsOneWidget);
    expect(find.byKey(const Key('moderationCurrentContent')), findsOneWidget);
    await _scrollCaseTo(
      tester,
      find.byKey(const Key('moderationReport-$_reportId')),
    );
    expect(find.text('Reporter One (@reporter_one)'), findsOneWidget);
    await _scrollCaseTo(
      tester,
      find.byKey(const Key('moderationReport-$_secondReportId')),
    );
    expect(find.text('Deleted or anonymized account'), findsOneWidget);
    expect(find.text('Private category'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'take-down and restore confirmations validate notes and submit once',
      (tester) async {
    final pending = Completer<ModerationActionResult>();
    final repository = FakePublicTemplateModerationRepository()
      ..caseResults.addAll([
        _case(),
        _case(
          restricted: true,
          status: 'taken_down',
          version: 2,
          templateVersion: 6,
        ),
        _case(status: 'taken_down', version: 2, templateVersion: 7),
      ])
      ..actionCompleter = pending;

    await _pumpScreen(
      tester,
      repository: repository,
      locale: const Locale('en'),
      dark: true,
      child: const ModerationCaseScreen(groupId: _groupId),
    );
    await _scrollCaseTo(
      tester,
      find.byKey(const Key('takeDownModerationCaseButton')),
    );
    await tester.tap(
      find.byKey(const Key('takeDownModerationCaseButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirmModerationActionButton')),
    );
    await tester.pump();
    expect(find.text('Add a private moderator note.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('moderationPrivateNoteField')),
      '  Reviewed public evidence.  ',
    );
    final confirm = find.byKey(const Key('confirmModerationActionButton'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    expect(repository.actionCalls, hasLength(1));

    final takeDown = repository.actionCalls.single;
    expect(takeDown.action, PublicTemplateModerationAction.takeDown);
    expect(takeDown.targetId, _groupId);
    expect(takeDown.expectedGroupVersion, 1);
    expect(takeDown.expectedTemplateVersion, 5);
    expect(
      takeDown.ownerReason,
      PublicTemplateReportReason.spamScamDeceptive,
    );
    expect(takeDown.privateNote, 'Reviewed public evidence.');

    pending.complete(
      ModerationActionResult(
        eventId: _eventId,
        action: PublicTemplateModerationAction.takeDown,
        groupId: _groupId,
        groupVersion: 2,
        restrictionVersion: 1,
        templateVersion: 6,
        createdAt: DateTime.utc(2026, 7, 26, 8),
      ),
    );
    repository.actionCompleter = null;
    await tester.pumpAndSettle();
    await _scrollCaseTo(
      tester,
      find.byKey(const Key('restoreModerationCaseButton')),
    );
    expect(
      find.byKey(const Key('restoreModerationCaseButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('restoreModerationCaseButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('cancelModerationActionButton')),
    );
    await tester.pumpAndSettle();
    expect(repository.actionCalls, hasLength(1));

    await tester.tap(
      find.byKey(const Key('restoreModerationCaseButton')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('moderationPrivateNoteField')),
      'Restriction reviewed and lifted.',
    );
    await tester.tap(
      find.byKey(const Key('confirmModerationActionButton')),
    );
    await tester.pumpAndSettle();

    expect(repository.actionCalls, hasLength(2));
    final restore = repository.actionCalls.last;
    expect(restore.action, PublicTemplateModerationAction.restore);
    expect(restore.targetId, _templateId);
    expect(restore.expectedRestrictionVersion, 1);
    expect(restore.expectedTemplateVersion, 6);
    expect(find.byKey(const Key('restoreModerationCaseButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismiss confirmation is private-note-bound and cancellable',
      (tester) async {
    final repository = FakePublicTemplateModerationRepository()
      ..caseResults.addAll([
        _case(),
        _case(status: 'dismissed', version: 2),
      ]);
    await _pumpScreen(
      tester,
      repository: repository,
      locale: const Locale('pt'),
      dark: false,
      child: const ModerationCaseScreen(groupId: _groupId),
    );

    await _scrollCaseTo(
      tester,
      find.byKey(const Key('dismissModerationCaseButton')),
    );
    await tester.tap(find.byKey(const Key('dismissModerationCaseButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelModerationActionButton')));
    await tester.pumpAndSettle();
    expect(repository.actionCalls, isEmpty);

    await tester.tap(find.byKey(const Key('dismissModerationCaseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('moderationPrivateNoteField')),
      '  Sem infração confirmada.  ',
    );
    await tester.tap(find.byKey(const Key('confirmModerationActionButton')));
    await tester.pumpAndSettle();

    expect(repository.actionCalls, hasLength(1));
    expect(
      repository.actionCalls.single.action,
      PublicTemplateModerationAction.dismiss,
    );
    expect(
      repository.actionCalls.single.privateNote,
      'Sem infração confirmada.',
    );
    expect(find.byKey(const Key('dismissModerationCaseButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked access clears protected data and exits exactly once',
      (tester) async {
    final repository = FakePublicTemplateModerationRepository()
      ..queuePage(
        _page(
          ModerationQueueFilter.open,
          cases: [_summary(groupId: _groupId)],
        ),
      );
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(_moderatorId),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = _moderationRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _routerApp(router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moderationCase-$_groupId')), findsOneWidget);

    repository.queueFailure = const PublicTemplateModerationFailure(
      PublicTemplateModerationFailureCode.revoked,
    );
    final controller =
        container.read(moderationQueueControllerProvider.notifier);
    await Future.wait([controller.load(), controller.load()]);
    await controller.load();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileAfterRevocation')), findsOneWidget);
    expect(find.byKey(const Key('moderationCase-$_groupId')), findsNothing);
    expect(
      find.text('Your moderation access was removed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakePublicTemplateModerationRepository repository,
  required Locale locale,
  required bool dark,
  required Widget child,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(_moderatorId),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, materialChild) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: materialChild!,
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollCaseTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    320,
    scrollable: find.descendant(
      of: find.byKey(const Key('moderationCaseScroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRouter(
  WidgetTester tester, {
  required FakePublicTemplateModerationRepository repository,
  required GoRouter router,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(_moderatorId),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
      child: _routerApp(router),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _routerApp(GoRouter router) => MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );

GoRouter _moderationRouter() => GoRouter(
      initialLocation: AppRoutes.moderation,
      routes: [
        GoRoute(
          path: AppRoutes.profile,
          builder: (_, __) => const Scaffold(
            key: Key('profileAfterRevocation'),
            body: Text('Profile'),
          ),
          routes: [
            GoRoute(
              path: 'moderation',
              builder: (_, __) => const ModerationQueueScreen(),
              routes: [
                GoRoute(
                  path: ':groupId',
                  builder: (_, state) => ModerationCaseScreen(
                    groupId: state.pathParameters['groupId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

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

ModerationQueueCase _summary({
  required String groupId,
  int reportCount = 1,
  String status = 'open',
  int version = 1,
  bool sourceChanged = false,
  bool restricted = false,
}) =>
    ModerationQueueCase(
      groupId: groupId,
      templateId: _templateId,
      templateName: 'Reported template',
      reportedRevision: 4,
      reportCount: reportCount,
      status: status,
      version: version,
      firstReportedAt: DateTime.utc(2026, 7, 26, 6),
      closedAt: status == 'open' ? null : DateTime.utc(2026, 7, 26, 7),
      sourceChanged: sourceChanged,
      sourceUnpublished: restricted,
      sourceDeleted: false,
      sourceModerated: restricted,
      isRestricted: restricted,
      restrictionVersion: restricted ? 1 : null,
    );

PublicTemplateModerationCase _case({
  bool restricted = false,
  String status = 'open',
  int version = 1,
  int templateVersion = 5,
}) =>
    PublicTemplateModerationCase(
      summary: _summary(
        groupId: _groupId,
        reportCount: 2,
        status: status,
        version: version,
        sourceChanged: true,
        restricted: restricted,
      ),
      reportedSnapshot: ModerationTemplateSnapshot(
        name: 'Reported template',
        items: [
          const ModerationSnapshotItem(
            name: 'Water',
            quantity: ListQuantity.one,
            position: 1,
          ),
        ],
      ),
      reports: [
        ModerationReport(
          id: _reportId,
          reason: PublicTemplateReportReason.other,
          explanation: 'Specific public-content concern.',
          createdAt: DateTime.utc(2026, 7, 26, 6),
          reporter: const ModerationReporterProfile(
            id: _reporterId,
            username: 'reporter_one',
            displayName: 'Reporter One',
          ),
        ),
        ModerationReport(
          id: _secondReportId,
          reason: PublicTemplateReportReason.spamScamDeceptive,
          explanation: null,
          createdAt: DateTime.utc(2026, 7, 26, 6, 1),
          reporter: null,
        ),
      ],
      currentTemplate: ModerationCurrentTemplate(
        id: _templateId,
        name: 'Current edited template',
        version: templateVersion,
        isPublic: !restricted,
        items: [
          ModerationSnapshotItem(
            name: 'Water bottles',
            quantity: ListQuantity.fromThousandths(2000),
            position: 1,
          ),
        ],
      ),
      restriction: restricted
          ? ModerationRestriction(
              active: true,
              version: 1,
              reason: PublicTemplateReportReason.spamScamDeceptive,
              imposedAt: DateTime.utc(2026, 7, 26, 7),
              restoredAt: null,
              sourceDeletedAt: null,
            )
          : null,
    );

final _cursor = ModerationQueueCursor(
  at: DateTime.utc(2026, 7, 26, 6),
  groupId: _groupId,
);
const _moderatorId = '11111111-1111-4111-8111-111111111111';
const _groupId = '22222222-2222-4222-8222-222222222222';
const _secondGroupId = '33333333-3333-4333-8333-333333333333';
const _templateId = '44444444-4444-4444-8444-444444444444';
const _reportId = '55555555-5555-4555-8555-555555555555';
const _secondReportId = '66666666-6666-4666-8666-666666666666';
const _reporterId = '77777777-7777-4777-8777-777777777777';
const _eventId = '88888888-8888-4888-8888-888888888888';
