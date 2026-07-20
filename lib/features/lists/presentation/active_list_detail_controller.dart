import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';

enum ActiveListDetailMessage {
  renamed,
  archived,
  restored,
  itemCreated,
  itemUpdated,
  itemDeleted,
  orderUpdated,
  staleRefreshed,
  invalidInput,
  archivedReadOnly,
  unavailable,
  operationFailed,
}

class ActiveListDetailState {
  const ActiveListDetailState({
    required this.detail,
    this.isMutating = false,
    this.message,
  });

  const ActiveListDetailState.loading()
      : detail = const AsyncLoading(),
        isMutating = false,
        message = null;

  final AsyncValue<ActiveListDetail> detail;
  final bool isMutating;
  final ActiveListDetailMessage? message;
}

class ActiveListDetailController extends StateNotifier<ActiveListDetailState> {
  ActiveListDetailController(
    this._repository,
    this.listId, {
    void Function()? invalidateLists,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _invalidateLists = invalidateLists ?? _noop,
        _requestIdGenerator = requestIdGenerator,
        super(const ActiveListDetailState.loading());

  final ActiveListRepository _repository;
  final String listId;
  final void Function() _invalidateLists;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _loadGeneration = 0;
  String? _pendingItemPayload;
  String? _pendingItemRequestId;

  Future<void> load({ActiveListDetailMessage? message}) async {
    final generation = ++_loadGeneration;
    final existing = state.detail.valueOrNull;
    if (existing == null) {
      state = const ActiveListDetailState.loading();
    }
    try {
      final results = await Future.wait<Object>([
        _repository.getList(listId),
        _repository.listItems(listId),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      state = ActiveListDetailState(
        detail: AsyncData(
          ActiveListDetail(
            summary: results[0] as ActiveListSummary,
            items: results[1] as List<ActiveListItem>,
          ),
        ),
        message: message,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      state = ActiveListDetailState(
        detail: existing == null
            ? AsyncError(error, stackTrace)
            : AsyncData(existing),
        message: error is ActiveListFailure &&
                error.code == ActiveListFailureCode.unavailable
            ? ActiveListDetailMessage.unavailable
            : ActiveListDetailMessage.operationFailed,
      );
    }
  }

  Future<bool> rename(String title) async {
    final detail = _startMutable();
    final normalized = title.trim();
    if (detail == null) return false;
    if (normalized.isEmpty || normalized.length > 80) {
      _finish(ActiveListDetailMessage.invalidInput);
      return false;
    }
    return _run(
      () => _repository.renameList(
        listId,
        normalized,
        expectedVersion: detail.summary.version,
      ),
      ActiveListDetailMessage.renamed,
    );
  }

  Future<bool> setArchived(bool archived) {
    final detail = state.detail.valueOrNull;
    if (detail == null || state.isMutating) return Future.value(false);
    _markMutating();
    return _run(
      () => _repository.setArchived(
        listId,
        archived: archived,
        expectedVersion: detail.summary.version,
      ),
      archived
          ? ActiveListDetailMessage.archived
          : ActiveListDetailMessage.restored,
    );
  }

  Future<bool> deleteList() async {
    final detail = _startMutable();
    if (detail == null) return false;
    try {
      await _repository.deleteList(
        listId,
        expectedVersion: detail.summary.version,
      );
      if (!mounted) return false;
      _invalidateLists();
      return true;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return false;
      await _handleFailure(failure);
      return false;
    } catch (_) {
      if (mounted) _finish(ActiveListDetailMessage.operationFailed);
      return false;
    }
  }

  Future<bool> createItem(
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return false;
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return false;
    }
    final payload =
        '$normalized\u0000${quantity.thousandths}\u0000${unit?.code ?? ''}';
    final requestId = _pendingItemPayload == payload
        ? _pendingItemRequestId!
        : _requestIdGenerator();
    _pendingItemPayload = payload;
    _pendingItemRequestId = requestId;
    final created = await _run(
      () => _repository.createItem(
        listId,
        normalized,
        quantity: quantity,
        unit: unit,
        requestId: requestId,
        expectedListVersion: detail.summary.version,
      ),
      ActiveListDetailMessage.itemCreated,
    );
    if (created) {
      _pendingItemPayload = null;
      _pendingItemRequestId = null;
    }
    return created;
  }

  Future<bool> updateItem(
    ActiveListItem item,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return false;
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return false;
    }
    return _run(
      () => _repository.updateItem(
        listId,
        item.id,
        normalized,
        quantity: quantity,
        unit: unit,
        expectedListVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      ActiveListDetailMessage.itemUpdated,
    );
  }

  Future<bool> setItemCompleted(ActiveListItem item, bool completed) async {
    final detail = _startMutable();
    if (detail == null) return false;
    return _run(
      () => _repository.setItemCompleted(
        listId,
        item.id,
        completed: completed,
        expectedListVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      ActiveListDetailMessage.itemUpdated,
    );
  }

  Future<bool> deleteItem(ActiveListItem item) async {
    final detail = _startMutable();
    if (detail == null) return false;
    return _run(
      () => _repository.deleteItem(
        listId,
        item.id,
        expectedListVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      ActiveListDetailMessage.itemDeleted,
    );
  }

  Future<bool> reorder(int oldIndex, int newIndex) async {
    final detail = _startMutable();
    if (detail == null) return false;
    final reordered = [...detail.items];
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= reordered.length ||
        newIndex < 0 ||
        newIndex >= reordered.length) {
      _finish(null);
      return false;
    }
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    return _run(
      () => _repository.reorderItems(
        listId,
        reordered.map((entry) => entry.id).toList(growable: false),
        expectedListVersion: detail.summary.version,
      ),
      ActiveListDetailMessage.orderUpdated,
    );
  }

  ActiveListDetail? _startMutable() {
    final detail = state.detail.valueOrNull;
    if (detail == null || state.isMutating) return null;
    if (detail.summary.status == ActiveListStatus.archived) {
      _finish(ActiveListDetailMessage.archivedReadOnly);
      return null;
    }
    _markMutating();
    return detail;
  }

  void _markMutating() {
    state = ActiveListDetailState(
      detail: state.detail,
      isMutating: true,
    );
  }

  Future<bool> _run(
    Future<Object?> Function() mutation,
    ActiveListDetailMessage successMessage,
  ) async {
    try {
      await mutation();
      if (!mounted) return false;
      _invalidateLists();
      await load(message: successMessage);
      return true;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return false;
      await _handleFailure(failure);
      return false;
    } catch (_) {
      if (mounted) _finish(ActiveListDetailMessage.operationFailed);
      return false;
    }
  }

  Future<void> _handleFailure(ActiveListFailure failure) async {
    switch (failure.code) {
      case ActiveListFailureCode.stale:
        _invalidateLists();
        await load(message: ActiveListDetailMessage.staleRefreshed);
      case ActiveListFailureCode.archived:
        _invalidateLists();
        await load(message: ActiveListDetailMessage.archivedReadOnly);
      case ActiveListFailureCode.unavailable:
        _finish(ActiveListDetailMessage.unavailable);
      case ActiveListFailureCode.invalid:
      case ActiveListFailureCode.retryConflict:
        _finish(ActiveListDetailMessage.invalidInput);
      case ActiveListFailureCode.generic:
        _finish(ActiveListDetailMessage.operationFailed);
    }
  }

  void _finish(ActiveListDetailMessage? message) {
    state = ActiveListDetailState(detail: state.detail, message: message);
  }

  static void _noop() {}
}
