import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';
import 'package:list_and_split/features/split/presentation/list_split_controller.dart';
import 'package:list_and_split/features/split/presentation/list_split_providers.dart';

import '../../helpers/fake_list_split_repository.dart';

void main() {
  test('only an active-list owner can enable Split', () async {
    final ownerRepository = FakeListSplitRepository(
      initial: disabledSplitOverview(),
    );
    final owner = _controller(ownerRepository);
    await owner.load();

    expect(
      await owner.enable(SplitCurrency.eur),
      ListSplitMutationOutcome.succeeded,
    );
    expect(ownerRepository.enableCalls, 1);
    expect(owner.state.overview.asData?.value.currency, SplitCurrency.eur);

    final memberRepository = FakeListSplitRepository(
      initial: disabledSplitOverview(isOwner: false),
    );
    final member = _controller(memberRepository);
    await member.load();
    expect(
      await member.enable(SplitCurrency.chf),
      ListSplitMutationOutcome.invalid,
    );
    expect(memberRepository.enableCalls, 0);

    owner.dispose();
    member.dispose();
  });

  test('matches the required combined CHF balance examples exactly', () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();

    await controller.createExpense(
      description: 'Dinner',
      amountMinor: 6000,
      payerParticipantId: splitOwnerParticipantId,
      beneficiaryParticipantIds: const [
        splitOwnerParticipantId,
        splitMemberParticipantId,
      ],
      requestId: '50000000-0000-4000-8000-000000000001',
    );
    final first = controller.state.overview.asData!.value;
    expect(first.participantById(splitOwnerParticipantId)?.balanceMinor, 3000);
    expect(
        first.participantById(splitMemberParticipantId)?.balanceMinor, -3000);

    await controller.createExpense(
      description: 'Tickets',
      amountMinor: 2000,
      payerParticipantId: splitMemberParticipantId,
      beneficiaryParticipantIds: const [splitOwnerParticipantId],
      requestId: '50000000-0000-4000-8000-000000000002',
    );
    final second = controller.state.overview.asData!.value;
    expect(second.participantById(splitOwnerParticipantId)?.balanceMinor, 1000);
    expect(
        second.participantById(splitMemberParticipantId)?.balanceMinor, -1000);
    expect(
      second.expenses.last.beneficiaryParticipantIds,
      isNot(contains(splitMemberParticipantId)),
    );

    controller.dispose();
  });

  test('keeps non-even integer remainder allocation deterministic', () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();

    await controller.createExpense(
      description: 'Coffee',
      amountMinor: 1001,
      payerParticipantId: splitOwnerParticipantId,
      beneficiaryParticipantIds: const [
        splitOwnerParticipantId,
        splitMemberParticipantId,
      ],
      requestId: '50000000-0000-4000-8000-000000000001',
    );

    expect(
      controller.state.overview.asData!.value.expenses.single.shares
          .map((share) => share.amountMinor),
      [501, 500],
    );
    controller.dispose();
  });

  test('creates exact custom shares and recalculates balances immediately',
      () async {
    const pedroParticipantId = '30000000-0000-4000-8000-000000000003';
    const pedroProfileId = '20000000-0000-4000-8000-000000000003';
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(
        participants: const [
          ...[
            ListSplitParticipant(
              id: splitOwnerParticipantId,
              profileId: splitOwnerProfileId,
              username: 'fernando',
              displayName: 'Fernando',
              isAnonymized: false,
              isCurrent: true,
              paidMinor: 0,
              owedMinor: 0,
              balanceMinor: 0,
            ),
            ListSplitParticipant(
              id: splitMemberParticipantId,
              profileId: splitMemberProfileId,
              username: 'susana',
              displayName: 'Susana',
              isAnonymized: false,
              isCurrent: true,
              paidMinor: 0,
              owedMinor: 0,
              balanceMinor: 0,
            ),
          ],
          ListSplitParticipant(
            id: pedroParticipantId,
            profileId: pedroProfileId,
            username: 'pedro',
            displayName: 'Pedro',
            isAnonymized: false,
            isCurrent: true,
            paidMinor: 0,
            owedMinor: 0,
            balanceMinor: 0,
          ),
        ],
      ),
    );
    final controller = _controller(repository);
    repository.settlements.add(
      ListSplitSettlement(
        id: '50000000-0000-4000-8000-000000000099',
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        recordedByParticipantId: splitOwnerParticipantId,
        amountMinor: 1,
        note: 'Earlier correction',
        createdAt: DateTime.utc(2026, 7, 22, 8),
        reversal: ListSplitSettlementReversal(
          reversedByParticipantId: splitOwnerParticipantId,
          reason: 'Already corrected',
          createdAt: DateTime.utc(2026, 7, 22, 8, 1),
        ),
        canReverse: false,
      ),
    );
    await controller.load();

    expect(
      await controller.createExpense(
        description: 'Custom dinner',
        amountMinor: 3000,
        payerParticipantId: splitOwnerParticipantId,
        beneficiaryParticipantIds: const [
          splitOwnerParticipantId,
          splitMemberParticipantId,
          pedroParticipantId,
        ],
        customShares: const [
          ListExpenseShare(
            participantId: splitOwnerParticipantId,
            amountMinor: 1500,
          ),
          ListExpenseShare(
            participantId: splitMemberParticipantId,
            amountMinor: 1000,
          ),
          ListExpenseShare(
            participantId: pedroParticipantId,
            amountMinor: 500,
          ),
        ],
        requestId: '50000000-0000-4000-8000-000000000010',
      ),
      ListSplitMutationOutcome.succeeded,
    );

    final result = controller.state.overview.asData!.value;
    expect(
      result.participantById(splitOwnerParticipantId)?.balanceMinor,
      1500,
    );
    expect(
      result.participantById(splitMemberParticipantId)?.balanceMinor,
      -1000,
    );
    expect(result.participantById(pedroParticipantId)?.balanceMinor, -500);
    expect(
      result.suggestions
          .map(
            (entry) => (
              entry.payerParticipantId,
              entry.recipientParticipantId,
              entry.amountMinor,
            ),
          )
          .toList(),
      const [
        (
          splitMemberParticipantId,
          splitOwnerParticipantId,
          1000,
        ),
        (
          pedroParticipantId,
          splitOwnerParticipantId,
          500,
        ),
      ],
    );
    expect(
      result.expenses.single.usesCanonicalEqualAllocation,
      isFalse,
    );
    expect(
      controller.state.settlementHistory.asData!.value.entries.single.id,
      '50000000-0000-4000-8000-000000000099',
    );
    controller.dispose();
  });

  test('rejects malformed custom allocations before repository mutation',
      () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();

    final invalidAllocations = <List<ListExpenseShare>>[
      const [
        ListExpenseShare(
          participantId: splitOwnerParticipantId,
          amountMinor: 499,
        ),
      ],
      const [
        ListExpenseShare(
          participantId: splitOwnerParticipantId,
          amountMinor: 501,
        ),
      ],
      const [
        ListExpenseShare(
          participantId: splitOwnerParticipantId,
          amountMinor: 0,
        ),
      ],
      const [
        ListExpenseShare(
          participantId: splitOwnerParticipantId,
          amountMinor: 250,
        ),
        ListExpenseShare(
          participantId: splitOwnerParticipantId,
          amountMinor: 250,
        ),
      ],
    ];
    for (final shares in invalidAllocations) {
      expect(
        await controller.createExpense(
          description: 'Invalid custom',
          amountMinor: 500,
          payerParticipantId: splitOwnerParticipantId,
          beneficiaryParticipantIds: const [splitOwnerParticipantId],
          customShares: shares,
          requestId: '50000000-0000-4000-8000-000000000011',
        ),
        ListSplitMutationOutcome.invalid,
      );
    }

    expect(repository.createCalls, 0);
    expect(controller.state.overview.asData!.value.expenses, isEmpty);
    controller.dispose();
  });

  test('retains removed identities only in their existing expense roles',
      () async {
    const formerPayer = '30000000-0000-4000-8000-000000000003';
    const formerBeneficiary = '30000000-0000-4000-8000-000000000004';
    final expense = splitExpense(
      payerParticipantId: formerPayer,
      beneficiaryParticipantIds: const [
        splitOwnerParticipantId,
        formerBeneficiary,
      ],
    );
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(
        participants: [
          ...splitParticipants(),
          const ListSplitParticipant(
            id: formerPayer,
            profileId: null,
            username: null,
            displayName: null,
            isAnonymized: true,
            isCurrent: false,
            paidMinor: 6000,
            owedMinor: 0,
            balanceMinor: 6000,
          ),
          const ListSplitParticipant(
            id: formerBeneficiary,
            profileId: null,
            username: null,
            displayName: null,
            isAnonymized: true,
            isCurrent: false,
            paidMinor: 0,
            owedMinor: 3000,
            balanceMinor: -3000,
          ),
        ],
        expenses: [expense],
      ),
    );
    final controller = _controller(repository);
    await controller.load();

    expect(
      await controller.updateExpense(
        expense,
        description: expense.description,
        amountMinor: expense.amountMinor,
        payerParticipantId: formerBeneficiary,
        beneficiaryParticipantIds: expense.beneficiaryParticipantIds,
      ),
      ListSplitMutationOutcome.invalid,
    );
    expect(
      await controller.updateExpense(
        expense,
        description: expense.description,
        amountMinor: expense.amountMinor,
        payerParticipantId: formerPayer,
        beneficiaryParticipantIds: const [
          splitOwnerParticipantId,
          formerBeneficiary,
          formerPayer,
        ],
      ),
      ListSplitMutationOutcome.invalid,
    );
    expect(repository.updateCalls, 0);

    expect(
      await controller.updateExpense(
        expense,
        description: 'Updated dinner',
        amountMinor: expense.amountMinor,
        payerParticipantId: formerPayer,
        beneficiaryParticipantIds: expense.beneficiaryParticipantIds,
        customShares: const [
          ListExpenseShare(
            participantId: splitOwnerParticipantId,
            amountMinor: 2000,
          ),
          ListExpenseShare(
            participantId: formerBeneficiary,
            amountMinor: 4000,
          ),
        ],
      ),
      ListSplitMutationOutcome.succeeded,
    );
    expect(repository.updateCalls, 1);
    expect(
      repository.overview.expenses.single.shares
          .firstWhere(
            (share) => share.participantId == formerBeneficiary,
          )
          .amountMinor,
      4000,
    );

    controller.dispose();
  });

  test('one create intent reuses its request id while a new intent does not',
      () async {
    var generated = 0;
    final repository = FakeListSplitRepository();
    final controller = ListSplitController(
      repository,
      splitListId,
      authenticatedProfileId: splitOwnerProfileId,
      requestIdGenerator: () =>
          '50000000-0000-4000-8000-${(++generated).toString().padLeft(12, '0')}',
    );
    await controller.load();
    final firstIntentId = controller.newExpenseRequestId();
    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.invalid);

    expect(
      await controller.createExpense(
        description: 'Coffee',
        amountMinor: 500,
        payerParticipantId: splitOwnerParticipantId,
        beneficiaryParticipantIds: const [splitOwnerParticipantId],
        requestId: firstIntentId,
      ),
      ListSplitMutationOutcome.invalid,
    );
    await controller.createExpense(
      description: 'Coffee',
      amountMinor: 500,
      payerParticipantId: splitOwnerParticipantId,
      beneficiaryParticipantIds: const [splitOwnerParticipantId],
      requestId: firstIntentId,
    );
    final nextIntentId = controller.newExpenseRequestId();

    expect(repository.requestIds, [firstIntentId, firstIntentId]);
    expect(nextIntentId, isNot(firstIntentId));
    controller.dispose();
  });

  test('records a partial payment, recalculates, and reverses once', () async {
    final repository = FakeListSplitRepository(
      initial: _overviewWithDebt(),
    );
    final controller = _controller(repository);
    await controller.load();

    expect(
      await controller.recordSettlement(
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        amountMinor: 1000,
        note: 'Cash',
        requestId: '50000000-0000-4000-8000-000000000010',
      ),
      ListSplitMutationOutcome.succeeded,
    );
    final paid = controller.state.overview.asData!.value;
    expect(
      paid.participantById(splitOwnerParticipantId)?.balanceMinor,
      2000,
    );
    expect(
      paid.participantById(splitMemberParticipantId)?.balanceMinor,
      -2000,
    );
    expect(paid.suggestions.single.amountMinor, 2000);
    expect(
      controller.state.settlementHistory.asData!.value.entries.single.note,
      'Cash',
    );

    final settlement =
        controller.state.settlementHistory.asData!.value.entries.single;
    expect(
      await controller.reverseSettlement(
        settlement,
        reason: 'Wrong cash amount',
        requestId: '50000000-0000-4000-8000-000000000011',
      ),
      ListSplitMutationOutcome.succeeded,
    );
    final restored = controller.state.overview.asData!.value;
    expect(
      restored.participantById(splitOwnerParticipantId)?.balanceMinor,
      3000,
    );
    expect(
      restored.participantById(splitMemberParticipantId)?.balanceMinor,
      -3000,
    );
    final reversed =
        controller.state.settlementHistory.asData!.value.entries.single;
    expect(reversed.reversal?.reason, 'Wrong cash amount');
    expect(
      await controller.reverseSettlement(
        reversed,
        reason: 'Again',
        requestId: '50000000-0000-4000-8000-000000000012',
      ),
      ListSplitMutationOutcome.invalid,
    );
    expect(repository.reverseSettlementCalls, 1);
    controller.dispose();
  });

  test('stale reversal authority refreshes without discarding list access',
      () async {
    final repository = FakeListSplitRepository(initial: _overviewWithDebt())
      ..settlements.add(
        _settlement(
          index: 0,
          createdAt: DateTime.utc(2026, 7, 23, 12),
        ),
      );
    final controller = _controller(repository);
    await controller.load();
    final staleSettlement =
        controller.state.settlementHistory.asData!.value.entries.single;
    repository.settlements[0] = ListSplitSettlement(
      id: staleSettlement.id,
      payerParticipantId: staleSettlement.payerParticipantId,
      recipientParticipantId: staleSettlement.recipientParticipantId,
      recordedByParticipantId: staleSettlement.recordedByParticipantId,
      amountMinor: staleSettlement.amountMinor,
      note: staleSettlement.note,
      createdAt: staleSettlement.createdAt,
      reversal: null,
      canReverse: false,
    );
    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.stale);

    expect(
      await controller.reverseSettlement(
        staleSettlement,
        reason: 'No longer authorized',
        requestId: '50000000-0000-4000-8000-000000000013',
      ),
      ListSplitMutationOutcome.stale,
    );
    expect(controller.state.overview.hasValue, isTrue);
    expect(
      controller
          .state.settlementHistory.asData!.value.entries.single.canReverse,
      isFalse,
    );
    expect(controller.state.message, ListSplitMessage.staleRefreshed);
    controller.dispose();
  });

  test('validates settlement direction, maximum, and overlapping saves',
      () async {
    final repository = FakeListSplitRepository(
      initial: _overviewWithDebt(),
    );
    final controller = _controller(repository);
    await controller.load();

    for (final invalid in [
      (
        payer: splitOwnerParticipantId,
        recipient: splitMemberParticipantId,
        amount: 100,
      ),
      (
        payer: splitMemberParticipantId,
        recipient: splitMemberParticipantId,
        amount: 100,
      ),
      (
        payer: splitMemberParticipantId,
        recipient: splitOwnerParticipantId,
        amount: 3001,
      ),
    ]) {
      expect(
        await controller.recordSettlement(
          payerParticipantId: invalid.payer,
          recipientParticipantId: invalid.recipient,
          amountMinor: invalid.amount,
          note: null,
          requestId: '50000000-0000-4000-8000-000000000020',
        ),
        ListSplitMutationOutcome.invalid,
      );
    }
    expect(repository.recordSettlementCalls, 0);

    repository.mutationCompleter = Completer<ListSplitOverview>();
    final first = controller.recordSettlement(
      payerParticipantId: splitMemberParticipantId,
      recipientParticipantId: splitOwnerParticipantId,
      amountMinor: 3000,
      note: null,
      requestId: '50000000-0000-4000-8000-000000000021',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      await controller.recordSettlement(
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        amountMinor: 3000,
        note: null,
        requestId: '50000000-0000-4000-8000-000000000021',
      ),
      ListSplitMutationOutcome.failed,
    );
    repository.mutationCompleter!.complete(repository.overview);
    expect(await first, ListSplitMutationOutcome.succeeded);
    expect(repository.recordSettlementCalls, 1);
    controller.dispose();
  });

  test('allows historical settlement endpoints and locks currency forever',
      () async {
    const formerDebtorId = '30000000-0000-4000-8000-000000000003';
    const formerCreditorId = '30000000-0000-4000-8000-000000000004';
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(
        participants: const [
          ...[
            ListSplitParticipant(
              id: splitOwnerParticipantId,
              profileId: splitOwnerProfileId,
              username: 'fernando',
              displayName: 'Fernando',
              isAnonymized: false,
              isCurrent: true,
              paidMinor: 0,
              owedMinor: 0,
              balanceMinor: 0,
            ),
          ],
          ListSplitParticipant(
            id: formerDebtorId,
            profileId: null,
            username: null,
            displayName: null,
            isAnonymized: true,
            isCurrent: false,
            paidMinor: 0,
            owedMinor: 2000,
            balanceMinor: -2000,
          ),
          ListSplitParticipant(
            id: formerCreditorId,
            profileId: null,
            username: null,
            displayName: null,
            isAnonymized: true,
            isCurrent: false,
            paidMinor: 2000,
            owedMinor: 0,
            balanceMinor: 2000,
          ),
        ],
      ).copyWithSuggestions(
        const [
          ListSettlementSuggestion(
            payerParticipantId: formerDebtorId,
            recipientParticipantId: formerCreditorId,
            amountMinor: 2000,
          ),
        ],
      ),
    );
    final controller = _controller(repository);
    await controller.load();

    expect(
      await controller.recordSettlement(
        payerParticipantId: formerDebtorId,
        recipientParticipantId: formerCreditorId,
        amountMinor: 500,
        note: 'Historical balance',
        requestId: '50000000-0000-4000-8000-000000000030',
      ),
      ListSplitMutationOutcome.succeeded,
    );
    final recorded =
        controller.state.settlementHistory.asData!.value.entries.single;
    expect(recorded.payerParticipantId, formerDebtorId);
    expect(recorded.recipientParticipantId, formerCreditorId);

    expect(
      await controller.reverseSettlement(
        recorded,
        reason: 'Correct the record',
        requestId: '50000000-0000-4000-8000-000000000031',
      ),
      ListSplitMutationOutcome.succeeded,
    );
    expect(
      controller
          .state.settlementHistory.asData!.value.entries.single.isReversed,
      isTrue,
    );
    expect(
      await controller.changeCurrency(SplitCurrency.eur),
      ListSplitMutationOutcome.invalid,
    );
    expect(repository.changeCurrencyCalls, 0);
    controller.dispose();
  });

  test('loads bounded settlement history with deterministic keyset pagination',
      () async {
    final repository = FakeListSplitRepository(initial: _overviewWithDebt());
    for (var index = 0; index < 21; index += 1) {
      repository.settlements.add(
        _settlement(
          index: index,
          createdAt: DateTime.utc(2026, 7, 23, 10).add(
            Duration(minutes: index),
          ),
        ),
      );
    }
    final controller = _controller(repository);

    await controller.load();
    final firstPage = controller.state.settlementHistory.asData!.value;
    expect(firstPage.entries, hasLength(splitSettlementHistoryPageSize));
    expect(firstPage.nextCursor, isNotNull);
    expect(firstPage.entries.first.id, repository.settlements.last.id);

    await controller.loadMoreSettlements();
    final completeHistory = controller.state.settlementHistory.asData!.value;
    expect(completeHistory.entries, hasLength(21));
    expect(completeHistory.nextCursor, isNull);
    expect(
      completeHistory.entries.map((entry) => entry.id).toSet(),
      hasLength(21),
    );
    expect(repository.listSettlementCalls, 2);
    controller.dispose();
  });

  test('late pagination cannot overwrite a Realtime history reconciliation',
      () async {
    final repository = FakeListSplitRepository(initial: _overviewWithDebt());
    for (var index = 0; index < 21; index += 1) {
      repository.settlements.add(
        _settlement(
          index: index,
          createdAt: DateTime.utc(2026, 7, 23, 10).add(
            Duration(minutes: index),
          ),
        ),
      );
    }
    final controller = _controller(repository);
    await controller.load();
    final paginationResult = Completer<ListSplitSettlementPage>();
    final reconciledEntry = _settlement(
      index: 98,
      createdAt: DateTime.utc(2026, 7, 23, 12),
    );
    repository.listSettlementsOverride = (listId, pageSize, cursor) {
      if (cursor != null) return paginationResult.future;
      return Future.value(
        ListSplitSettlementPage(
          listId: listId,
          currency: SplitCurrency.chf,
          entries: [reconciledEntry],
          nextCursor: null,
        ),
      );
    };

    final pagination = controller.loadMoreSettlements();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isLoadingMoreSettlements, isTrue);

    await controller.reconcile();
    expect(
      controller.state.settlementHistory.asData!.value.entries.single.id,
      reconciledEntry.id,
    );

    paginationResult.complete(
      ListSplitSettlementPage(
        listId: splitListId,
        currency: SplitCurrency.chf,
        entries: [repository.settlements.first],
        nextCursor: null,
      ),
    );
    await pagination;

    expect(
      controller.state.settlementHistory.asData!.value.entries.single.id,
      reconciledEntry.id,
    );
    expect(controller.state.isLoadingMoreSettlements, isFalse);
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('history rejects foreign actors and propagates lost access', () async {
    final repository = FakeListSplitRepository(initial: _overviewWithDebt());
    repository.listSettlementsOverride =
        (listId, pageSize, cursor) => Future.value(
              ListSplitSettlementPage(
                listId: listId,
                currency: SplitCurrency.chf,
                entries: [
                  ListSplitSettlement(
                    id: '50000000-0000-4000-8000-000000000099',
                    payerParticipantId: '30000000-0000-4000-8000-000000000099',
                    recipientParticipantId: splitOwnerParticipantId,
                    recordedByParticipantId: splitOwnerParticipantId,
                    amountMinor: 100,
                    note: null,
                    createdAt: DateTime.utc(2026, 7, 23, 12),
                    reversal: null,
                    canReverse: false,
                  ),
                ],
                nextCursor: null,
              ),
            );
    final controller = _controller(repository);

    await controller.load();
    expect(controller.state.overview.hasValue, isTrue);
    expect(controller.state.settlementHistory.hasError, isTrue);

    repository.listSettlementsOverride =
        (listId, pageSize, cursor) => Future.error(
              const ListSplitFailure(ListSplitFailureCode.unavailable),
            );
    await controller.reconcile();
    expect(controller.state.overview.hasError, isTrue);
    expect(controller.state.overview.valueOrNull, isNull);
    expect(controller.state.message, ListSplitMessage.unavailable);
    controller.dispose();
  });

  test('transport failure preserves only a still-valid cached history page',
      () async {
    final repository = FakeListSplitRepository(initial: _overviewWithDebt())
      ..settlements.add(
        _settlement(
          index: 0,
          createdAt: DateTime.utc(2026, 7, 23, 12),
        ),
      );
    final controller = _controller(repository);
    await controller.load();
    final cached =
        controller.state.settlementHistory.asData!.value.entries.single;

    repository.listSettlementsOverride =
        (listId, pageSize, cursor) => Future.error(
              const ListSplitFailure(ListSplitFailureCode.transport),
            );
    await controller.reconcile();

    expect(controller.state.overview.hasValue, isTrue);
    expect(
      controller.state.settlementHistory.asData!.value.entries.single.id,
      cached.id,
    );
    expect(controller.state.message, isNull);
    controller.dispose();
  });

  test('manual refresh coalesces behind a mutation and remains available after',
      () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();
    repository.mutationCompleter = Completer<ListSplitOverview>();

    final mutation = controller.createExpense(
      description: 'Coffee',
      amountMinor: 500,
      payerParticipantId: splitOwnerParticipantId,
      beneficiaryParticipantIds: const [splitOwnerParticipantId],
      requestId: '50000000-0000-4000-8000-000000000001',
    );
    final refresh = controller.refresh();
    final reconciliation = controller.reconcile();
    await Future<void>.delayed(Duration.zero);

    expect(repository.createCalls, 1);
    expect(repository.getCalls, 1);
    expect(controller.state.isMutating, isTrue);

    repository.mutationCompleter!.complete(repository.overview);
    await mutation;
    await Future.wait([refresh, reconciliation]);
    expect(repository.getCalls, 2);
    expect(controller.state.isMutating, isFalse);

    await controller.refresh();
    expect(repository.getCalls, 3);
    controller.dispose();
  });

  test('stale mutation reloads authoritatively without hiding reload failure',
      () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();
    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.stale);

    expect(
      await controller.changeCurrency(SplitCurrency.eur),
      ListSplitMutationOutcome.stale,
    );
    expect(controller.state.message, ListSplitMessage.staleRefreshed);

    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.stale);
    repository.nextGetFailure =
        const ListSplitFailure(ListSplitFailureCode.transport);
    expect(
      await controller.changeCurrency(SplitCurrency.eur),
      ListSplitMutationOutcome.failed,
    );
    expect(controller.state.message, ListSplitMessage.refreshFailed);
    controller.dispose();
  });

  test('stale reconciliation stays busy and rejects an overlapping mutation',
      () async {
    final repository = FakeListSplitRepository();
    final controller = _controller(repository);
    await controller.load();
    repository.nextMutationFailure =
        const ListSplitFailure(ListSplitFailureCode.stale);
    repository.getCompleter = Completer<ListSplitOverview>();

    final first = controller.changeCurrency(SplitCurrency.eur);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isMutating, isTrue);
    expect(
      await controller.changeCurrency(SplitCurrency.eur),
      ListSplitMutationOutcome.failed,
    );
    expect(repository.changeCurrencyCalls, 1);

    repository.getCompleter!.complete(repository.overview);
    expect(await first, ListSplitMutationOutcome.stale);
    expect(controller.state.isMutating, isFalse);
    controller.dispose();
  });

  test('unavailable reconciliation discards the cached writable projection',
      () async {
    final expense = splitExpense();
    final repository = FakeListSplitRepository(
      initial: enabledSplitOverview(expenses: [expense]),
    );
    final controller = _controller(repository);
    await controller.load();

    repository.failure =
        const ListSplitFailure(ListSplitFailureCode.unavailable);
    await Future.wait([controller.reconcile(), controller.reconcile()]);

    expect(controller.state.overview.hasError, isTrue);
    expect(controller.state.overview.valueOrNull, isNull);
    expect(controller.state.message, ListSplitMessage.unavailable);
    expect(controller.state.isMutating, isFalse);
    expect(repository.updateCalls, 0);
    expect(repository.overview.expenses.single, expense);
    controller.dispose();
  });

  test('session reset reconstructs list-scoped Split state', () {
    final repository = FakeListSplitRepository();
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(null),
        listSplitRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final before =
        container.read(listSplitControllerProvider(splitListId).notifier);

    container.read(resetSessionStateProvider)();

    expect(
      container.read(listSplitControllerProvider(splitListId).notifier),
      isNot(same(before)),
    );
  });
}

ListSplitController _controller(FakeListSplitRepository repository) =>
    ListSplitController(
      repository,
      splitListId,
      authenticatedProfileId: splitOwnerProfileId,
      requestIdGenerator: () => '50000000-0000-4000-8000-000000000001',
    );

ListSplitOverview _overviewWithDebt() {
  final expense = splitExpense();
  return enabledSplitOverview(
    expenses: [expense],
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
  ).copyWithSuggestions(
    const [
      ListSettlementSuggestion(
        payerParticipantId: splitMemberParticipantId,
        recipientParticipantId: splitOwnerParticipantId,
        amountMinor: 3000,
      ),
    ],
  );
}

ListSplitSettlement _settlement({
  required int index,
  required DateTime createdAt,
}) {
  return ListSplitSettlement(
    id: '50000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
    payerParticipantId: splitMemberParticipantId,
    recipientParticipantId: splitOwnerParticipantId,
    recordedByParticipantId: splitOwnerParticipantId,
    amountMinor: 1,
    note: null,
    createdAt: createdAt,
    reversal: null,
    canReverse: true,
  );
}

extension on ListSplitOverview {
  ListSplitOverview copyWithSuggestions(
    List<ListSettlementSuggestion> suggestions,
  ) =>
      ListSplitOverview(
        listId: listId,
        listTitle: listTitle,
        listStatus: listStatus,
        listVersion: listVersion,
        isOwner: isOwner,
        enabled: enabled,
        writable: writable,
        settings: settings,
        participants: participants,
        expenses: expenses,
        suggestions: suggestions,
      );
}
