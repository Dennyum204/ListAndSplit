import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
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

  test('Realtime overview reconciliation moves archive and restore projections',
      () async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
    );
    addTearDown(controller.dispose);
    await controller.loadAll();

    await repository.setArchived('list-1', archived: true, expectedVersion: 1);
    await controller.reconcile();

    expect(controller.state.activeLists.requireValue, isEmpty);
    expect(controller.state.archivedLists.requireValue.single.id, 'list-1');

    await repository.setArchived('list-1', archived: false, expectedVersion: 2);
    await controller.reconcile();

    expect(controller.state.activeLists.requireValue.single.id, 'list-1');
    expect(controller.state.archivedLists.requireValue, isEmpty);
  });

  test('manual overview refresh remains an authoritative fallback', () async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
    );
    addTearDown(controller.dispose);
    await controller.loadAll();

    await repository.renameList('list-1', 'Manually refreshed',
        expectedVersion: 1);
    await controller.refresh(ActiveListStatus.active);

    expect(
      controller.state.activeLists.requireValue.single.title,
      'Manually refreshed',
    );
  });

  test('owner and member device registries reconcile independently', () async {
    final ownerRepository = FakeActiveListRepository()
      ..activeLists = [_summary(title: 'Original')];
    final memberRepository = FakeActiveListRepository()
      ..activeLists = [_summary(title: 'Original', isOwner: false)];
    final ownerController =
        ActiveListDetailController(ownerRepository, 'list-1');
    final memberController =
        ActiveListDetailController(memberRepository, 'list-1');
    addTearDown(ownerController.dispose);
    addTearDown(memberController.dispose);
    await Future.wait([ownerController.load(), memberController.load()]);

    final ownerRegistry = ReconciliationRegistry()
      ..register(ownerController.reconcile);
    final memberRegistry = ReconciliationRegistry()
      ..register(memberController.reconcile);
    await ownerRepository.renameList('list-1', 'Owner projection',
        expectedVersion: 1);
    await memberRepository.renameList('list-1', 'Member projection',
        expectedVersion: 1);

    await ownerRegistry.reconcile();
    expect(ownerController.state.detail.requireValue.summary.title,
        'Owner projection');
    expect(
        memberController.state.detail.requireValue.summary.title, 'Original');

    await memberRegistry.reconcile();
    expect(memberController.state.detail.requireValue.summary.title,
        'Member projection');
  });

  test('remote archive is signalled once after authoritative detail refresh',
      () async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)];
    final controller = ActiveListDetailController(repository, 'list-1');
    addTearDown(controller.dispose);
    await controller.load();

    await repository.setArchived('list-1', archived: true, expectedVersion: 1);
    await controller.reconcile();

    expect(
      controller.state.message,
      ActiveListDetailMessage.remotelyArchived,
    );
    expect(
      controller.state.detail.requireValue.summary.status,
      ActiveListStatus.archived,
    );

    await controller.reconcile();
    expect(controller.state.message, isNull);
  });

  test('Realtime overview reconciliation preserves cached state on failure',
      () async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(title: 'Cached')];
    final controller = ActiveListsController(
      repository,
      hasAuthenticatedUser: true,
    );
    addTearDown(controller.dispose);
    await controller.loadAll();

    repository.failure =
        const ActiveListFailure(ActiveListFailureCode.transport);
    await controller.reconcile();

    expect(controller.state.activeLists.requireValue.single.title, 'Cached');
    expect(controller.state.activeLists.hasError, isFalse);
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

    expect(
      await controller.rename('Changed elsewhere'),
      ActiveListMutationOutcome.stale,
    );

    await Future<void>.delayed(Duration.zero);

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
      ActiveListMutationOutcome.failed,
    );
    expect(
      controller.state.message,
      ActiveListDetailMessage.archivedReadOnly,
    );
    expect(repository.mutationCalls, 0);

    expect(
      await controller.setArchived(false),
      ActiveListMutationOutcome.succeeded,
    );
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
      ActiveListMutationOutcome.reconciling,
    );
    repository.failure = null;
    expect(
      await controller.createItem(
        'Coffee',
        quantity: ListQuantity.fromThousandths(1500),
        unit: ListUnit.pack,
      ),
      ActiveListMutationOutcome.succeeded,
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

    expect(
      await controller.reorder(0, 2),
      ActiveListMutationOutcome.succeeded,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.state.detail.asData?.value.items.map((item) => item.id),
      ['item-2', 'item-1'],
    );
    expect(controller.state.message, ActiveListDetailMessage.orderUpdated);
  });

  test(
      'two-device stale rename settles before delayed recovery and never overwrites',
      () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(title: 'Weekend Shopping'),
      items: [_item()],
    );
    final controllerA = ActiveListDetailController(repository, 'list-1');
    final controllerB = ActiveListDetailController(repository, 'list-1');
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);
    await Future.wait([controllerA.load(), controllerB.load()]);

    expect(
      await controllerA.rename('Weekend Shopping Updated'),
      ActiveListMutationOutcome.succeeded,
    );
    await _flushAsync();
    final delayedRecovery = Completer<ActiveListSummary>();
    repository.nextGet = delayedRecovery;

    final outcome = await controllerB.rename('Old Device Name');

    expect(outcome, ActiveListMutationOutcome.stale);
    expect(controllerB.state.isMutating, isFalse);
    expect(
      controllerB.state.message,
      ActiveListDetailMessage.recoveryInProgress,
    );
    expect(delayedRecovery.isCompleted, isFalse);
    expect(repository.summary.title, 'Weekend Shopping Updated');

    delayedRecovery.complete(repository.summary);
    await _flushAsync();

    expect(
      controllerB.state.detail.requireValue.summary.title,
      'Weekend Shopping Updated',
    );
    expect(
      controllerB.state.message,
      ActiveListDetailMessage.staleRefreshed,
    );
    expect(repository.summary.title, isNot('Old Device Name'));
  });

  test('stale item edit settles and reloads the authoritative item', () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(),
      items: [_item()],
    );
    final controllerA = ActiveListDetailController(repository, 'list-1');
    final controllerB = ActiveListDetailController(repository, 'list-1');
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);
    await Future.wait([controllerA.load(), controllerB.load()]);
    final staleItem = controllerB.state.detail.requireValue.items.single;

    expect(
      await controllerA.updateItem(
        controllerA.state.detail.requireValue.items.single,
        'Tea',
        quantity: ListQuantity.one,
        unit: null,
      ),
      ActiveListMutationOutcome.succeeded,
    );
    await _flushAsync();
    final delayedRecovery = Completer<ActiveListSummary>();
    repository.nextGet = delayedRecovery;

    expect(
      await controllerB.updateItem(
        staleItem,
        'Old coffee',
        quantity: ListQuantity.one,
        unit: null,
      ),
      ActiveListMutationOutcome.stale,
    );
    expect(controllerB.state.isMutating, isFalse);
    expect(repository.items.single.name, 'Tea');

    delayedRecovery.complete(repository.summary);
    await _flushAsync();

    expect(controllerB.state.detail.requireValue.items.single.name, 'Tea');
    expect(controllerB.state.message, ActiveListDetailMessage.staleRefreshed);
    expect(repository.items.single.name, isNot('Old coffee'));
  });

  test('stale reorder settles and preserves the authoritative item order',
      () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(),
      items: [
        _item(),
        _item(id: 'item-2', position: 2),
        _item(id: 'item-3', position: 3),
      ],
    );
    final controllerA = ActiveListDetailController(repository, 'list-1');
    final controllerB = ActiveListDetailController(repository, 'list-1');
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);
    await Future.wait([controllerA.load(), controllerB.load()]);

    expect(
      await controllerA.reorder(0, 3),
      ActiveListMutationOutcome.succeeded,
    );
    await _flushAsync();
    final delayedRecovery = Completer<ActiveListSummary>();
    repository.nextGet = delayedRecovery;

    expect(
      await controllerB.reorder(1, 3),
      ActiveListMutationOutcome.stale,
    );
    expect(controllerB.state.isMutating, isFalse);
    expect(repository.items.map((item) => item.id), [
      'item-2',
      'item-3',
      'item-1',
    ]);

    delayedRecovery.complete(repository.summary);
    await _flushAsync();

    expect(
      controllerB.state.detail.requireValue.items.map((item) => item.id),
      ['item-2', 'item-3', 'item-1'],
    );
    expect(controllerB.state.message, ActiveListDetailMessage.staleRefreshed);
  });

  test('failed stale recovery remains enabled and supports a truthful retry',
      () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(title: 'Original'),
      items: [_item()],
    );
    final controllerA = ActiveListDetailController(repository, 'list-1');
    final controllerB = ActiveListDetailController(repository, 'list-1');
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);
    await Future.wait([controllerA.load(), controllerB.load()]);
    expect(
      await controllerA.rename('Authoritative'),
      ActiveListMutationOutcome.succeeded,
    );
    await _flushAsync();
    final failedRecovery = Completer<ActiveListSummary>();
    repository.nextGet = failedRecovery;

    expect(
      await controllerB.rename('Stale draft'),
      ActiveListMutationOutcome.stale,
    );
    expect(controllerB.state.isMutating, isFalse);
    failedRecovery.completeError(StateError('offline'));
    await _flushAsync();

    expect(controllerB.state.isMutating, isFalse);
    expect(
      controllerB.state.message,
      ActiveListDetailMessage.recoveryFailed,
    );
    expect(controllerB.state.detail.requireValue.summary.title, 'Original');

    await controllerB.load();
    expect(
      controllerB.state.detail.requireValue.summary.title,
      'Authoritative',
    );
  });

  test('never-completing write and recovery reads cannot hold mutation state',
      () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(),
      items: [_item()],
    );
    final controller = ActiveListDetailController(
      repository,
      'list-1',
      requestTimeout: const Duration(milliseconds: 10),
      reconciliationDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.load();
    final hangingMutation = Completer<ActiveListSummary>();
    final hangingRecovery = Completer<ActiveListSummary>();
    repository
      ..nextRename = hangingMutation
      ..nextGet = hangingRecovery;

    expect(
      await controller.rename('Maybe saved'),
      ActiveListMutationOutcome.reconciling,
    );
    expect(controller.state.isMutating, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.state.isMutating, isFalse);
    expect(controller.state.message, ActiveListDetailMessage.recoveryFailed);

    hangingMutation.complete(repository.summary);
    hangingRecovery.complete(repository.summary);
  });

  test('an older background refresh cannot unlock a newer mutation', () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(),
      items: [_item()],
    );
    final controller = ActiveListDetailController(repository, 'list-1');
    addTearDown(controller.dispose);
    await controller.load();
    final olderRefresh = Completer<ActiveListSummary>();
    repository.nextGet = olderRefresh;

    expect(
      await controller.rename('First rename'),
      ActiveListMutationOutcome.succeeded,
    );
    final newerMutation = Completer<ActiveListSummary>();
    repository.nextRename = newerMutation;
    final newerResult = controller.rename('Second rename');
    expect(controller.state.isMutating, isTrue);

    olderRefresh.complete(repository.summary);
    await _flushAsync();

    expect(controller.state.isMutating, isTrue);
    newerMutation.complete(repository.summary);
    expect(await newerResult, ActiveListMutationOutcome.succeeded);
    await _flushAsync();
    expect(controller.state.isMutating, isFalse);
  });

  test('disposing detail releases reconciliation waiting on a mutation',
      () async {
    final repository = _VersionedActiveListRepository(
      summary: _summary(),
      items: const [],
    );
    final controller = ActiveListDetailController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    await controller.load();
    final delayedMutation = Completer<ActiveListSummary>();
    repository.nextRename = delayedMutation;

    final mutation = controller.rename('Delayed');
    await Future<void>.delayed(Duration.zero);
    final reconciliation = controller.reconcile();
    controller.dispose();

    await reconciliation.timeout(const Duration(milliseconds: 100));
    delayedMutation.complete(_summary(title: 'Delayed', version: 2));
    await mutation;
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
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

class _VersionedActiveListRepository extends FakeActiveListRepository {
  _VersionedActiveListRepository({
    required ActiveListSummary summary,
    required List<ActiveListItem> items,
  }) {
    activeLists = [
      summary.copyWith(
        itemCount: items.length,
        completedItemCount: items.where((item) => item.isCompleted).length,
      ),
    ];
    itemsByList[summary.id] = List.of(items);
  }

  Completer<ActiveListSummary>? nextGet;
  Completer<ActiveListSummary>? nextRename;

  ActiveListSummary get summary => [...activeLists, ...archivedLists].single;
  List<ActiveListItem> get items => itemsByList[summary.id]!;

  @override
  Future<ActiveListSummary> getList(String listId) {
    final completer = nextGet;
    if (completer != null) {
      nextGet = null;
      return completer.future;
    }
    return super.getList(listId);
  }

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    final completer = nextRename;
    if (completer != null) {
      nextRename = null;
      return completer.future;
    }
    _requireListVersion(expectedVersion);
    final updated = summary.copyWith(
      title: title,
      version: summary.version + 1,
      updatedAt: summary.updatedAt.add(const Duration(seconds: 1)),
    );
    _replaceSummary(updated);
    return updated;
  }

  @override
  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    final index = items.indexWhere((item) => item.id == itemId);
    final current = items[index];
    if (expectedListVersion != summary.version ||
        expectedItemVersion != current.version) {
      throw const ActiveListFailure(ActiveListFailureCode.stale);
    }
    final updatedAt = current.updatedAt.add(const Duration(seconds: 1));
    final updated = ActiveListItem(
      id: current.id,
      name: name,
      quantity: quantity,
      unit: unit,
      position: current.position,
      version: current.version + 1,
      completedAt: current.completedAt,
      completedBy: current.completedBy,
      createdAt: current.createdAt,
      updatedAt: updatedAt,
    );
    items[index] = updated;
    _incrementListVersion(updatedAt);
    return updated;
  }

  @override
  Future<int> reorderItems(
    String listId,
    List<String> orderedItemIds, {
    required int expectedListVersion,
  }) async {
    mutationCalls += 1;
    _requireListVersion(expectedListVersion);
    final byId = {for (final item in items) item.id: item};
    final reordered = <ActiveListItem>[];
    for (var index = 0; index < orderedItemIds.length; index += 1) {
      final current = byId[orderedItemIds[index]]!;
      reordered.add(
        ActiveListItem(
          id: current.id,
          name: current.name,
          quantity: current.quantity,
          unit: current.unit,
          position: index + 1,
          version: current.version,
          completedAt: current.completedAt,
          completedBy: current.completedBy,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      );
    }
    itemsByList[listId] = reordered;
    _incrementListVersion(summary.updatedAt.add(const Duration(seconds: 1)));
    return summary.version;
  }

  void _requireListVersion(int expectedVersion) {
    if (expectedVersion != summary.version) {
      throw const ActiveListFailure(ActiveListFailureCode.stale);
    }
  }

  void _incrementListVersion(DateTime updatedAt) {
    _replaceSummary(
      summary.copyWith(
        version: summary.version + 1,
        updatedAt: updatedAt,
      ),
    );
  }

  void _replaceSummary(ActiveListSummary replacement) {
    activeLists = [
      for (final entry in activeLists)
        if (entry.id == replacement.id) replacement else entry,
    ];
    archivedLists = [
      for (final entry in archivedLists)
        if (entry.id == replacement.id) replacement else entry,
    ];
  }
}

ActiveListSummary _summary({
  String id = 'list-1',
  String title = 'Groceries',
  ActiveListStatus status = ActiveListStatus.active,
  DateTime? archivedAt,
  int version = 1,
  bool isOwner = true,
}) {
  return ActiveListSummary(
    id: id,
    title: title,
    status: status,
    version: version,
    itemCount: 1,
    completedItemCount: 0,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
    archivedAt: archivedAt,
    isOwner: isOwner,
  );
}

ActiveListItem _item({
  String id = 'item-1',
  String name = 'Coffee',
  int position = 1,
  int version = 1,
}) {
  return ActiveListItem(
    id: id,
    name: name,
    quantity: ListQuantity.fromThousandths(1500),
    unit: ListUnit.pack,
    position: position,
    version: version,
    completedAt: null,
    completedBy: null,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
  );
}
