import 'dart:async';

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
  recoveryInProgress,
  staleRefreshed,
  reconciled,
  recoveryFailed,
  refreshFailed,
  invalidInput,
  archivedReadOnly,
  unavailable,
  operationFailed,
}

enum ActiveListMutationOutcome {
  succeeded,
  stale,
  reconciling,
  invalid,
  unavailable,
  failed,
}

extension ActiveListMutationOutcomePresentation on ActiveListMutationOutcome {
  bool get dismissesEditor => switch (this) {
        ActiveListMutationOutcome.succeeded ||
        ActiveListMutationOutcome.stale ||
        ActiveListMutationOutcome.reconciling ||
        ActiveListMutationOutcome.unavailable =>
          true,
        ActiveListMutationOutcome.invalid ||
        ActiveListMutationOutcome.failed =>
          false,
      };
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
    Duration requestTimeout = const Duration(seconds: 15),
    Duration reconciliationDelay = const Duration(milliseconds: 300),
  })  : _invalidateLists = invalidateLists ?? _noop,
        _requestIdGenerator = requestIdGenerator,
        _requestTimeout = requestTimeout,
        _reconciliationDelay = reconciliationDelay,
        assert(requestTimeout > Duration.zero),
        assert(reconciliationDelay >= Duration.zero),
        super(const ActiveListDetailState.loading());

  final ActiveListRepository _repository;
  final String listId;
  final void Function() _invalidateLists;
  final CreationRequestIdGenerator _requestIdGenerator;
  final Duration _requestTimeout;
  final Duration _reconciliationDelay;
  int _loadGeneration = 0;
  String? _pendingItemPayload;
  String? _pendingItemRequestId;

  Future<void> load({ActiveListDetailMessage? message}) async {
    await _load(
      successMessage: message,
      failureMessage: ActiveListDetailMessage.operationFailed,
    );
  }

  Future<bool> _load({
    required ActiveListDetailMessage? successMessage,
    required ActiveListDetailMessage failureMessage,
    int? scheduledGeneration,
  }) async {
    final generation = scheduledGeneration ?? ++_loadGeneration;
    if (scheduledGeneration != null && generation != _loadGeneration) {
      return false;
    }
    final existing = state.detail.valueOrNull;
    if (existing == null) {
      state = const ActiveListDetailState.loading();
    }
    try {
      final results = await Future.wait<Object>([
        _repository.getList(listId),
        _repository.listItems(listId),
      ]).timeout(_requestTimeout);
      if (!mounted || generation != _loadGeneration) return false;
      state = ActiveListDetailState(
        detail: AsyncData(
          ActiveListDetail(
            summary: results[0] as ActiveListSummary,
            items: results[1] as List<ActiveListItem>,
          ),
        ),
        message: successMessage,
      );
      return true;
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return false;
      state = ActiveListDetailState(
        detail: existing == null
            ? AsyncError(error, stackTrace)
            : AsyncData(existing),
        message: error is ActiveListFailure &&
                error.code == ActiveListFailureCode.unavailable
            ? ActiveListDetailMessage.unavailable
            : failureMessage,
      );
      return false;
    }
  }

  Future<ActiveListMutationOutcome> rename(String title) async {
    final detail = _startMutable();
    final normalized = title.trim();
    if (detail == null) return ActiveListMutationOutcome.failed;
    if (normalized.isEmpty || normalized.length > 80) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
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

  Future<ActiveListMutationOutcome> setArchived(bool archived) {
    final detail = state.detail.valueOrNull;
    if (detail == null || state.isMutating) {
      return Future.value(ActiveListMutationOutcome.failed);
    }
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

  Future<ActiveListMutationOutcome> deleteList() async {
    final detail = _startMutable();
    if (detail == null) return ActiveListMutationOutcome.failed;
    try {
      await _repository
          .deleteList(
            listId,
            expectedVersion: detail.summary.version,
          )
          .timeout(_requestTimeout);
      if (!mounted) return ActiveListMutationOutcome.failed;
      _finish(null);
      _invalidateLists();
      return ActiveListMutationOutcome.succeeded;
    } on TimeoutException {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _beginUncertainRecovery();
    } on ActiveListFailure catch (failure) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _handleFailure(failure);
    } catch (_) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _beginUncertainRecovery();
    }
  }

  Future<ActiveListMutationOutcome> createItem(
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return ActiveListMutationOutcome.failed;
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
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
    if (created == ActiveListMutationOutcome.succeeded) {
      _pendingItemPayload = null;
      _pendingItemRequestId = null;
    }
    return created;
  }

  Future<ActiveListMutationOutcome> updateItem(
    ActiveListItem item,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return ActiveListMutationOutcome.failed;
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
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

  Future<ActiveListMutationOutcome> setItemCompleted(
    ActiveListItem item,
    bool completed,
  ) async {
    final detail = _startMutable();
    if (detail == null) return ActiveListMutationOutcome.failed;
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

  Future<ActiveListMutationOutcome> deleteItem(ActiveListItem item) async {
    final detail = _startMutable();
    if (detail == null) return ActiveListMutationOutcome.failed;
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

  Future<ActiveListMutationOutcome> reorder(
    int oldIndex,
    int newIndex,
  ) async {
    final detail = _startMutable();
    if (detail == null) return ActiveListMutationOutcome.failed;
    final reordered = [...detail.items];
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= reordered.length ||
        newIndex < 0 ||
        newIndex >= reordered.length) {
      _finish(null);
      return ActiveListMutationOutcome.failed;
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
    ++_loadGeneration;
    state = ActiveListDetailState(
      detail: state.detail,
      isMutating: true,
    );
  }

  Future<ActiveListMutationOutcome> _run(
    Future<Object?> Function() mutation,
    ActiveListDetailMessage successMessage,
  ) async {
    try {
      await mutation().timeout(_requestTimeout);
      if (!mounted) return ActiveListMutationOutcome.failed;
      _finish(null);
      _refreshInBackground(
        successMessage: successMessage,
        failureMessage: ActiveListDetailMessage.refreshFailed,
      );
      return ActiveListMutationOutcome.succeeded;
    } on TimeoutException {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _beginUncertainRecovery();
    } on ActiveListFailure catch (failure) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _handleFailure(failure);
    } catch (_) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _beginUncertainRecovery();
    }
  }

  ActiveListMutationOutcome _handleFailure(ActiveListFailure failure) {
    switch (failure.code) {
      case ActiveListFailureCode.stale:
        return _beginStaleRecovery(ActiveListDetailMessage.staleRefreshed);
      case ActiveListFailureCode.archived:
        return _beginStaleRecovery(ActiveListDetailMessage.archivedReadOnly);
      case ActiveListFailureCode.unavailable:
        return _finishWithOutcome(
          ActiveListDetailMessage.unavailable,
          ActiveListMutationOutcome.unavailable,
        );
      case ActiveListFailureCode.invalid:
      case ActiveListFailureCode.retryConflict:
        return _finishWithOutcome(
          ActiveListDetailMessage.invalidInput,
          ActiveListMutationOutcome.invalid,
        );
      case ActiveListFailureCode.transport:
        return _beginUncertainRecovery();
      case ActiveListFailureCode.generic:
        return _finishWithOutcome(
          ActiveListDetailMessage.operationFailed,
          ActiveListMutationOutcome.failed,
        );
    }
  }

  ActiveListMutationOutcome _beginStaleRecovery(
    ActiveListDetailMessage successMessage,
  ) {
    _finish(ActiveListDetailMessage.recoveryInProgress);
    _refreshInBackground(
      successMessage: successMessage,
      failureMessage: ActiveListDetailMessage.recoveryFailed,
    );
    return ActiveListMutationOutcome.stale;
  }

  ActiveListMutationOutcome _beginUncertainRecovery() {
    _finish(ActiveListDetailMessage.recoveryInProgress);
    _refreshInBackground(
      successMessage: ActiveListDetailMessage.reconciled,
      failureMessage: ActiveListDetailMessage.recoveryFailed,
      delay: _reconciliationDelay,
    );
    return ActiveListMutationOutcome.reconciling;
  }

  ActiveListMutationOutcome _finishWithOutcome(
    ActiveListDetailMessage message,
    ActiveListMutationOutcome outcome,
  ) {
    _finish(message);
    return outcome;
  }

  void _refreshInBackground({
    required ActiveListDetailMessage successMessage,
    required ActiveListDetailMessage failureMessage,
    Duration delay = Duration.zero,
  }) {
    _invalidateLists();
    final generation = ++_loadGeneration;
    unawaited(
      _recover(
        successMessage: successMessage,
        failureMessage: failureMessage,
        delay: delay,
        generation: generation,
      ),
    );
  }

  Future<void> _recover({
    required ActiveListDetailMessage successMessage,
    required ActiveListDetailMessage failureMessage,
    required Duration delay,
    required int generation,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!mounted || generation != _loadGeneration) return;
    await _load(
      successMessage: successMessage,
      failureMessage: failureMessage,
      scheduledGeneration: generation,
    );
  }

  void _finish(ActiveListDetailMessage? message) {
    state = ActiveListDetailState(detail: state.detail, message: message);
  }

  static void _noop() {}
}
