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
      ),
      ListSplitMutationOutcome.succeeded,
    );
    expect(repository.updateCalls, 1);

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
