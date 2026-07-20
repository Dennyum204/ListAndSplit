import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_controller.dart';

import '../../helpers/fakes.dart';

void main() {
  test('overview loads active and archived lists independently', () async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..archivedLists = [
        _summary(
          id: 'archived-list',
          status: ActiveListStatus.archived,
          archivedAt: DateTime.utc(2026, 7, 20, 11),
        ),
      ];
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
    );
    addTearDown(controller.dispose);

    await controller.loadAll();

    expect(controller.state.activeLists.asData?.value.single.id, 'list-1');
    expect(
      controller.state.archivedLists.asData?.value.single.id,
      'archived-list',
    );
    expect(repository.listCalls, 2);
  });

  test('creation validates and blocks rapid duplicate submissions', () async {
    final repository = FakeActiveListRepository()
      ..createCompleter = Completer<ActiveListSummary>();
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
    );
    addTearDown(controller.dispose);
    await controller.loadAll();

    expect(await controller.create('   '), isFalse);
    expect(controller.state.message, ActiveListsMessage.invalidTitle);
    final first = controller.create(' Duplicate title ');
    final second = controller.create(' Duplicate title ');
    expect(await second, isFalse);
    expect(repository.createCalls, 1);

    repository.createCompleter!.complete(_summary(title: 'Duplicate title'));
    expect(await first, isTrue);
    expect(controller.state.message, ActiveListsMessage.created);
  });

  test('lost-response retry reuses its creation request id', () async {
    final repository = FakeActiveListRepository()
      ..failure = StateError('lost response');
    var generated = 0;
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
      requestIdGenerator: () => 'request-${++generated}',
    );
    addTearDown(controller.dispose);
    await controller.loadAll();

    expect(await controller.create('Groceries'), isFalse);
    repository.failure = null;
    expect(await controller.create('Groceries'), isTrue);

    expect(repository.createRequestIds, ['request-1', 'request-1']);
    expect(generated, 1);
  });

  test('detail stale conflict reloads authoritative state', () async {
    final repository = _StaleOnceRepository()
      ..activeLists = [_summary()]
      ..itemsByList['list-1'] = [_item()];
    var invalidations = 0;
    final controller = ActiveListDetailController(
      repository,
      'list-1',
      invalidateLists: () => invalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.rename('Changed elsewhere'), isFalse);

    expect(controller.state.message, ActiveListDetailMessage.staleRefreshed);
    expect(controller.state.isMutating, isFalse);
    expect(repository.getCalls, 2);
    expect(invalidations, 1);
  });

  test('archived detail stays readable and rejects item mutations locally',
      () async {
    final repository = FakeActiveListRepository()
      ..archivedLists = [
        _summary(
          status: ActiveListStatus.archived,
          archivedAt: DateTime.utc(2026, 7, 20, 11),
        ),
      ]
      ..itemsByList['list-1'] = [_item()];
    final controller = ActiveListDetailController(repository, 'list-1');
    addTearDown(controller.dispose);
    await controller.load();

    expect(
      await controller.createItem(
        'Another',
        quantity: ListQuantity.one,
        unit: null,
      ),
      isFalse,
    );
    expect(
      controller.state.message,
      ActiveListDetailMessage.archivedReadOnly,
    );
    expect(repository.mutationCalls, 0);

    expect(await controller.setArchived(false), isTrue);
    expect(repository.mutationCalls, 1);
  });

  test('item lost-response retry reuses its request id and exact payload',
      () async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    var generated = 0;
    final controller = ActiveListDetailController(
      repository,
      'list-1',
      requestIdGenerator: () => 'item-request-${++generated}',
    );
    addTearDown(controller.dispose);
    await controller.load();
    repository.failure = StateError('lost response');

    expect(
      await controller.createItem(
        'Coffee',
        quantity: ListQuantity.fromThousandths(1500),
        unit: ListUnit.pack,
      ),
      isFalse,
    );
    repository.failure = null;
    expect(
      await controller.createItem(
        'Coffee',
        quantity: ListQuantity.fromThousandths(1500),
        unit: ListUnit.pack,
      ),
      isTrue,
    );

    expect(
      repository.itemRequestIds,
      ['item-request-1', 'item-request-1'],
    );
    expect(generated, 1);
  });

  test('valid reorder submits the entire deterministic item set', () async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..itemsByList['list-1'] = [_item(), _item(id: 'item-2', position: 2)];
    final controller = ActiveListDetailController(repository, 'list-1');
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.reorder(0, 2), isTrue);
    expect(
      controller.state.detail.asData?.value.items.map((item) => item.id),
      ['item-2', 'item-1'],
    );
    expect(controller.state.message, ActiveListDetailMessage.orderUpdated);
  });
}

class _StaleOnceRepository extends FakeActiveListRepository {
  var getCalls = 0;
  var _shouldFail = true;

  @override
  Future<ActiveListSummary> getList(String listId) {
    getCalls += 1;
    return super.getList(listId);
  }

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw const ActiveListFailure(ActiveListFailureCode.stale);
    }
    return super.renameList(
      listId,
      title,
      expectedVersion: expectedVersion,
    );
  }
}

ActiveListSummary _summary({
  String id = 'list-1',
  String title = 'Groceries',
  ActiveListStatus status = ActiveListStatus.active,
  DateTime? archivedAt,
}) {
  return ActiveListSummary(
    id: id,
    title: title,
    status: status,
    version: 1,
    itemCount: 1,
    completedItemCount: 0,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
    archivedAt: archivedAt,
  );
}

ActiveListItem _item({String id = 'item-1', int position = 1}) {
  return ActiveListItem(
    id: id,
    name: 'Coffee',
    quantity: ListQuantity.fromThousandths(1500),
    unit: ListUnit.pack,
    position: position,
    version: 1,
    completedAt: null,
    completedBy: null,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
  );
}
