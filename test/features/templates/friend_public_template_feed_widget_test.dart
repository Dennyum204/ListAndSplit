import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/friend_public_template_feed_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_friend_public_template_feed_repository.dart';

void main() {
  for (final configuration in [
    (locale: const Locale('en'), dark: false),
    (locale: const Locale('pt'), dark: true),
  ]) {
    testWidgets(
        'feed is localized, accessible and overflow-free at 200 percent '
        '(${configuration.locale.languageCode}, ${configuration.dark ? 'dark' : 'light'})',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = FakeFriendPublicTemplateFeedRepository()
        ..outcomes.add(
          _page([
            _entry(
              profileId: _firstProfileId,
              templateId: _firstTemplateId,
            ),
            _entry(
              profileId: _secondProfileId,
              templateId: _secondTemplateId,
            ),
          ]),
        );
      await _pump(
        tester,
        repository,
        locale: configuration.locale,
        dark: configuration.dark,
      );

      expect(find.byType(FriendPublicTemplateFeedScreen), findsOneWidget);
      expect(find.text('Duplicate trip'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel(RegExp('Duplicate trip.*public_friend')),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('friendTemplateCard-$_firstTemplateId')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const Key('openFriendTemplateOwner-$_firstProfileId'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
          find.byKey(const Key('savePublicTemplateCopyButton')), findsNothing);
      expect(find.byKey(const Key('reportPublicTemplateButton')), findsNothing);

      await tester.tap(
        find.byKey(const Key('openFriendTemplate-$_firstTemplateId')),
      );
      await tester.pumpAndSettle();
      final detail = tester.widget<_TemplateProbe>(
        find.byType(_TemplateProbe),
      );
      expect(detail.profileId, _firstProfileId);
      expect(detail.templateId, _firstTemplateId);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FriendPublicTemplateFeedScreen), findsOneWidget);
      expect(repository.calls, 1);

      await tester.tap(
        find.byKey(
          const Key('openFriendTemplateOwner-$_secondProfileId'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<_ProfileProbe>(find.byType(_ProfileProbe)).profileId,
        _secondProfileId,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('initial failure retries into the privacy-neutral empty state',
      (tester) async {
    final repository = FakeFriendPublicTemplateFeedRepository()
      ..outcomes.add(
        const PublicTemplateFailure(PublicTemplateFailureCode.transport),
      )
      ..outcomes.add(_page(const []));
    await _pump(tester, repository);

    expect(find.byKey(const Key('retryFriendTemplatesButton')), findsOneWidget);
    expect(find.text('No templates to show'), findsNothing);

    await tester.tap(find.byKey(const Key('retryFriendTemplatesButton')));
    await tester.pumpAndSettle();

    expect(find.text('No templates to show'), findsOneWidget);
    expect(find.textContaining('not friends'), findsNothing);
    expect(repository.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load-more failure is retained and explicitly retryable',
      (tester) async {
    final repository = FakeFriendPublicTemplateFeedRepository()
      ..outcomes.add(
        _page(
          [_entry()],
          nextCursor: _cursor,
        ),
      )
      ..outcomes.add(StateError('offline'))
      ..outcomes.add(
        _page([
          _entry(),
          _entry(
            profileId: _secondProfileId,
            templateId: _secondTemplateId,
          ),
        ]),
      );
    await _pump(tester, repository);

    await tester.tap(
      find.byKey(const Key('loadMoreFriendTemplatesButton')),
    );
    await tester.pumpAndSettle();

    expect(find.text('More templates could not be loaded. Try again.'),
        findsOneWidget);
    expect(find.text('Retry loading more'), findsOneWidget);
    expect(
      find.byKey(const Key('friendTemplateCard-$_firstTemplateId')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('loadMoreFriendTemplatesButton')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('friendTemplateCard-$_firstTemplateId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('friendTemplateCard-$_secondTemplateId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('loadMoreFriendTemplatesButton')),
      findsNothing,
    );
    expect(repository.calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-to-refresh reloads the authoritative first page',
      (tester) async {
    final repository = FakeFriendPublicTemplateFeedRepository()
      ..outcomes.add(_page([_entry()]))
      ..outcomes.add(
        _page([
          _entry(
            profileId: _secondProfileId,
            templateId: _secondTemplateId,
          ),
        ]),
      );
    await _pump(tester, repository);

    await tester.fling(
      find.byKey(const Key('friendTemplateFeedList')),
      const Offset(0, 420),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(
      find.byKey(const Key('friendTemplateCard-$_firstTemplateId')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('friendTemplateCard-$_secondTemplateId')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'refresh retains data, reports once, guards repeats and reconciles later',
      (tester) async {
    final repository = FakeFriendPublicTemplateFeedRepository()
      ..outcomes.add(_page([_entry()]))
      ..outcomes.add(StateError('offline'))
      ..outcomes.add(
        _page([
          _entry(
            profileId: _secondProfileId,
            templateId: _secondTemplateId,
          ),
        ]),
      );
    final container = await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('refreshFriendTemplatesButton')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The latest templates could not be loaded. '
        'Your previous results are still shown.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('friendTemplateCard-$_firstTemplateId')),
      findsOneWidget,
    );

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('friendTemplateCard-$_secondTemplateId')),
      findsOneWidget,
    );
    expect(repository.calls, 3);

    final completion = Completer<FriendPublicTemplatePage>();
    repository.completer = completion;
    await tester.tap(find.byKey(const Key('refreshFriendTemplatesButton')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('refreshFriendTemplatesButton')),
      warnIfMissed: false,
    );
    expect(repository.calls, 4);
    completion.complete(
      _page([
        _entry(
          profileId: _secondProfileId,
          templateId: _secondTemplateId,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeFriendPublicTemplateFeedRepository repository, {
  Locale locale = const Locale('en'),
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      verifiedUserIdProvider.overrideWithValue(_viewerId),
      friendPublicTemplateFeedRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: AppRoutes.friendTemplates,
    routes: [
      GoRoute(
        path: AppRoutes.community,
        builder: (context, state) =>
            const Scaffold(body: Text('Community root')),
        routes: [
          GoRoute(
            path: 'friends-templates',
            builder: (context, state) => const FriendPublicTemplateFeedScreen(),
          ),
          GoRoute(
            path: 'profile/:profileId',
            builder: (context, state) => _ProfileProbe(
              profileId: state.pathParameters['profileId']!,
            ),
            routes: [
              GoRoute(
                path: 'templates/:templateId',
                builder: (context, state) => _TemplateProbe(
                  profileId: state.pathParameters['profileId']!,
                  templateId: state.pathParameters['templateId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class _ProfileProbe extends StatelessWidget {
  const _ProfileProbe({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('profile:$profileId'));
  }
}

class _TemplateProbe extends StatelessWidget {
  const _TemplateProbe({
    required this.profileId,
    required this.templateId,
  });

  final String profileId;
  final String templateId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('template:$profileId:$templateId'));
  }
}

FriendPublicTemplatePage _page(
  List<FriendPublicTemplateEntry> entries, {
  PublicTemplateCursor? nextCursor,
}) {
  return FriendPublicTemplatePage(
    entries: entries,
    nextCursor: nextCursor,
  );
}

FriendPublicTemplateEntry _entry({
  String profileId = _firstProfileId,
  String templateId = _firstTemplateId,
}) {
  return FriendPublicTemplateEntry(
    profile: PublicTemplateProfile(
      id: profileId,
      username:
          profileId == _firstProfileId ? 'public_friend' : 'second_friend',
      displayName:
          profileId == _firstProfileId ? 'Public Friend' : 'Second Friend',
    ),
    template: PublicTemplateSummary(
      id: templateId,
      name: 'Duplicate trip',
      version: 2,
      itemCount: 3,
      publishedAt: DateTime.utc(2026, 7, 27, 12),
    ),
  );
}

final _cursor = PublicTemplateCursor(
  publishedAt: DateTime.utc(2026, 7, 27, 12),
  templateId: _firstTemplateId,
);

const _viewerId = '00000000-0000-4000-8000-000000000001';
const _firstProfileId = '11111111-1111-4111-8111-111111111111';
const _secondProfileId = '22222222-2222-4222-8222-222222222222';
const _firstTemplateId = '33333333-3333-4333-8333-333333333333';
const _secondTemplateId = '44444444-4444-4444-8444-444444444444';
