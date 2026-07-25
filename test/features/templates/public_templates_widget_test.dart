import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/presentation/public_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_profile_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_public_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
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
}

Future<void> _pump(
  WidgetTester tester, {
  required FakePublicTemplateRepository repository,
  required Locale locale,
  required bool dark,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('viewer-id'),
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

PublicTemplateSummary _summary(
  String id, {
  int itemCount = 1,
}) =>
    PublicTemplateSummary(
      id: id,
      name: 'Trip kit',
      version: 2,
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
