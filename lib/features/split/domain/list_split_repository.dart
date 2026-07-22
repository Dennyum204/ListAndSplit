import 'package:list_and_split/features/split/domain/list_split.dart';

enum ListSplitFailureCode {
  invalid,
  unavailable,
  stale,
  archived,
  capacity,
  transport,
  generic,
}

class ListSplitFailure implements Exception {
  const ListSplitFailure(this.code);

  final ListSplitFailureCode code;
}

abstract interface class ListSplitRepository {
  Future<ListSplitOverview> getSplit(String listId);

  Future<ListSplitOverview> enableSplit(
    String listId,
    SplitCurrency currency, {
    required int expectedListVersion,
  });

  Future<ListSplitOverview> changeCurrency(
    String listId,
    SplitCurrency currency, {
    required int expectedSplitVersion,
  });

  Future<ListSplitOverview> createExpense(
    String listId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required String requestId,
    required int expectedSplitVersion,
  });

  Future<ListSplitOverview> updateExpense(
    String listId,
    String expenseId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  });

  Future<ListSplitOverview> deleteExpense(
    String listId,
    String expenseId, {
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  });
}
