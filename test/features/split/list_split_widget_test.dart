import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';
import 'package:list_and_split/features/split/presentation/list_split_providers.dart';
import 'package:list_and_split/features/split/presentation/list_split_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_list_split_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('owner enables Split while member sees owner-only guidance',
      (tester) async {
    final ownerRepository = FakeListSplitRepository(
      initial: disabledSplitOverview(),
    );
    await _pump(tester, ownerRepository);

    expect(find.byKey(const Key('splitDisabledState')), findsOneWidget);
    expect(find.byKey(const Key('enableSplitButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('splitCurrencyField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enableSplitButton')));
    await tester.pumpAndSettle();

    expect(ownerRepository.enableCalls, 1);
    expect(find.textContaining('EUR'), findsWidgets);
    expect(find.byKey(const Key('addExpenseButton')), findsOneWidget);

    final memberRepository = FakeListSplitRepository(
      initial: disabledSplitOverview(isOwner: false),
    );
    await _pump(tester, memberRepository);
    expect(find.byKey(const Key('splitDisabledState')), findsOneWidget);
    expect(find.byKey(const Key('enableSplitButton')), findsNothing);
    expect(find.textContaining('owner'), findsOneWidget);
  });

  testWidgets('load failure is recoverable through the retry action',
      (tester) async {
    final repository = FakeListSplitRepository()
      ..failure = const ListSplitFailure(ListSplitFailureCode.transport);
    await _pump(tester, repository);
    expect(find.byKey(const Key('retrySplitButton')), findsOneWidget);

    repository.failure = null;
    await tester.tap(find.byKey(const Key('retrySplitButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splitOverview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows loading then the authoritative empty state',
      (tester) async {
    final repository = FakeListSplitRepository()
      ..getCompleter = Completer<ListSplitOverview>();
    await _pump(tester, repository, settle: false);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    repository.getCompleter!.complete(repository.overview);
    repository.getCompleter = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splitOverview')), findsOneWidget);
    await _scrollSplitUntilVisible(
      tester,
      find.textContaining('No expenses yet'),
    );
    expect(find.textContaining('No expenses yet'), findsOneWidget);
  });

  testWidgets('creates an exact payer-excluded expense from the editor',
      (tester) async {
    final repository = FakeListSplitRepository();
    final notifications = FakeNotificationRepository();
    await _pump(tester, repository, notifications: notifications);

    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Train ticket',
    );
    await tester.enterText(
      find.byKey(const Key('splitExpenseAmountField')),
      '10.01',
    );
    await tester.tap(
      find.byKey(const ValueKey('splitBeneficiary-$splitOwnerParticipantId')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.createCalls, 1);
    final created = repository.overview.expenses.single;
    expect(created.description, 'Train ticket');
    expect(created.amountMinor, 1001);
    expect(created.payerParticipantId, splitOwnerParticipantId);
    expect(created.beneficiaryParticipantIds, [splitMemberParticipantId]);
    expect(created.shares.single.amountMinor, 1001);
    await _scrollSplitUntilVisible(tester, find.text('Train ticket'));
    expect(find.text('Train ticket'), findsOneWidget);
    expect(notifications.markCalls, isEmpty);
    expect(notifications.notifications, isEmpty);
  });

  testWidgets('renders positive, negative, zero, and historical balances',
      (tester) async {
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(
        participants: const [
          ListSplitParticipant(
            id: splitOwnerParticipantId,
            profileId: splitOwnerProfileId,
            username: 'fernando',
            displayName: 'Fernando',
            isAnonymized: false,
            isCurrent: true,
            paidMinor: 1000,
            owedMinor: 500,
            balanceMinor: 500,
          ),
          ListSplitParticipant(
            id: splitMemberParticipantId,
            profileId: splitMemberProfileId,
            username: 'susana',
            displayName: 'Susana',
            isAnonymized: false,
            isCurrent: true,
            paidMinor: 0,
            owedMinor: 500,
            balanceMinor: -500,
          ),
          ListSplitParticipant(
            id: '30000000-0000-4000-8000-000000000003',
            profileId: null,
            username: null,
            displayName: null,
            isAnonymized: true,
            isCurrent: false,
            paidMinor: 250,
            owedMinor: 250,
            balanceMinor: 0,
          ),
        ],
      ),
    );
    await _pump(tester, repository);

    expect(find.text('You are owed CHF 5.00'), findsOneWidget);
    expect(find.text('Fernando is owed CHF 5.00'), findsOneWidget);
    expect(find.text('Susana owes CHF 5.00'), findsOneWidget);
    expect(find.text('Former participant is settled up'), findsOneWidget);
  });

  testWidgets('invalid amount and zero beneficiaries never submit',
      (tester) async {
    final repository = FakeListSplitRepository();
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Coffee',
    );
    await tester.enterText(
      find.byKey(const Key('splitExpenseAmountField')),
      '0',
    );
    for (final participantId in [
      splitOwnerParticipantId,
      splitMemberParticipantId,
    ]) {
      final checkbox = find.byKey(ValueKey('splitBeneficiary-$participantId'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
    }
    final save = find.byKey(const Key('saveSplitExpenseButton'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.createCalls, 0);
    expect(
      find.text(
        'Enter a positive supported amount with up to two decimal places.',
      ),
      findsOneWidget,
    );
    expect(
        find.text('Choose at least one eligible participant.'), findsOneWidget);
  });

  testWidgets('active accepted member can create an expense', (tester) async {
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(isOwner: false),
    );
    await _pump(
      tester,
      repository,
      authenticatedProfileId: splitMemberProfileId,
    );
    await _openCompletedCreateEditor(tester);
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.overview.expenses.single.description, 'Coffee');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Realtime reconciliation renders remote add and edit',
      (tester) async {
    final repository = FakeListSplitRepository();
    final container = await _pump(tester, repository);
    final registry = container.read(reconciliationRegistryProvider);
    repository.overview = enabledSplitOverview(
      expenses: [splitExpense(description: 'Remote coffee')],
    );
    await registry.reconcile();
    await tester.pumpAndSettle();
    await _scrollSplitUntilVisible(tester, find.text('Remote coffee'));
    expect(find.text('Remote coffee'), findsOneWidget);

    repository.overview = enabledSplitOverview(
      expenses: [splitExpense(description: 'Remote edited coffee')],
    );
    await registry.reconcile();
    await tester.pumpAndSettle();
    await _scrollSplitUntilVisible(tester, find.text('Remote edited coffee'));
    expect(find.text('Remote coffee'), findsNothing);
    expect(find.text('Remote edited coffee'), findsOneWidget);
  });

  testWidgets('local edit success updates the expense authoritatively',
      (tester) async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    await _pump(tester, repository);
    await _scrollSplitUntilVisible(
      tester,
      find.byKey(ValueKey('splitExpense-${expense.id}')),
    );
    await tester.tap(find.byKey(ValueKey('splitExpense-${expense.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Updated dinner',
    );
    await tester.enterText(
      find.byKey(const Key('splitExpenseAmountField')),
      '12.00',
    );
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.overview.expenses.single.amountMinor, 1200);
    expect(find.text('Updated dinner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid repeated create submission executes once', (tester) async {
    final repository = FakeListSplitRepository();
    await _pump(tester, repository);
    await _openCompletedCreateEditor(tester);
    repository.mutationCompleter = Completer<ListSplitOverview>();
    final save = find.byKey(const Key('saveSplitExpenseButton'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();

    expect(repository.createCalls, 1);
    repository.mutationCompleter!.complete(repository.overview);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(repository.overview.expenses, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme and large text keep controls scrollable and semantic',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    final semantics = tester.ensureSemantics();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [splitExpense()]),
    );
    await _pump(
      tester,
      repository,
      dark: true,
      textScale: 2,
    );
    expect(find.bySemanticsLabel('Add expense'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('saveSplitExpenseButton'));
    await tester.ensureVisible(save);
    expect(save, findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
      'same editor retries one UUID and a new identical editor gets new UUID',
      (tester) async {
    final repository = FakeListSplitRepository();
    await _pump(tester, repository);
    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.invalid);

    await _openCompletedCreateEditor(tester);
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormDialog), findsNothing);

    await _openCompletedCreateEditor(tester);
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();

    expect(repository.requestIds, hasLength(3));
    expect(repository.requestIds[0], repository.requestIds[1]);
    expect(repository.requestIds[2], isNot(repository.requestIds[0]));
    expect(repository.overview.expenses, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'remote archive closes an open editor exactly once and stays on Split',
      (tester) async {
    final repository = FakeListSplitRepository();
    final container = await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseFormDialog), findsOneWidget);

    repository.overview = enabledSplitOverview(
      status: SplitListStatus.archived,
      writable: false,
    );
    await container
        .read(listSplitControllerProvider(splitListId).notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(find.byKey(const Key('addExpenseButton')), findsNothing);
    expect(find.textContaining('archived'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'current-user access removal closes the editor and discards unsaved edits',
      (tester) async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    final container = await _pump(
      tester,
      repository,
      authenticatedProfileId: splitMemberProfileId,
    );
    await _scrollSplitUntilVisible(
      tester,
      find.byKey(ValueKey('splitExpense-${expense.id}')),
    );
    await tester.tap(find.byKey(ValueKey('splitExpense-${expense.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Unsaved replacement',
    );

    repository.failure =
        const ListSplitFailure(ListSplitFailureCode.unavailable);
    final controller =
        container.read(listSplitControllerProvider(splitListId).notifier);
    await Future.wait([controller.reconcile(), controller.reconcile()]);
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(find.byKey(const Key('saveSplitExpenseButton')), findsNothing);
    expect(repository.updateCalls, 0);
    expect(
        repository.overview.expenses.single.description, expense.description);
    expect(
      repository.overview.participants
          .map((participant) => participant.balanceMinor),
      enabledSplitOverview(expenses: [expense])
          .participants
          .map((participant) => participant.balanceMinor),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed selected payer clears safely and requires reselection',
      (tester) async {
    final repository = FakeListSplitRepository();
    final container = await _pump(tester, repository);
    await _openCompletedCreateEditor(tester);
    await tester.tap(find.byKey(const Key('splitExpensePayerField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Susana').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('splitExpensePayerField')));
    await tester.pumpAndSettle();
    repository.overview = enabledSplitOverview(
      participants: [splitParticipants().first],
    );
    final controller =
        container.read(listSplitControllerProvider(splitListId).notifier);
    await Future.wait([controller.reconcile(), controller.reconcile()]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final payerField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('splitExpensePayerField')),
    );
    expect(payerField.initialValue, isNull);
    final selectAll = find.byKey(const Key('selectAllSplitParticipantsButton'));
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 0);
    expect(find.byType(ExpenseFormDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('splitExpensePayerField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fernando').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote deletion closes editor safely even with payer menu open',
      (tester) async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    final container = await _pump(tester, repository);
    await _scrollSplitUntilVisible(
      tester,
      find.byKey(ValueKey('splitExpense-${expense.id}')),
    );
    await tester.tap(find.byKey(ValueKey('splitExpense-${expense.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('splitExpensePayerField')));
    await tester.pumpAndSettle();

    repository.overview = enabledSplitOverview();
    await container
        .read(listSplitControllerProvider(splitListId).notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'remote deletion during submit and duplicate invalidations pop no route',
      (tester) async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    final container = await _pump(tester, repository);
    await _scrollSplitUntilVisible(
      tester,
      find.byKey(ValueKey('splitExpense-${expense.id}')),
    );
    await tester.tap(find.byKey(ValueKey('splitExpense-${expense.id}')));
    await tester.pumpAndSettle();
    repository.mutationCompleter = Completer<ListSplitOverview>();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Updated dinner',
    );
    await tester.tap(find.byKey(const Key('saveSplitExpenseButton')));
    await tester.pump();
    final mutationResponse = repository.overview;
    repository.overview = enabledSplitOverview();
    final controller =
        container.read(listSplitControllerProvider(splitListId).notifier);
    final firstReconciliation = controller.reconcile();
    final secondReconciliation = controller.reconcile();

    repository.mutationCompleter!.complete(mutationResponse);
    await tester.pump();
    await Future.wait([firstReconciliation, secondReconciliation]);
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid delete actions show and submit only one confirmation',
      (tester) async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    await _pump(tester, repository);
    final deleteButton =
        find.byKey(ValueKey('deleteSplitExpense-${expense.id}'));
    await _scrollSplitUntilVisible(tester, deleteButton);

    await tester.tap(deleteButton);
    await tester.tap(deleteButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmDeleteSplitExpenseButton')),
        findsOneWidget);

    final confirmation =
        find.byKey(const Key('confirmDeleteSplitExpenseButton'));
    await tester.tap(confirmation);
    await tester.tap(confirmation, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 1);
    expect(repository.overview.expenses, isEmpty);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeListSplitRepository repository, {
  String authenticatedProfileId = splitOwnerProfileId,
  FakeNotificationRepository? notifications,
  bool dark = false,
  double textScale = 1,
  bool settle = true,
}) async {
  final notificationRepository = notifications ?? FakeNotificationRepository();
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(authenticatedProfileId),
        listSplitRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(
          notificationRepository,
        ),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ListSplitScreen(listId: splitListId),
          );
        },
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return container;
}

Future<void> _openCompletedCreateEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('addExpenseButton')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('splitExpenseDescriptionField')),
    'Coffee',
  );
  await tester.enterText(
    find.byKey(const Key('splitExpenseAmountField')),
    '5.00',
  );
}

Future<void> _scrollSplitUntilVisible(
  WidgetTester tester,
  Finder target,
) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.descendant(
      of: find.byKey(const Key('splitOverview')),
      matching: find.byType(Scrollable),
    ),
    maxScrolls: 20,
  );
  await tester.pumpAndSettle();
}
