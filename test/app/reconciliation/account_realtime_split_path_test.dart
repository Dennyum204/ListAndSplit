import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_coordinator.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/bounded_realtime_websocket_transport.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/realtime/supabase_account_realtime_gateway.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/presentation/list_split_providers.dart';
import 'package:list_and_split/features/split/presentation/list_split_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_list_split_repository.dart';
import '../../helpers/fakes.dart';
import '../../helpers/scripted_realtime_websocket.dart';

void main() {
  testWidgets(
      'production invalidation path reloads mounted Split and closes stale editor',
      (tester) async {
    final originalExpense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: _initialOverview(originalExpense),
    );
    final container = await _pumpSplit(tester, repository);

    final connector = ScriptedRealtimeConnector();
    final transport = BoundedRealtimeWebSocketTransport(
      connector: connector.connect,
    );
    final client = SupabaseClient(
      'https://example.invalid',
      'publishable-test-value',
      realtimeClientOptions: RealtimeClientOptions(
        transport: transport.connect,
      ),
    );
    final diagnostics = <AccountRealtimeDiagnostic>[];
    final coordinator = AccountReconciliationCoordinator(
      SupabaseAccountRealtimeGateway(client),
      container.read(reconciliationRegistryProvider),
      closedChannelRetryDelay: const Duration(days: 1),
      diagnosticSink: diagnostics.add,
    );
    var cleanedUp = false;
    Future<void> cleanUpRealtime() async {
      if (cleanedUp) return;
      cleanedUp = true;
      await coordinator.dispose();
      client.auth.dispose();
    }

    addTearDown(cleanUpRealtime);

    coordinator.setAccount(splitOwnerProfileId);
    await _pumpUntil(tester, () => connector.channels.length == 1);
    connector.channels.single.completeHandshake();
    await _pumpUntil(
      tester,
      () => diagnostics.any(
        (entry) => entry.update.status == AccountRealtimeStatus.subscribed,
      ),
    );
    await tester.pumpAndSettle();

    await _scrollSplitUntilVisible(
      tester,
      find.byKey(ValueKey('splitExpense-${originalExpense.id}')),
    );
    await tester.tap(
      find.byKey(ValueKey('splitExpense-${originalExpense.id}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('splitExpenseDescriptionField')),
      'Unsaved local value',
    );
    expect(find.byType(ExpenseFormDialog), findsOneWidget);

    final remoteExpense = splitExpense(
      id: '40000000-0000-4000-8000-000000000002',
      description: 'Remote lodging',
      amountMinor: 8000,
    );
    final remoteSettlement = ListSplitSettlement(
      id: '50000000-0000-4000-8000-000000000001',
      payerParticipantId: splitMemberParticipantId,
      recipientParticipantId: splitOwnerParticipantId,
      recordedByParticipantId: splitOwnerParticipantId,
      amountMinor: 500,
      note: 'Remote cash',
      createdAt: DateTime.utc(2026, 7, 24, 12),
      reversal: null,
      canReverse: true,
    );
    repository.overview = _remoteOverview(remoteExpense);
    repository.settlements
      ..clear()
      ..add(remoteSettlement);

    final getCallsBeforeInvalidation = repository.getCalls;
    connector.channels.single.emitAccountInvalidation(splitOwnerProfileId);
    await _pumpUntil(
      tester,
      () => repository.getCalls == getCallsBeforeInvalidation + 1,
    );
    await tester.pumpAndSettle();

    final state = container.read(listSplitControllerProvider(splitListId));
    final overview = state.overview.requireValue;
    final history = state.settlementHistory.requireValue;
    expect(repository.getCalls, getCallsBeforeInvalidation + 1);
    expect(overview.expenses.single.id, remoteExpense.id);
    expect(overview.expenses.single.description, 'Remote lodging');
    expect(
      overview.participantById(splitOwnerParticipantId)!.balanceMinor,
      3500,
    );
    expect(
      overview.participantById(splitMemberParticipantId)!.balanceMinor,
      -3500,
    );
    expect(overview.suggestions.single.amountMinor, 3500);
    expect(history.entries.single.id, remoteSettlement.id);
    expect(history.entries.single.note, 'Remote cash');
    expect(state.message, isNull);
    expect(find.byType(ExpenseFormDialog), findsNothing);
    expect(find.byKey(const Key('saveSplitExpenseButton')), findsNothing);
    expect(find.text('Unsaved local value'), findsNothing);
    expect(tester.takeException(), isNull);

    final cleanup = cleanUpRealtime();
    await tester.pump();
    await cleanup;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<ProviderContainer> _pumpSplit(
  WidgetTester tester,
  FakeListSplitRepository repository,
) async {
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
          return const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ListSplitScreen(listId: splitListId),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await tester.pump();
  }
  fail('The expected mounted Realtime state was not reached.');
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

ListSplitOverview _initialOverview(ListSplitExpense expense) {
  final createdAt = DateTime.utc(2026, 7, 23, 9);
  return ListSplitOverview(
    listId: splitListId,
    listTitle: 'Weekend shop',
    listStatus: SplitListStatus.active,
    listVersion: 3,
    isOwner: true,
    enabled: true,
    writable: true,
    settings: ListSplitSettings(
      currency: SplitCurrency.chf,
      version: 1,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    participants: const [
      ListSplitParticipant(
        id: splitOwnerParticipantId,
        profileId: splitOwnerProfileId,
        username: 'fernando',
        displayName: 'Fernando',
        isAnonymized: false,
        isCurrent: true,
        paidMinor: 6000,
        owedMinor: 3000,
        balanceMinor: 3000,
      ),
      ListSplitParticipant(
        id: splitMemberParticipantId,
        profileId: splitMemberProfileId,
        username: 'susana',
        displayName: 'Susana',
        isAnonymized: false,
        isCurrent: true,
        paidMinor: 0,
        owedMinor: 3000,
        balanceMinor: -3000,
      ),
    ],
    expenses: [expense],
    suggestions: const [
      ListSettlementSuggestion(
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        amountMinor: 3000,
      ),
    ],
  );
}

ListSplitOverview _remoteOverview(ListSplitExpense expense) {
  final createdAt = DateTime.utc(2026, 7, 23, 9);
  return ListSplitOverview(
    listId: splitListId,
    listTitle: 'Weekend shop',
    listStatus: SplitListStatus.active,
    listVersion: 4,
    isOwner: true,
    enabled: true,
    writable: true,
    settings: ListSplitSettings(
      currency: SplitCurrency.chf,
      version: 3,
      createdAt: createdAt,
      updatedAt: DateTime.utc(2026, 7, 24, 12),
    ),
    participants: const [
      ListSplitParticipant(
        id: splitOwnerParticipantId,
        profileId: splitOwnerProfileId,
        username: 'fernando',
        displayName: 'Fernando',
        isAnonymized: false,
        isCurrent: true,
        paidMinor: 8000,
        owedMinor: 4000,
        settlementReceivedMinor: 500,
        balanceMinor: 3500,
      ),
      ListSplitParticipant(
        id: splitMemberParticipantId,
        profileId: splitMemberProfileId,
        username: 'susana',
        displayName: 'Susana',
        isAnonymized: false,
        isCurrent: true,
        paidMinor: 0,
        owedMinor: 4000,
        settlementPaidMinor: 500,
        balanceMinor: -3500,
      ),
    ],
    expenses: [expense],
    suggestions: const [
      ListSettlementSuggestion(
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        amountMinor: 3500,
      ),
    ],
  );
}
