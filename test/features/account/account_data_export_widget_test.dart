import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_action.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/onboarding_screen.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import 'account_data_export_fixtures.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('renders localized accessible action in ${themeMode.name}',
        (tester) async {
      final repository = FakeAccountDataExportRepository()
        ..document = validAccountDataExportDocument();
      await _pumpAction(
        tester,
        repository: repository,
        themeMode: themeMode,
      );

      expect(find.text('Account and data'), findsOneWidget);
      expect(find.textContaining('personal information'), findsOneWidget);
      expect(find.text('Download my data'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Download my account data as a JSON file'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('asks for confirmation and reports success safely',
      (tester) async {
    final repository = FakeAccountDataExportRepository()
      ..document = validAccountDataExportDocument();
    final shareService = FakeAccountDataExportShareService();
    await _pumpAction(
      tester,
      repository: repository,
      shareService: shareService,
    );

    await tester.tap(find.byKey(const Key('downloadAccountDataButton')));
    await tester.pumpAndSettle();
    expect(find.text('Download your data?'), findsOneWidget);
    expect(find.textContaining('server does not retain'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.exportCalls, 0);

    await tester.tap(find.byKey(const Key('downloadAccountDataButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAccountDataExportButton')));
    await tester.pumpAndSettle();

    expect(repository.exportCalls, 1);
    expect(shareService.shareCalls, 1);
    expect(find.textContaining('ready in the share sheet'), findsOneWidget);
  });

  testWidgets('reports a dismissed share sheet and remains retryable',
      (tester) async {
    final repository = FakeAccountDataExportRepository()
      ..document = validAccountDataExportDocument();
    final shareService = FakeAccountDataExportShareService()
      ..result = AccountDataShareResult.dismissed;
    await _pumpAction(
      tester,
      repository: repository,
      shareService: shareService,
    );

    await tester.tap(find.byKey(const Key('downloadAccountDataButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAccountDataExportButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('share sheet was closed'), findsOneWidget);
    await tester.tap(find.byKey(const Key('downloadAccountDataButton')));
    await tester.pumpAndSettle();
    expect(find.text('Download your data?'), findsOneWidget);
  });

  testWidgets('completed Profile contains the account data entry point',
      (tester) async {
    final repository = FakeAccountDataExportRepository()
      ..document = validAccountDataExportDocument();
    await _pumpScreen(
      tester,
      child: const ProfileScreen(),
      overrides: [
        ownProfileProvider.overrideWith(
          (ref) async => FakeProfileRepository.completeProfile,
        ),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(
            profile: FakeProfileRepository.completeProfile,
          ),
        ),
        accountDataExportRepositoryProvider.overrideWithValue(repository),
        accountDataExportShareServiceProvider.overrideWithValue(
          FakeAccountDataExportShareService(),
        ),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
      ],
    );

    await tester.ensureVisible(
      find.byKey(const Key('downloadAccountDataButton')),
    );
    expect(find.byKey(const Key('accountDataExportSection')), findsOneWidget);
  });

  testWidgets('verified incomplete Onboarding exports without profile input',
      (tester) async {
    final repository = FakeAccountDataExportRepository()
      ..document = validAccountDataExportDocument(
        incompleteProfile: true,
        emptyCollections: true,
      );
    final shareService = FakeAccountDataExportShareService();
    await _pumpScreen(
      tester,
      child: OnboardingScreen(onSignOut: () async => true),
      overrides: [
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        accountDataExportRepositoryProvider.overrideWithValue(repository),
        accountDataExportShareServiceProvider.overrideWithValue(shareService),
      ],
    );

    await tester.ensureVisible(
      find.byKey(const Key('downloadAccountDataButton')),
    );
    await tester.tap(find.byKey(const Key('downloadAccountDataButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAccountDataExportButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboardingUsername')), findsOneWidget);
    expect(repository.exportCalls, 1);
    expect(shareService.shareCalls, 1);
  });
}

Future<void> _pumpAction(
  WidgetTester tester, {
  required FakeAccountDataExportRepository repository,
  FakeAccountDataExportShareService? shareService,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return _pumpScreen(
    tester,
    child: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: AccountDataExportAction(),
      ),
    ),
    themeMode: themeMode,
    overrides: [
      accountDataExportRepositoryProvider.overrideWithValue(repository),
      accountDataExportShareServiceProvider.overrideWithValue(
        shareService ?? FakeAccountDataExportShareService(),
      ),
    ],
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
