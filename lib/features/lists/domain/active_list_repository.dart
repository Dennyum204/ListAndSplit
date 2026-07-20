import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';

enum ActiveListFailureCode {
  invalid,
  unavailable,
  stale,
  retryConflict,
  archived,
  generic,
}

class ActiveListFailure implements Exception {
  const ActiveListFailure(this.code);

  final ActiveListFailureCode code;
}

abstract interface class ActiveListRepository {
  Future<ActiveListPage> listLists({
    required ActiveListStatus status,
    required int limit,
    ActiveListCursor? before,
  });

  Future<ActiveListSummary> getList(String listId);
  Future<List<ActiveListItem>> listItems(String listId);
  Future<ActiveListSummary> createList(
    String title, {
    required String requestId,
  });

  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  });

  Future<ActiveListSummary> setArchived(
    String listId, {
    required bool archived,
    required int expectedVersion,
  });

  Future<void> deleteList(String listId, {required int expectedVersion});

  Future<ActiveListItem> createItem(
    String listId,
    String name, {
    required int expectedListVersion,
    ListQuantity quantity = ListQuantity.one,
    ListUnit? unit,
    required String requestId,
  });

  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required int expectedListVersion,
    required int expectedItemVersion,
  });

  Future<ActiveListItem> setItemCompleted(
    String listId,
    String itemId, {
    required bool completed,
    required int expectedListVersion,
    required int expectedItemVersion,
  });

  Future<int> deleteItem(
    String listId,
    String itemId, {
    required int expectedListVersion,
    required int expectedItemVersion,
  });

  Future<int> reorderItems(
    String listId,
    List<String> orderedItemIds, {
    required int expectedListVersion,
  });
}
