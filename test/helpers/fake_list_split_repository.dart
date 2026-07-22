import 'dart:async';

import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';

const splitListId = '10000000-0000-4000-8000-000000000001';
const splitOwnerProfileId = '20000000-0000-4000-8000-000000000001';
const splitMemberProfileId = '20000000-0000-4000-8000-000000000002';
const splitOwnerParticipantId = '30000000-0000-4000-8000-000000000001';
const splitMemberParticipantId = '30000000-0000-4000-8000-000000000002';

class FakeListSplitRepository implements ListSplitRepository {
  FakeListSplitRepository({ListSplitOverview? initial})
      : overview = initial ?? enabledSplitOverview();

  ListSplitOverview overview;
  Object? failure;
  Object? nextGetFailure;
  Object? nextMutationFailure;
  Completer<ListSplitOverview>? mutationCompleter;
  Completer<ListSplitOverview>? getCompleter;
  int getCalls = 0;
  int enableCalls = 0;
  int changeCurrencyCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  final List<String> requestIds = [];
  final Set<String> completedRequestIds = {};

  @override
  Future<ListSplitOverview> getSplit(String listId) async {
    getCalls += 1;
    final currentFailure = nextGetFailure;
    nextGetFailure = null;
    if (currentFailure != null) throw currentFailure;
    _throwFailure();
    final completer = getCompleter;
    if (completer != null) return completer.future;
    return overview;
  }

  @override
  Future<ListSplitOverview> enableSplit(
    String listId,
    SplitCurrency currency, {
    required int expectedListVersion,
  }) async {
    enableCalls += 1;
    _throwMutationFailure();
    final now = DateTime.utc(2026, 7, 22, 10);
    overview = _copy(
      overview,
      enabled: true,
      writable: true,
      settings: ListSplitSettings(
        currency: currency,
        version: 1,
        createdAt: now,
        updatedAt: now,
      ),
      participants: splitParticipants(),
    );
    return _completeMutation();
  }

  @override
  Future<ListSplitOverview> changeCurrency(
    String listId,
    SplitCurrency currency, {
    required int expectedSplitVersion,
  }) async {
    changeCurrencyCalls += 1;
    _throwMutationFailure();
    final settings = overview.settings!;
    overview = _copy(
      overview,
      settings: ListSplitSettings(
        currency: currency,
        version: settings.version + 1,
        createdAt: settings.createdAt,
        updatedAt: settings.updatedAt.add(const Duration(seconds: 1)),
      ),
    );
    return _completeMutation();
  }

  @override
  Future<ListSplitOverview> createExpense(
    String listId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required String requestId,
    required int expectedSplitVersion,
  }) async {
    createCalls += 1;
    requestIds.add(requestId);
    _throwMutationFailure();
    if (completedRequestIds.contains(requestId)) return overview;
    final now = DateTime.utc(2026, 7, 22, 11, overview.expenses.length);
    final expense = _expense(
      id: '40000000-0000-4000-8000-${(overview.expenses.length + 1).toString().padLeft(12, '0')}',
      description: description,
      amountMinor: amountMinor,
      payerParticipantId: payerParticipantId,
      beneficiaryParticipantIds: beneficiaryParticipantIds,
      createdAt: now,
    );
    overview = _withExpenses([...overview.expenses, expense]);
    completedRequestIds.add(requestId);
    return _completeMutation();
  }

  @override
  Future<ListSplitOverview> updateExpense(
    String listId,
    String expenseId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  }) async {
    updateCalls += 1;
    _throwMutationFailure();
    final existing =
        overview.expenses.firstWhere((entry) => entry.id == expenseId);
    final updated = _expense(
      id: expenseId,
      description: description,
      amountMinor: amountMinor,
      payerParticipantId: payerParticipantId,
      beneficiaryParticipantIds: beneficiaryParticipantIds,
      version: existing.version + 1,
      createdAt: existing.createdAt,
    );
    overview = _withExpenses([
      for (final expense in overview.expenses)
        if (expense.id == expenseId) updated else expense,
    ]);
    return _completeMutation();
  }

  @override
  Future<ListSplitOverview> deleteExpense(
    String listId,
    String expenseId, {
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  }) async {
    deleteCalls += 1;
    _throwMutationFailure();
    overview = _withExpenses(
      overview.expenses.where((entry) => entry.id != expenseId).toList(),
    );
    return _completeMutation();
  }

  ListSplitOverview _withExpenses(List<ListSplitExpense> expenses) {
    final settings = overview.settings!;
    final totals = <String, (int, int)>{
      for (final participant in overview.participants) participant.id: (0, 0),
    };
    for (final expense in expenses) {
      final payer = totals[expense.payerParticipantId]!;
      totals[expense.payerParticipantId] =
          (payer.$1 + expense.amountMinor, payer.$2);
      for (final share in expense.shares) {
        final participant = totals[share.participantId]!;
        totals[share.participantId] =
            (participant.$1, participant.$2 + share.amountMinor);
      }
    }
    return _copy(
      overview,
      settings: ListSplitSettings(
        currency: settings.currency,
        version: settings.version + 1,
        createdAt: settings.createdAt,
        updatedAt: settings.updatedAt.add(const Duration(seconds: 1)),
      ),
      participants: [
        for (final participant in overview.participants)
          ListSplitParticipant(
            id: participant.id,
            profileId: participant.profileId,
            username: participant.username,
            displayName: participant.displayName,
            isAnonymized: participant.isAnonymized,
            isCurrent: participant.isCurrent,
            paidMinor: totals[participant.id]!.$1,
            owedMinor: totals[participant.id]!.$2,
            balanceMinor:
                totals[participant.id]!.$1 - totals[participant.id]!.$2,
          ),
      ],
      expenses: expenses,
    );
  }

  Future<ListSplitOverview> _completeMutation() async {
    final completer = mutationCompleter;
    if (completer != null) return completer.future;
    return overview;
  }

  void _throwFailure() {
    final current = failure;
    if (current != null) throw current;
  }

  void _throwMutationFailure() {
    final currentFailure = nextMutationFailure;
    nextMutationFailure = null;
    if (currentFailure != null) throw currentFailure;
    _throwFailure();
  }
}

ListSplitOverview disabledSplitOverview({
  bool isOwner = true,
  SplitListStatus status = SplitListStatus.active,
}) {
  return ListSplitOverview(
    listId: splitListId,
    listTitle: 'Weekend shop',
    listStatus: status,
    listVersion: 3,
    isOwner: isOwner,
    enabled: false,
    writable: false,
    settings: null,
    participants: const [],
    expenses: const [],
  );
}

ListSplitOverview enabledSplitOverview({
  bool isOwner = true,
  SplitListStatus status = SplitListStatus.active,
  bool writable = true,
  List<ListSplitParticipant>? participants,
  List<ListSplitExpense> expenses = const [],
}) {
  final now = DateTime.utc(2026, 7, 22, 9);
  return ListSplitOverview(
    listId: splitListId,
    listTitle: 'Weekend shop',
    listStatus: status,
    listVersion: 3,
    isOwner: isOwner,
    enabled: true,
    writable: writable && status == SplitListStatus.active,
    settings: ListSplitSettings(
      currency: SplitCurrency.chf,
      version: 1,
      createdAt: now,
      updatedAt: now,
    ),
    participants: participants ?? splitParticipants(),
    expenses: expenses,
  );
}

List<ListSplitParticipant> splitParticipants() => const [
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
    ];

ListSplitExpense splitExpense({
  String id = '40000000-0000-4000-8000-000000000001',
  String description = 'Dinner',
  int amountMinor = 6000,
  String payerParticipantId = splitOwnerParticipantId,
  List<String> beneficiaryParticipantIds = const [
    splitOwnerParticipantId,
    splitMemberParticipantId,
  ],
}) =>
    _expense(
      id: id,
      description: description,
      amountMinor: amountMinor,
      payerParticipantId: payerParticipantId,
      beneficiaryParticipantIds: beneficiaryParticipantIds,
      createdAt: DateTime.utc(2026, 7, 22, 11),
    );

ListSplitExpense _expense({
  required String id,
  required String description,
  required int amountMinor,
  required String payerParticipantId,
  required List<String> beneficiaryParticipantIds,
  required DateTime createdAt,
  int version = 1,
}) {
  final ordered = beneficiaryParticipantIds.toSet().toList()..sort();
  final base = amountMinor ~/ ordered.length;
  final remainder = amountMinor % ordered.length;
  return ListSplitExpense(
    id: id,
    description: description,
    amountMinor: amountMinor,
    payerParticipantId: payerParticipantId,
    creatorParticipantId: splitOwnerParticipantId,
    lastEditorParticipantId: splitOwnerParticipantId,
    version: version,
    createdAt: createdAt,
    updatedAt: createdAt.add(Duration(seconds: version - 1)),
    beneficiaryParticipantIds: ordered,
    shares: [
      for (var index = 0; index < ordered.length; index += 1)
        ListExpenseShare(
          participantId: ordered[index],
          amountMinor: base + (index < remainder ? 1 : 0),
        ),
    ],
  );
}

ListSplitOverview _copy(
  ListSplitOverview source, {
  bool? enabled,
  bool? writable,
  ListSplitSettings? settings,
  List<ListSplitParticipant>? participants,
  List<ListSplitExpense>? expenses,
}) {
  return ListSplitOverview(
    listId: source.listId,
    listTitle: source.listTitle,
    listStatus: source.listStatus,
    listVersion: source.listVersion,
    isOwner: source.isOwner,
    enabled: enabled ?? source.enabled,
    writable: writable ?? source.writable,
    settings: settings ?? source.settings,
    participants: participants ?? source.participants,
    expenses: expenses ?? source.expenses,
  );
}
