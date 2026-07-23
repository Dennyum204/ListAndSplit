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

const _formerParticipantId = '30000000-0000-4000-8000-000000000003';

void main() {
  test(
      'owner and member Realtime registries reconcile independently without duplicates',
      () async {
    final ownerRepository = FakeListSplitRepository(initial: _debtOverview());
    final memberRepository = FakeListSplitRepository(
      initial: _debtOverview(isOwner: false),
    );
    final ownerContainer = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(splitOwnerProfileId),
        listSplitRepositoryProvider.overrideWithValue(ownerRepository),
      ],
    );
    final memberContainer = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(splitMemberProfileId),
        listSplitRepositoryProvider.overrideWithValue(memberRepository),
      ],
    );
    addTearDown(ownerContainer.dispose);
    addTearDown(memberContainer.dispose);
    final ownerProvider = listSplitControllerProvider(splitListId);
    final memberProvider = listSplitControllerProvider(splitListId);
    final ownerSubscription = ownerContainer.listen(
      ownerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    final memberSubscription = memberContainer.listen(
      memberProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(ownerSubscription.close);
    addTearDown(memberSubscription.close);
    await Future.wait([
      ownerContainer.read(ownerProvider.notifier).load(),
      memberContainer.read(memberProvider.notifier).load(),
    ]);
    final ownerCallsBefore = ownerRepository.getCalls;
    final memberCallsBefore = memberRepository.getCalls;

    final remoteSettlement = _settlement(
      id: '50000000-0000-4000-8000-000000000001',
      amountMinor: 200,
    );
    ownerRepository
      ..overview = _debtOverview(
        settingsVersion: 2,
        settlementAmountMinor: 200,
      )
      ..settlements.add(remoteSettlement);
    memberRepository
      ..overview = _debtOverview(
        settingsVersion: 2,
        settlementAmountMinor: 200,
        isOwner: false,
      )
      ..settlements.add(remoteSettlement);

    final ownerRegistry = ownerContainer.read(reconciliationRegistryProvider);
    final memberRegistry = memberContainer.read(reconciliationRegistryProvider);
    expect(identical(ownerRegistry, memberRegistry), isFalse);
    await Future.wait([
      ownerRegistry.reconcile(),
      ownerRegistry.reconcile(),
      memberRegistry.reconcile(),
      memberRegistry.reconcile(),
    ]);

    final ownerState = ownerContainer.read(ownerProvider);
    final memberState = memberContainer.read(memberProvider);
    expect(ownerRepository.getCalls, greaterThan(ownerCallsBefore));
    expect(memberRepository.getCalls, greaterThan(memberCallsBefore));
    expect(ownerState.overview.valueOrNull!.isOwner, isTrue);
    expect(memberState.overview.valueOrNull!.isOwner, isFalse);
    expect(
      ownerState.overview.valueOrNull!
          .participantById(splitMemberParticipantId)!
          .balanceMinor,
      -300,
    );
    expect(
      memberState.overview.valueOrNull!
          .participantById(splitMemberParticipantId)!
          .balanceMinor,
      -300,
    );
    expect(ownerState.settlementHistory.valueOrNull!.entries, hasLength(1));
    expect(memberState.settlementHistory.valueOrNull!.entries, hasLength(1));
    expect(
      ownerState.settlementHistory.valueOrNull!.entries.single.id,
      remoteSettlement.id,
    );
    expect(
      memberState.settlementHistory.valueOrNull!.entries.single.id,
      remoteSettlement.id,
    );
    expect(ownerState.message, isNull);
    expect(memberState.message, isNull);
  });

  testWidgets(
      'deterministic suggestion supports partial then full payment recording',
      (tester) async {
    final repository = FakeListSplitRepository(initial: _debtOverview());
    await _pumpSettlement(tester, repository);

    final suggestion = find.byKey(
      const ValueKey(
        'splitSuggestion-$splitMemberParticipantId-'
        '$splitOwnerParticipantId',
      ),
    );
    await _scrollSplitUntilVisible(tester, suggestion);
    expect(find.text('Susana pays Fernando CHF 5.00'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'recordSuggestedPayment-$splitMemberParticipantId-'
          '$splitOwnerParticipantId',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettlementFormDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settlementAmountField')))
          .controller!
          .text,
      '5.00',
    );
    await tester.enterText(
      find.byKey(const Key('settlementAmountField')),
      '2.00',
    );
    await tester.enterText(
      find.byKey(const Key('settlementNoteField')),
      'Cash after lunch',
    );
    await tester.tap(find.byKey(const Key('saveSettlementButton')));
    await tester.pumpAndSettle();

    expect(repository.recordSettlementCalls, 1);
    expect(repository.settlements.single.amountMinor, 200);
    expect(repository.settlements.single.note, 'Cash after lunch');
    expect(
      repository.overview
          .participantById(splitMemberParticipantId)!
          .balanceMinor,
      -300,
    );
    expect(
      repository.overview
          .participantById(splitOwnerParticipantId)!
          .balanceMinor,
      300,
    );
    await _scrollSplitUntilVisible(
      tester,
      find.text('Susana pays Fernando CHF 3.00'),
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
          'recordSuggestedPayment-$splitMemberParticipantId-'
          '$splitOwnerParticipantId',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveSettlementButton')));
    await tester.pumpAndSettle();

    expect(repository.recordSettlementCalls, 2);
    expect(repository.settlements.last.amountMinor, 300);
    expect(
      repository.overview.participants.map((entry) => entry.balanceMinor),
      everyElement(0),
    );
    await _scrollSplitUntilVisible(
      tester,
      find.text('Everyone is settled up.'),
    );
    expect(find.text('Everyone is settled up.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid repeated payment confirmation submits exactly once',
      (tester) async {
    final repository = FakeListSplitRepository(initial: _debtOverview());
    await _pumpSettlement(tester, repository);
    await _openSettlementEditor(tester);
    await tester.enterText(
      find.byKey(const Key('settlementAmountField')),
      '2.50',
    );
    repository.mutationCompleter = Completer<ListSplitOverview>();

    final save = find.byKey(const Key('saveSettlementButton'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();

    expect(repository.recordSettlementCalls, 1);
    expect(repository.settlements, hasLength(1));
    repository.mutationCompleter!.complete(repository.overview);
    await tester.pumpAndSettle();
    expect(find.byType(SettlementFormDialog), findsNothing);
    expect(repository.settlements.single.amountMinor, 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain payment response retries the exact request once',
      (tester) async {
    final repository = FakeListSplitRepository(initial: _debtOverview())
      ..nextMutationFailure =
          const ListSplitFailure(ListSplitFailureCode.transport);
    await _pumpSettlement(tester, repository);
    await _openSettlementEditor(tester);
    await tester.enterText(
      find.byKey(const Key('settlementAmountField')),
      '2.50',
    );
    await tester.enterText(
      find.byKey(const Key('settlementNoteField')),
      'Exact retry',
    );

    await tester.tap(find.byKey(const Key('saveSettlementButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SettlementFormDialog), findsOneWidget);
    expect(repository.recordSettlementCalls, 1);
    expect(repository.settlements, isEmpty);
    expect(
      find.byKey(const Key('settlementRetryMessage')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settlementAmountField')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settlementNoteField')))
          .controller!
          .text,
      'Exact retry',
    );

    await tester.tap(find.byKey(const Key('saveSettlementButton')));
    await tester.pumpAndSettle();

    expect(repository.recordSettlementCalls, 2);
    expect(repository.requestIds, hasLength(2));
    expect(repository.requestIds[0], repository.requestIds[1]);
    expect(repository.settlements, hasLength(1));
    expect(repository.settlements.single.amountMinor, 250);
    expect(repository.settlements.single.note, 'Exact retry');
    expect(find.byType(SettlementFormDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history preserves attribution and historical identities then reverses once',
      (tester) async {
    final repository = FakeListSplitRepository(
      initial: _debtOverview(includeFormerParticipant: true),
    )..settlements.addAll([
        _settlement(
          id: '50000000-0000-4000-8000-000000000001',
          amountMinor: 200,
          note: 'Bank transfer',
        ),
        _settlement(
          id: '50000000-0000-4000-8000-000000000002',
          payerParticipantId: _formerParticipantId,
          recipientParticipantId: splitMemberParticipantId,
          recordedByParticipantId: _formerParticipantId,
          amountMinor: 50,
          canReverse: false,
          createdAt: DateTime.utc(2026, 7, 23, 11),
        ),
      ]);
    final container = await _pumpSettlement(tester, repository);
    final initialState =
        container.read(listSplitControllerProvider(splitListId));
    expect(initialState.overview.valueOrNull!.writable, isTrue);
    expect(initialState.overview.valueOrNull!.settings!.version, 1);
    expect(initialState.settlementHistory.valueOrNull!.entries, hasLength(2));

    final currentEntry = find.byKey(
      const ValueKey(
        'splitSettlement-50000000-0000-4000-8000-000000000001',
      ),
    );
    await _scrollSplitUntilVisible(tester, currentEntry);
    expect(find.text('Susana paid Fernando CHF 2.00'), findsOneWidget);
    expect(find.textContaining('Recorded by Fernando'), findsOneWidget);
    expect(find.text('Bank transfer'), findsOneWidget);
    expect(
      find.text('Former participant paid Susana CHF 0.50'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Recorded by Former participant'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
          'reverseSettlement-50000000-0000-4000-8000-000000000001',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettlementReversalDialog), findsOneWidget);
    final dialogState =
        container.read(listSplitControllerProvider(splitListId));
    expect(dialogState.isMutating, isFalse);
    expect(dialogState.overview.valueOrNull!.writable, isTrue);
    expect(dialogState.overview.valueOrNull!.settings!.version, 1);
    expect(
      dialogState.settlementHistory.valueOrNull!.entries
          .where((entry) => entry.id.endsWith('000000000001')),
      hasLength(1),
    );
    await tester.enterText(
      find.byKey(const Key('settlementReversalReasonField')),
      'Recorded against the wrong person',
    );
    await tester.pump();
    final reasonField = tester.widget<TextField>(
      find.byKey(const Key('settlementReversalReasonField')),
    );
    expect(reasonField.enabled, isTrue);
    expect(reasonField.controller!.text, 'Recorded against the wrong person');
    final confirm = find.byKey(const Key('confirmReverseSettlementButton'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(repository.reverseSettlementCalls, 1);
    expect(repository.settlements.first.isReversed, isTrue);
    expect(
      repository.settlements.first.reversal!.reason,
      'Recorded against the wrong person',
    );
    await _scrollSplitUntilVisible(tester, currentEntry);
    expect(
      find.text(
        'Reversed by Fernando: Recorded against the wrong person',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'reverseSettlement-50000000-0000-4000-8000-000000000001',
        ),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounded history loads the next keyset page without duplicates',
      (tester) async {
    final repository = FakeListSplitRepository(initial: _debtOverview());
    for (var index = 1; index <= 21; index += 1) {
      repository.settlements.add(
        _settlement(
          id: '50000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
          amountMinor: index,
          canReverse: false,
          createdAt: DateTime.utc(2026, 7, 23, 10, index),
        ),
      );
    }
    await _pumpSettlement(tester, repository);

    expect(repository.listSettlementCalls, 1);
    expect(
      find.byKey(
        const ValueKey(
          'splitSettlement-50000000-0000-4000-8000-000000000001',
        ),
      ),
      findsNothing,
    );
    final loadMore = find.byKey(const Key('loadMoreSettlementsButton'));
    await _scrollSplitUntilVisible(tester, loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(repository.listSettlementCalls, 2);
    expect(
      find.byKey(
        const ValueKey(
          'splitSettlement-50000000-0000-4000-8000-000000000001',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'splitSettlement-50000000-0000-4000-8000-000000000021',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loadMoreSettlementsButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duplicate remote invalidations close a stale payment editor once',
      (tester) async {
    final repository = FakeListSplitRepository(initial: _debtOverview());
    final container = await _pumpSettlement(tester, repository);
    await _openSettlementEditor(tester);
    await tester.enterText(
      find.byKey(const Key('settlementNoteField')),
      'Unsaved local note',
    );

    repository.overview = _debtOverview(settingsVersion: 2);
    final controller =
        container.read(listSplitControllerProvider(splitListId).notifier);
    await Future.wait([controller.reconcile(), controller.reconcile()]);
    await tester.pumpAndSettle();

    expect(find.byType(SettlementFormDialog), findsNothing);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(repository.recordSettlementCalls, 0);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'remote reversal closes an active reversal editor without resubmission',
      (tester) async {
    final settlement = _settlement(
      id: '50000000-0000-4000-8000-000000000001',
      amountMinor: 200,
    );
    final repository = FakeListSplitRepository(initial: _debtOverview())
      ..settlements.add(settlement);
    final container = await _pumpSettlement(tester, repository);
    final reverse = find.byKey(
      const ValueKey(
        'reverseSettlement-50000000-0000-4000-8000-000000000001',
      ),
    );
    await _scrollSplitUntilVisible(tester, reverse);
    await tester.tap(reverse);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settlementReversalReasonField')),
      'Unsaved reason',
    );

    repository
      ..overview = _debtOverview(settingsVersion: 2)
      ..settlements[0] = _settlement(
        id: settlement.id,
        amountMinor: settlement.amountMinor,
        canReverse: false,
        reversal: ListSplitSettlementReversal(
          reversedByParticipantId: splitMemberParticipantId,
          reason: 'Reversed remotely',
          createdAt: DateTime.utc(2026, 7, 23, 12, 1),
        ),
      );
    final controller =
        container.read(listSplitControllerProvider(splitListId).notifier);
    await Future.wait([controller.reconcile(), controller.reconcile()]);
    await tester.pumpAndSettle();

    expect(find.byType(SettlementReversalDialog), findsNothing);
    expect(repository.reverseSettlementCalls, 0);
    expect(find.byType(ListSplitScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settlement controls remain accessible in dark mode at 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    final repository = FakeListSplitRepository(initial: _debtOverview())
      ..settlements.add(
        _settlement(
          id: '50000000-0000-4000-8000-000000000001',
          amountMinor: 200,
          canReverse: false,
        ),
      );
    await _pumpSettlement(
      tester,
      repository,
      dark: true,
      textScale: 2,
    );

    final record = find.byKey(
      const ValueKey(
        'recordSuggestedPayment-$splitMemberParticipantId-'
        '$splitOwnerParticipantId',
      ),
    );
    await _scrollSplitUntilVisible(tester, record);
    expect(find.bySemanticsLabel('Record payment'), findsWidgets);
    await tester.tap(record);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('saveSettlementButton')),
    );
    expect(find.byKey(const Key('settlementAmountField')), findsOneWidget);
    expect(find.byKey(const Key('settlementNoteField')), findsOneWidget);
    expect(find.byKey(const Key('saveSettlementButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Future<ProviderContainer> _pumpSettlement(
  WidgetTester tester,
  FakeListSplitRepository repository, {
  bool dark = false,
  double textScale = 1,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(splitOwnerProfileId),
        listSplitRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
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
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openSettlementEditor(WidgetTester tester) async {
  final record = find.byKey(
    const ValueKey(
      'recordSuggestedPayment-$splitMemberParticipantId-'
      '$splitOwnerParticipantId',
    ),
  );
  await _scrollSplitUntilVisible(tester, record);
  await tester.tap(record);
  await tester.pumpAndSettle();
  expect(find.byType(SettlementFormDialog), findsOneWidget);
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
    maxScrolls: 30,
  );
  await tester.pumpAndSettle();
}

ListSplitOverview _debtOverview({
  int settingsVersion = 1,
  bool includeFormerParticipant = false,
  bool isOwner = true,
  int settlementAmountMinor = 0,
}) {
  final now = DateTime.utc(2026, 7, 23, 10);
  return ListSplitOverview(
    listId: splitListId,
    listTitle: 'Weekend shop',
    listStatus: SplitListStatus.active,
    listVersion: 3,
    isOwner: isOwner,
    enabled: true,
    writable: true,
    settings: ListSplitSettings(
      currency: SplitCurrency.chf,
      version: settingsVersion,
      createdAt: now,
      updatedAt: now.add(Duration(seconds: settingsVersion - 1)),
    ),
    participants: [
      ListSplitParticipant(
        id: splitOwnerParticipantId,
        profileId: splitOwnerProfileId,
        username: 'fernando',
        displayName: 'Fernando',
        isAnonymized: false,
        isCurrent: true,
        paidMinor: 1000,
        owedMinor: 500,
        settlementReceivedMinor: settlementAmountMinor,
        balanceMinor: 500 - settlementAmountMinor,
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
        settlementPaidMinor: settlementAmountMinor,
        balanceMinor: -500 + settlementAmountMinor,
      ),
      if (includeFormerParticipant)
        const ListSplitParticipant(
          id: _formerParticipantId,
          profileId: null,
          username: null,
          displayName: null,
          isAnonymized: true,
          isCurrent: false,
          paidMinor: 0,
          owedMinor: 0,
          balanceMinor: 0,
        ),
    ],
    expenses: [splitExpense(amountMinor: 1000)],
    suggestions: settlementAmountMinor == 500
        ? const []
        : [
            ListSettlementSuggestion(
              payerParticipantId: splitMemberParticipantId,
              recipientParticipantId: splitOwnerParticipantId,
              amountMinor: 500 - settlementAmountMinor,
            ),
          ],
  );
}

ListSplitSettlement _settlement({
  required String id,
  String payerParticipantId = splitMemberParticipantId,
  String recipientParticipantId = splitOwnerParticipantId,
  String recordedByParticipantId = splitOwnerParticipantId,
  required int amountMinor,
  String? note,
  bool canReverse = true,
  DateTime? createdAt,
  ListSplitSettlementReversal? reversal,
}) {
  return ListSplitSettlement(
    id: id,
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    recordedByParticipantId: recordedByParticipantId,
    amountMinor: amountMinor,
    note: note,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 23, 12),
    reversal: reversal,
    canReverse: canReverse,
  );
}
