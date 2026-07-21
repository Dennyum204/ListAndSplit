import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_action.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/onboarding_screen.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import 'account_data_export_fixtures.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('renders an accessible destructive flow in ${themeMode.name}',
        (tester) async {
      final repository = FakeAccountDeletionRepository();
      await _pumpAction(
        tester,
        repository: repository,
        themeMode: themeMode,
      );

      expect(find.text('Delete account'), findsOneWidget);
      expect(find.textContaining('Download your data first'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Permanently delete my List & Split account',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('deleteAccountButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.text('exact_name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel closes every stage without invoking deletion',
      (tester) async {
    final repository = FakeAccountDeletionRepository();
    await _pumpAction(tester, repository: repository);

    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelAccountDeletionButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('accountDeletionDialog')), findsNothing);
    expect(repository.deletionCalls, 0);
  });

  testWidgets('shows authoritative shared-list impact without identities',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..impact = const AccountDeletionListImpact(
        ownedSharedListCount: 2,
        affectedParticipantCount: 5,
      );
    await _pumpAction(tester, repository: repository);

    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();

    expect(repository.impactCalls, 1);
    expect(
      find.byKey(const Key('accountDeletionSharedListImpact')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'permanently delete 2 shared lists you own and remove access for 5 non-owner participants',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('impact lookup failure never opens a misleading deletion dialog',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..impactFailure = StateError('offline');
    await _pumpAction(tester, repository: repository);

    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('accountDeletionDialog')), findsNothing);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(repository.deletionCalls, 0);
  });

  testWidgets('submits exact inputs, clears local session and reports success',
      (tester) async {
    final repository = FakeAccountDeletionRepository();
    var routedToSignIn = 0;
    await _pumpAction(
      tester,
      repository: repository,
      onDeleted: () => routedToSignIn += 1,
    );

    await _openAndFill(tester);
    await tester.tap(find.byKey(const Key('confirmAccountDeletionButton')));
    await tester.pumpAndSettle();

    expect(repository.lastEmail, 'person@example.com');
    expect(repository.lastConfirmation, 'exact_name');
    expect(repository.lastPassword, ' Pass Word ');
    expect(repository.clearSessionCalls, 1);
    expect(routedToSignIn, 1);
    expect(find.byKey(const Key('accountDeletionDialog')), findsNothing);
  });

  testWidgets('wrong password keeps account and allows a clean retry',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..deletionFailure = const AccountDeletionFailure(
        AccountDeletionFailureCode.wrongPassword,
      );
    await _pumpAction(tester, repository: repository);

    await _openAndFill(tester);
    await tester.tap(find.byKey(const Key('confirmAccountDeletionButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('password is incorrect'), findsOneWidget);
    expect(repository.clearSessionCalls, 0);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('accountDeletionPasswordField')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      isEmpty,
    );

    repository.deletionFailure = null;
    await tester.enterText(
      find.byKey(const Key('accountDeletionConfirmationField')),
      'exact_name',
    );
    await tester.enterText(
      find.byKey(const Key('accountDeletionPasswordField')),
      'new password',
    );
    await tester.ensureVisible(
      find.byKey(const Key('accountDeletionFinalConfirmation')),
    );
    await tester.tap(find.byKey(const Key('accountDeletionFinalConfirmation')));
    await tester.ensureVisible(
      find.byKey(const Key('confirmAccountDeletionButton')),
    );
    await tester.tap(find.byKey(const Key('confirmAccountDeletionButton')));
    await tester.pumpAndSettle();
    expect(repository.deletionCalls, 2);
  });

  testWidgets('completed Profile keeps export and username deletion entries',
      (tester) async {
    await _pumpScreen(
      tester,
      child: const ProfileScreen(),
      overrides: _screenOverrides(completeProfile: true),
    );

    await tester.ensureVisible(find.byKey(const Key('deleteAccountButton')));
    expect(find.byKey(const Key('downloadAccountDataButton')), findsOneWidget);
    expect(find.byKey(const Key('deleteAccountButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('accountDeletionConfirmationTarget')),
        matching: find.text('fernando_1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('incomplete Onboarding keeps export and email deletion entries',
      (tester) async {
    await _pumpScreen(
      tester,
      child: OnboardingScreen(onSignOut: () async => true),
      overrides: _screenOverrides(completeProfile: false),
    );

    await tester.ensureVisible(find.byKey(const Key('deleteAccountButton')));
    expect(find.byKey(const Key('downloadAccountDataButton')), findsOneWidget);
    expect(find.byKey(const Key('deleteAccountButton')), findsOneWidget);
    expect(find.byKey(const Key('onboardingUsername')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    expect(find.text('person@example.com'), findsOneWidget);
  });
}

Future<void> _openAndFill(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deleteAccountButton')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('accountDeletionConfirmationField')),
    'exact_name',
  );
  await tester.enterText(
    find.byKey(const Key('accountDeletionPasswordField')),
    ' Pass Word ',
  );
  await tester.ensureVisible(
    find.byKey(const Key('accountDeletionFinalConfirmation')),
  );
  await tester.tap(find.byKey(const Key('accountDeletionFinalConfirmation')));
  await tester.ensureVisible(
    find.byKey(const Key('confirmAccountDeletionButton')),
  );
}

Future<void> _pumpAction(
  WidgetTester tester, {
  required FakeAccountDeletionRepository repository,
  ThemeMode themeMode = ThemeMode.light,
  VoidCallback? onDeleted,
}) {
  return _pumpScreen(
    tester,
    themeMode: themeMode,
    overrides: [
      accountDeletionRepositoryProvider.overrideWithValue(repository),
    ],
    child: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: AccountDeletionAction(
          email: 'person@example.com',
          confirmationTarget: 'exact_name',
          onDeleted: onDeleted ?? () {},
        ),
      ),
    ),
  );
}

List<Override> _screenOverrides({required bool completeProfile}) {
  final profile = completeProfile
      ? FakeProfileRepository.completeProfile
      : FakeProfileRepository.incompleteProfile;
  final exportRepository = FakeAccountDataExportRepository()
    ..document = validAccountDataExportDocument(
      incompleteProfile: !completeProfile,
      emptyCollections: !completeProfile,
    );
  return [
    ownProfileProvider.overrideWith((ref) async => profile),
    profileRepositoryProvider.overrideWithValue(
      FakeProfileRepository(profile: profile),
    ),
    accountDataExportRepositoryProvider.overrideWithValue(exportRepository),
    accountDataExportShareServiceProvider.overrideWithValue(
      FakeAccountDataExportShareService(),
    ),
    accountDeletionRepositoryProvider.overrideWithValue(
      FakeAccountDeletionRepository(),
    ),
    notificationRepositoryProvider.overrideWithValue(
      FakeNotificationRepository(),
    ),
  ];
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
        authSessionProvider
            .overrideWith((ref) => Stream.value(verifiedSession)),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(session: verifiedSession),
        ),
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
