import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';

const activeListPageSize = 20;

enum ActiveListsMessage { created, invalidTitle, stale, operationFailed }

class ActiveListsState {
  const ActiveListsState({
    required this.activeLists,
    required this.archivedLists,
    this.activeCursor,
    this.archivedCursor,
    this.activeHasMore = false,
    this.archivedHasMore = false,
    this.loadingMoreStatus,
    this.isCreating = false,
    this.message,
  });

  const ActiveListsState.loading()
      : activeLists = const AsyncLoading(),
        archivedLists = const AsyncLoading(),
        activeCursor = null,
        archivedCursor = null,
        activeHasMore = false,
        archivedHasMore = false,
        loadingMoreStatus = null,
        isCreating = false,
        message = null;

  final AsyncValue<List<ActiveListSummary>> activeLists;
  final AsyncValue<List<ActiveListSummary>> archivedLists;
  final ActiveListCursor? activeCursor;
  final ActiveListCursor? archivedCursor;
  final bool activeHasMore;
  final bool archivedHasMore;
  final ActiveListStatus? loadingMoreStatus;
  final bool isCreating;
  final ActiveListsMessage? message;

  AsyncValue<List<ActiveListSummary>> listsFor(ActiveListStatus status) =>
      status == ActiveListStatus.active ? activeLists : archivedLists;

  bool hasMoreFor(ActiveListStatus status) =>
      status == ActiveListStatus.active ? activeHasMore : archivedHasMore;
}

class ActiveListsController extends StateNotifier<ActiveListsState> {
  ActiveListsController(
    this._repository, {
    required bool hasAuthenticatedUser,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        _requestIdGenerator = requestIdGenerator,
        super(const ActiveListsState.loading());

  final ActiveListRepository _repository;
  final bool _hasAuthenticatedUser;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _loadGeneration = 0;
  bool _reconciliationPending = false;
  String? _pendingCreateTitle;
  String? _pendingCreateRequestId;

  Future<void> loadAll() async {
    if (!_hasAuthenticatedUser) return;
    final generation = ++_loadGeneration;
    state = const ActiveListsState.loading();
    try {
      final pages = await Future.wait([
        _repository.listLists(
          status: ActiveListStatus.active,
          limit: activeListPageSize,
        ),
        _repository.listLists(
          status: ActiveListStatus.archived,
          limit: activeListPageSize,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final active = pages[0];
      final archived = pages[1];
      state = ActiveListsState(
        activeLists: AsyncData(active.lists),
        archivedLists: AsyncData(archived.lists),
        activeCursor: active.nextCursor,
        archivedCursor: archived.nextCursor,
        activeHasMore: active.hasMore,
        archivedHasMore: archived.hasMore,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      state = ActiveListsState(
        activeLists: AsyncError(error, stackTrace),
        archivedLists: AsyncError(error, stackTrace),
        message: ActiveListsMessage.operationFailed,
      );
    }
  }

  Future<void> reconcile() async {
    if (!_hasAuthenticatedUser) return;
    if (state.isCreating || state.loadingMoreStatus != null) {
      _reconciliationPending = true;
      return;
    }
    _reconciliationPending = false;
    final generation = ++_loadGeneration;
    try {
      final pages = await Future.wait([
        _repository.listLists(
          status: ActiveListStatus.active,
          limit: activeListPageSize,
        ),
        _repository.listLists(
          status: ActiveListStatus.archived,
          limit: activeListPageSize,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      state = ActiveListsState(
        activeLists: AsyncData(pages[0].lists),
        archivedLists: AsyncData(pages[1].lists),
        activeCursor: pages[0].nextCursor,
        archivedCursor: pages[1].nextCursor,
        activeHasMore: pages[0].hasMore,
        archivedHasMore: pages[1].hasMore,
        message: state.message,
      );
    } catch (_) {
      // Realtime is best-effort: retain usable cached projections and manual
      // refresh when a background reconciliation fails.
    }
  }

  Future<void> refresh(ActiveListStatus status) async {
    if (!_hasAuthenticatedUser || state.loadingMoreStatus != null) return;
    final generation = ++_loadGeneration;
    try {
      final page = await _repository.listLists(
        status: status,
        limit: activeListPageSize,
      );
      if (!mounted || generation != _loadGeneration) return;
      state = _replaceStatus(state, status, page);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = ActiveListsState(
        activeLists: state.activeLists,
        archivedLists: state.archivedLists,
        activeCursor: state.activeCursor,
        archivedCursor: state.archivedCursor,
        activeHasMore: state.activeHasMore,
        archivedHasMore: state.archivedHasMore,
        message: ActiveListsMessage.operationFailed,
      );
    }
  }

  Future<void> loadMore(ActiveListStatus status) async {
    final current = state.listsFor(status).valueOrNull;
    final cursor = status == ActiveListStatus.active
        ? state.activeCursor
        : state.archivedCursor;
    if (current == null ||
        cursor == null ||
        !state.hasMoreFor(status) ||
        state.loadingMoreStatus != null) {
      return;
    }

    state = ActiveListsState(
      activeLists: state.activeLists,
      archivedLists: state.archivedLists,
      activeCursor: state.activeCursor,
      archivedCursor: state.archivedCursor,
      activeHasMore: state.activeHasMore,
      archivedHasMore: state.archivedHasMore,
      loadingMoreStatus: status,
    );
    try {
      final page = await _repository.listLists(
        status: status,
        limit: activeListPageSize,
        before: cursor,
      );
      if (!mounted) return;
      final knownIds = current.map((list) => list.id).toSet();
      final combined = [
        ...current,
        ...page.lists.where((list) => knownIds.add(list.id)),
      ];
      state = _replaceStatus(
        state,
        status,
        ActiveListPage(lists: combined, hasMore: page.hasMore),
      );
      _drainReconciliation();
    } catch (_) {
      if (!mounted) return;
      state = ActiveListsState(
        activeLists: state.activeLists,
        archivedLists: state.archivedLists,
        activeCursor: state.activeCursor,
        archivedCursor: state.archivedCursor,
        activeHasMore: state.activeHasMore,
        archivedHasMore: state.archivedHasMore,
        message: ActiveListsMessage.operationFailed,
      );
      _drainReconciliation();
    }
  }

  Future<bool> create(String title) async {
    if (state.isCreating) return false;
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      _setMessage(ActiveListsMessage.invalidTitle);
      return false;
    }
    state = ActiveListsState(
      activeLists: state.activeLists,
      archivedLists: state.archivedLists,
      activeCursor: state.activeCursor,
      archivedCursor: state.archivedCursor,
      activeHasMore: state.activeHasMore,
      archivedHasMore: state.archivedHasMore,
      isCreating: true,
    );
    try {
      final requestId = _pendingCreateTitle == normalized
          ? _pendingCreateRequestId!
          : _requestIdGenerator();
      _pendingCreateTitle = normalized;
      _pendingCreateRequestId = requestId;
      await _repository.createList(normalized, requestId: requestId);
      if (!mounted) return false;
      _pendingCreateTitle = null;
      _pendingCreateRequestId = null;
      await refresh(ActiveListStatus.active);
      if (!mounted) return false;
      _setMessage(ActiveListsMessage.created);
      return true;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return false;
      _setMessage(
        failure.code == ActiveListFailureCode.invalid
            ? ActiveListsMessage.invalidTitle
            : ActiveListsMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (mounted) _setMessage(ActiveListsMessage.operationFailed);
      return false;
    }
  }

  ActiveListsState _replaceStatus(
    ActiveListsState current,
    ActiveListStatus status,
    ActiveListPage page,
  ) {
    return ActiveListsState(
      activeLists: status == ActiveListStatus.active
          ? AsyncData(page.lists)
          : current.activeLists,
      archivedLists: status == ActiveListStatus.archived
          ? AsyncData(page.lists)
          : current.archivedLists,
      activeCursor: status == ActiveListStatus.active
          ? page.nextCursor
          : current.activeCursor,
      archivedCursor: status == ActiveListStatus.archived
          ? page.nextCursor
          : current.archivedCursor,
      activeHasMore: status == ActiveListStatus.active
          ? page.hasMore
          : current.activeHasMore,
      archivedHasMore: status == ActiveListStatus.archived
          ? page.hasMore
          : current.archivedHasMore,
    );
  }

  void _setMessage(ActiveListsMessage message) {
    state = ActiveListsState(
      activeLists: state.activeLists,
      archivedLists: state.archivedLists,
      activeCursor: state.activeCursor,
      archivedCursor: state.archivedCursor,
      activeHasMore: state.activeHasMore,
      archivedHasMore: state.archivedHasMore,
      message: message,
    );
    _drainReconciliation();
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted) return;
    _reconciliationPending = false;
    unawaited(reconcile());
  }
}
