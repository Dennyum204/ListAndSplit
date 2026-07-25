import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/lists/domain/general_note.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';

enum ActiveListDetailMessage {
  renamed,
  archived,
  restored,
  remotelyArchived,
  itemCreated,
  itemUpdated,
  itemDeleted,
  noteSaved,
  orderUpdated,
  left,
  recoveryInProgress,
  staleRefreshed,
  reconciled,
  recoveryFailed,
  refreshFailed,
  invalidInput,
  itemCapacity,
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
  Completer<void>? _mutationCompleted;
  String? _pendingItemPayload;
  String? _pendingItemRequestId;

  Future<void> load({ActiveListDetailMessage? message}) async {
    await _load(
      successMessage: message,
      failureMessage: ActiveListDetailMessage.operationFailed,
    );
  }

  Future<void> reconcile() async {
    final mutationCompleted = _mutationCompleted;
    if (mutationCompleted != null) await mutationCompleted.future;
    if (!mounted) return;
    await _load(successMessage: null, failureMessage: null);
  }

  Future<bool> _load({
    required ActiveListDetailMessage? successMessage,
    required ActiveListDetailMessage? failureMessage,
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
        _repository.listParticipants(listId),
        _repository.getGeneralNote(listId),
      ]).timeout(_requestTimeout);
      if (!mounted || generation != _loadGeneration) return false;
      final refreshedSummary = results[0] as ActiveListSummary;
      final message = existing?.summary.status == ActiveListStatus.active &&
              refreshedSummary.status == ActiveListStatus.archived &&
              successMessage != ActiveListDetailMessage.archived
          ? ActiveListDetailMessage.remotelyArchived
          : successMessage;
      state = ActiveListDetailState(
        detail: AsyncData(
          ActiveListDetail(
            summary: refreshedSummary,
            items: results[1] as List<ActiveListItem>,
            participants: results[2] as List<ActiveListParticipant>,
            generalNote: results[3] as ActiveListGeneralNote,
          ),
        ),
        message: message,
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
            : failureMessage ?? state.message,
      );
      return false;
    }
  }

  Future<ActiveListMutationOutcome> rename(String title) async {
    final detail = _startMutable();
    final normalized = title.trim();
    if (detail == null || !detail.summary.isOwner) {
      if (detail != null) _finish(ActiveListDetailMessage.unavailable);
      return ActiveListMutationOutcome.unavailable;
    }
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
    if (detail == null || state.isMutating || !detail.summary.isOwner) {
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
    if (state.detail.valueOrNull?.summary.isOwner != true) {
      return ActiveListMutationOutcome.unavailable;
    }
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
    Set<String> assigneeProfileIds = const {},
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return ActiveListMutationOutcome.failed;
    if (detail.items.length >= activeListItemCapacity) {
      _finish(ActiveListDetailMessage.itemCapacity);
      return ActiveListMutationOutcome.invalid;
    }
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
    }
    final assigneeIds = _validatedAssigneeIds(detail, assigneeProfileIds);
    if (assigneeIds == null) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
    }
    final payload = '$normalized\u0000${quantity.thousandths}\u0000'
        '${unit?.code ?? ''}\u0000${assigneeIds.join(',')}';
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
        assigneeProfileIds: assigneeIds,
        requestId: requestId,
        expectedListVersion: detail.summary.version,
      ),
      ActiveListDetailMessage.itemCreated,
      reconcileInvalid: true,
    );
    if (created == ActiveListMutationOutcome.succeeded) {
      _pendingItemPayload = null;
      _pendingItemRequestId = null;
    }
    return created;
  }

  Future<ActiveListMutationOutcome> updateGeneralNote(
    String text, {
    required Set<String> mentionedProfileIds,
    required int expectedGeneralNoteVersion,
  }) async {
    final detail = _startMutable();
    if (detail == null) return ActiveListMutationOutcome.failed;
    final normalized = normalizeGeneralNoteText(text);
    final participantById = {
      for (final participant in detail.participants)
        participant.profileId: participant,
    };
    final canonicalMentionIds = mentionedProfileIds.toList()..sort();
    if (normalized.runes.length > generalNoteMaximumCodePoints ||
        canonicalMentionIds.length > 20 ||
        expectedGeneralNoteVersion < 1 ||
        canonicalMentionIds.any((id) => !participantById.containsKey(id)) ||
        canonicalMentionIds.any(
          (id) => !containsGeneralNoteMentionToken(
            normalized,
            participantById[id]!.username,
          ),
        )) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
    }
    return _run(
      () => _repository.updateGeneralNote(
        listId,
        normalized,
        mentionedProfileIds: canonicalMentionIds,
        expectedGeneralNoteVersion: expectedGeneralNoteVersion,
      ),
      ActiveListDetailMessage.noteSaved,
      reconcileInvalid: true,
    );
  }

  Future<ActiveListMutationOutcome> updateItem(
    ActiveListItem item,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    Set<String>? assigneeProfileIds,
  }) async {
    final detail = _startMutable();
    final normalized = name.trim();
    if (detail == null) return ActiveListMutationOutcome.failed;
    if (normalized.isEmpty || normalized.length > 120) {
      _finish(ActiveListDetailMessage.invalidInput);
      return ActiveListMutationOutcome.invalid;
    }
    final assigneeIds = _validatedAssigneeIds(
      detail,
      assigneeProfileIds ??
          item.assignees.map((assignee) => assignee.profileId).toSet(),
    );
    if (assigneeIds == null) {
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
        assigneeProfileIds: assigneeIds,
        expectedListVersion: detail.summary.version,
        expectedItemVersion: item.version,
      ),
      ActiveListDetailMessage.itemUpdated,
      reconcileInvalid: true,
    );
  }

  List<String>? _validatedAssigneeIds(
    ActiveListDetail detail,
    Set<String> selectedIds,
  ) {
    final currentParticipantIds =
        detail.participants.map((participant) => participant.profileId).toSet();
    if (selectedIds.length > 20 ||
        !currentParticipantIds.containsAll(selectedIds)) {
      return null;
    }
    return selectedIds.toList(growable: false)..sort();
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

  Future<ActiveListMutationOutcome> leaveList() async {
    final detail = state.detail.valueOrNull;
    final accessVersion = detail?.summary.callerAccessVersion;
    if (detail == null ||
        detail.summary.isOwner ||
        accessVersion == null ||
        state.isMutating) {
      return ActiveListMutationOutcome.unavailable;
    }
    _markMutating();
    try {
      await _repository
          .leaveList(listId, expectedAccessVersion: accessVersion)
          .timeout(_requestTimeout);
      if (!mounted) return ActiveListMutationOutcome.failed;
      _finish(ActiveListDetailMessage.left);
      _invalidateLists();
      return ActiveListMutationOutcome.succeeded;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _handleFailure(failure);
    } catch (_) {
      if (!mounted) return ActiveListMutationOutcome.failed;
      return _beginUncertainRecovery();
    }
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
    _mutationCompleted = Completer<void>();
    state = ActiveListDetailState(
      detail: state.detail,
      isMutating: true,
    );
  }

  Future<ActiveListMutationOutcome> _run(
    Future<Object?> Function() mutation,
    ActiveListDetailMessage successMessage, {
    bool reconcileInvalid = false,
  }) async {
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
      if (reconcileInvalid && failure.code == ActiveListFailureCode.invalid) {
        return _beginStaleRecovery(ActiveListDetailMessage.staleRefreshed);
      }
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
      case ActiveListFailureCode.capacity:
        return _finishWithOutcome(
          ActiveListDetailMessage.itemCapacity,
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
    _mutationCompleted?.complete();
    _mutationCompleted = null;
  }

  @override
  void dispose() {
    _mutationCompleted?.complete();
    _mutationCompleted = null;
    super.dispose();
  }

  static void _noop() {}
}
