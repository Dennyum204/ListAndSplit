import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/public_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_profile_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_public_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('owned public template exposes the Send action', (tester) async {
    final detail = PublicTemplateDetail(
      profile: _profile,
      summary: _summary(_firstTemplateId, itemCount: 0),
      items: const [],
    );
    final repository = FakePublicTemplateRepository()
      ..detailsByTemplate[_firstTemplateId] = detail;

    await _pump(
      tester,
      repository: repository,
      locale: const Locale('en'),
      dark: false,
      userId: _ownerId,
      child: const PublicTemplateDetailScreen(
        profileId: _ownerId,
        templateId: _firstTemplateId,
      ),
    );

    expect(
        find.byKey(const Key('sendOwnedPublicTemplateButton')), findsOneWidget);
    expect(find.byKey(const Key('reportPublicTemplateButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final configuration in [
    (locale: const Locale('en'), dark: false),
    (locale: const Locale('pt'), dark: true),
  ]) {
    testWidgets(
        'public profile is localized, accessible and overflow-free at 200 percent '
        '(${configuration.locale.languageCode}, ${configuration.dark ? 'dark' : 'light'})',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakePublicTemplateRepository()
        ..queuePage(
          _ownerId,
          PublicTemplatePage(
            profile: _profile,
            templates: [_summary(_firstTemplateId)],
            nextCursor: PublicTemplateCursor(
              publishedAt: _publishedAt,
              templateId: _firstTemplateId,
            ),
          ),
        )
        ..queuePage(
          _ownerId,
          PublicTemplatePage(
            profile: _profile,
            templates: [_summary(_secondTemplateId)],
            nextCursor: null,
          ),
        );

      await _pump(
        tester,
        repository: repository,
        locale: configuration.locale,
        dark: configuration.dark,
        child: const PublicTemplateProfileScreen(profileId: _ownerId),
      );

      expect(find.text('@public_owner'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Trip kit.*1')),
        findsOneWidget,
      );
      final loadMore = find.byKey(const Key('loadMorePublicTemplatesButton'));
      await tester.ensureVisible(loadMore);
      expect(tester.getSize(loadMore).height, greaterThanOrEqualTo(48));
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
      expect(
          find.byKey(const Key('publicTemplate-template-one')), findsOneWidget);
      expect(
          find.byKey(const Key('publicTemplate-template-two')), findsOneWidget);
      final exception = tester.takeException();
      semantics.dispose();
      expect(exception, isNull);
    });
  }

  for (final configuration in [
    (locale: const Locale('en'), dark: true),
    (locale: const Locale('pt'), dark: false),
  ]) {
    testWidgets(
        'public detail exposes only read-only copy actions with accessible quantities '
        '(${configuration.locale.languageCode}, ${configuration.dark ? 'dark' : 'light'})',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final detail = PublicTemplateDetail(
        profile: _profile,
        summary: _summary(_firstTemplateId, itemCount: 1),
        items: [
          PublicTemplateItem(
            name: 'Coffee beans',
            quantity: ListQuantity.tryParse('1.5')!,
            position: 1,
          ),
        ],
      );
      final repository = FakePublicTemplateRepository()
        ..detailsByTemplate[_firstTemplateId] = detail;

      await _pump(
        tester,
        repository: repository,
        locale: configuration.locale,
        dark: configuration.dark,
        child: const PublicTemplateDetailScreen(
          profileId: _ownerId,
          templateId: _firstTemplateId,
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Public Owner.*public_owner')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Coffee beans.*1[,.]5')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('addTemplateItemButton')), findsNothing);
      expect(find.text('Edit template'), findsNothing);
      expect(find.text('Import into existing list'), findsNothing);
      final copyButton = find.byKey(const Key('savePublicTemplateCopyButton'));
      expect(tester.getSize(copyButton).height, greaterThanOrEqualTo(48));
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('confirmSavePublicTemplateCopyButton')),
        findsOneWidget,
      );
      final exception = tester.takeException();
      semantics.dispose();
      expect(exception, isNull);
    });
  }

  for (final configuration in [
    (
      locale: const Locale('en'),
      dark: false,
      labels: const [
        'Spam, scam, or deceptive content',
        'Hate, harassment, or bullying',
        'Sexual content',
        'Violence or dangerous content',
        'Illegal or regulated content',
        'Personal or confidential information',
        'Copyright or trademark concern',
        'Other',
      ],
      requiredMessage: 'Add an explanation for this reason.',
      copyrightNotice:
          'This is an in-app moderation signal, not a formal legal-notice process.',
    ),
    (
      locale: const Locale('pt'),
      dark: true,
      labels: const [
        'Spam, fraude ou conteúdo enganador',
        'Ódio, assédio ou intimidação',
        'Conteúdo sexual',
        'Violência ou conteúdo perigoso',
        'Conteúdo ilegal ou regulamentado',
        'Informação pessoal ou confidencial',
        'Questão de direitos de autor ou marca',
        'Outro',
      ],
      requiredMessage: 'Adicione uma explicação para este motivo.',
      copyrightNotice:
          'Este é um sinal de moderação na aplicação, não um processo formal de notificação legal.',
    ),
  ]) {
    testWidgets(
        'report dialog validates every localized reason without overflow '
        '(${configuration.locale.languageCode}, ${configuration.dark ? 'dark' : 'light'})',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakePublicTemplateRepository()
        ..detailsByTemplate[_firstTemplateId] = _detail();
      final community = FakeCommunityRepository();

      await _pumpReportFlow(
        tester,
        repository: repository,
        community: community,
        locale: configuration.locale,
        dark: configuration.dark,
      );

      final reportAction = tester.widget<IconButton>(
        find.byKey(const Key('reportPublicTemplateButton')),
      );
      expect(
        reportAction.tooltip,
        configuration.locale.languageCode == 'en'
            ? 'Report template'
            : 'Denunciar modelo',
      );
      await tester.tap(
        find.byKey(const Key('reportPublicTemplateButton')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('publicTemplateReportReason')),
      );
      await tester.pumpAndSettle();
      for (final label in configuration.labels) {
        expect(find.text(label), findsAtLeastNWidgets(1));
      }

      final other = find.text(configuration.labels.last).last;
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('submitPublicTemplateReportButton')),
      );
      await tester.pump();
      expect(find.text(configuration.requiredMessage), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('publicTemplateReportReason')),
      );
      await tester.pumpAndSettle();
      final copyright = find.text(configuration.labels[6]).last;
      await tester.ensureVisible(copyright);
      await tester.tap(copyright);
      await tester.pumpAndSettle();
      expect(find.text(configuration.copyrightNotice), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('publicTemplateReportExplanation')),
        '  Specific concern.  ',
      );
      final submit = find.byKey(const Key('submitPublicTemplateReportButton'));
      await tester.tap(submit);
      await tester.tap(submit, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repository.reportCalls, 1);
      expect(repository.reportedTemplateIds, [_firstTemplateId]);
      expect(repository.reportedTemplateVersions, [2]);
      expect(
        repository.reportReasons,
        [PublicTemplateReportReason.copyrightTrademark],
      );
      expect(repository.reportExplanations, ['Specific concern.']);
      expect(
        find.byKey(const Key('blockAfterPublicTemplateReportButton')),
        findsOneWidget,
      );
      expect(community.blockCalls, 0);

      await tester.tap(
        find.byKey(const Key('finishPublicTemplateReportButton')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('communityAfterReport')), findsOneWidget);
      expect(find.text('Trip kit'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('report cancellation preserves access and makes no request',
      (tester) async {
    final repository = FakePublicTemplateRepository()
      ..detailsByTemplate[_firstTemplateId] = _detail();

    await _pumpReportFlow(
      tester,
      repository: repository,
      community: FakeCommunityRepository(),
      locale: const Locale('en'),
      dark: false,
    );
    await tester.tap(find.byKey(const Key('reportPublicTemplateButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('cancelPublicTemplateReportButton')),
    );
    await tester.pumpAndSettle();

    expect(repository.reportCalls, 0);
    expect(find.text('Trip kit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final configuration in [
    (
      locale: const Locale('en'),
      submitting: 'Submitting report…',
      stale:
          'This template changed before your report was submitted. Refresh the latest version and try again.',
    ),
    (
      locale: const Locale('pt'),
      submitting: 'A enviar denúncia…',
      stale:
          'Este modelo foi alterado antes de a denúncia ser enviada. Atualize a versão mais recente e tente novamente.',
    ),
  ]) {
    testWidgets(
        'stale report stops submitting and stays on refreshed detail '
        '(${configuration.locale.languageCode})', (tester) async {
      final completion = Completer<PublicTemplateReportResult>();
      final repository = FakePublicTemplateRepository()
        ..detailsByTemplate[_firstTemplateId] = _detail()
        ..reportCompleter = completion;

      await _pumpReportFlow(
        tester,
        repository: repository,
        community: FakeCommunityRepository(),
        locale: configuration.locale,
        dark: configuration.locale.languageCode == 'pt',
      );
      await tester.tap(find.byKey(const Key('reportPublicTemplateButton')));
      await tester.pumpAndSettle();
      repository.detailsByTemplate[_firstTemplateId] = _detail(version: 3);

      await tester.tap(
        find.byKey(const Key('submitPublicTemplateReportButton')),
      );
      await tester.pump();

      expect(find.text(configuration.submitting), findsOneWidget);
      expect(
        find.byKey(const Key('publicTemplateReportSubmittingIndicator')),
        findsOneWidget,
      );
      expect(repository.reportCalls, 1);
      expect(repository.reportedTemplateVersions, [2]);

      completion.completeError(
        const PublicTemplateFailure(PublicTemplateFailureCode.stale),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.byKey(const Key('publicTemplateReportSubmittingIndicator')),
        findsNothing,
      );
      expect(find.text(configuration.stale), findsOneWidget);
      expect(
        find.byKey(const Key('blockAfterPublicTemplateReportButton')),
        findsNothing,
      );
      expect(find.text('Report submitted'), findsNothing);
      expect(find.byKey(const Key('communityAfterReport')), findsNothing);
      expect(find.text('Trip kit'), findsOneWidget);
      expect(repository.detailCalls, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unexpected report error stops submitting without success',
      (tester) async {
    final completion = Completer<PublicTemplateReportResult>();
    final repository = FakePublicTemplateRepository()
      ..detailsByTemplate[_firstTemplateId] = _detail()
      ..reportCompleter = completion;

    await _pumpReportFlow(
      tester,
      repository: repository,
      community: FakeCommunityRepository(),
      locale: const Locale('en'),
      dark: false,
    );
    await tester.tap(find.byKey(const Key('reportPublicTemplateButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('submitPublicTemplateReportButton')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('publicTemplateReportSubmittingIndicator')),
      findsOneWidget,
    );

    completion.completeError(StateError('unexpected client failure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const Key('publicTemplateReportSubmittingIndicator')),
      findsNothing,
    );
    expect(
      find.text(
        'Public templates could not be loaded or updated. '
        'Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Report submitted'), findsNothing);
    expect(find.byKey(const Key('communityAfterReport')), findsNothing);
    expect(find.text('Trip kit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the report dialog during submission is safe',
      (tester) async {
    final completion = Completer<PublicTemplateReportResult>();
    final repository = FakePublicTemplateRepository()
      ..detailsByTemplate[_firstTemplateId] = _detail()
      ..reportCompleter = completion;

    await _pumpReportFlow(
      tester,
      repository: repository,
      community: FakeCommunityRepository(),
      locale: const Locale('en'),
      dark: false,
    );
    await tester.tap(find.byKey(const Key('reportPublicTemplateButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('submitPublicTemplateReportButton')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('publicTemplateReportSubmittingIndicator')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    completion.completeError(
      const PublicTemplateFailure(PublicTemplateFailureCode.stale),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('optional post-report block remains separate and exactly once',
      (tester) async {
    final repository = FakePublicTemplateRepository()
      ..detailsByTemplate[_firstTemplateId] = _detail();
    final community = FakeCommunityRepository();

    await _pumpReportFlow(
      tester,
      repository: repository,
      community: community,
      locale: const Locale('en'),
      dark: false,
    );
    await tester.tap(find.byKey(const Key('reportPublicTemplateButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('submitPublicTemplateReportButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('blockAfterPublicTemplateReportButton')),
    );
    await tester.tap(
      find.byKey(const Key('blockAfterPublicTemplateReportButton')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(repository.reportCalls, 1);
    expect(community.blockCalls, 1);
    expect(community.lastBlockedProfileId, _ownerId);
    expect(find.byKey(const Key('communityAfterReport')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakePublicTemplateRepository repository,
  required Locale locale,
  required bool dark,
  required Widget child,
  String userId = 'viewer-id',
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(userId),
        publicTemplateRepositoryProvider.overrideWithValue(repository),
        communityRepositoryProvider.overrideWithValue(
          FakeCommunityRepository(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, materialChild) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
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

Future<void> _pumpReportFlow(
  WidgetTester tester, {
  required FakePublicTemplateRepository repository,
  required FakeCommunityRepository community,
  required Locale locale,
  required bool dark,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.publicTemplate(
      _ownerId,
      _firstTemplateId,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.community,
        builder: (_, __) => const Scaffold(
          key: Key('communityAfterReport'),
          body: Text('Community'),
        ),
        routes: [
          GoRoute(
            path: 'profile/:profileId/templates/:templateId',
            builder: (_, state) => PublicTemplateDetailScreen(
              profileId: state.pathParameters['profileId']!,
              templateId: state.pathParameters['templateId']!,
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('viewer-id'),
        publicTemplateRepositoryProvider.overrideWithValue(repository),
        communityRepositoryProvider.overrideWithValue(community),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, materialChild) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
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
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PublicTemplateDetail _detail({int version = 2}) => PublicTemplateDetail(
      profile: _profile,
      summary: _summary(_firstTemplateId, version: version),
      items: [
        const PublicTemplateItem(
          name: 'Coffee beans',
          quantity: ListQuantity.one,
          position: 1,
        ),
      ],
    );

PublicTemplateSummary _summary(
  String id, {
  int itemCount = 1,
  int version = 2,
}) =>
    PublicTemplateSummary(
      id: id,
      name: 'Trip kit',
      version: version,
      itemCount: itemCount,
      publishedAt: _publishedAt,
    );

const _profile = PublicTemplateProfile(
  id: _ownerId,
  username: 'public_owner',
  displayName: 'Public Owner',
);
final _publishedAt = DateTime.utc(2026, 7, 25, 19, 33, 6);
const _ownerId = 'owner-id';
const _firstTemplateId = 'template-one';
const _secondTemplateId = 'template-two';
