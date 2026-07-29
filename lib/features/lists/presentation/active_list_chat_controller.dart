import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';

const activeListChatInitialPageSize = 30;

enum ActiveListChatNotice {
  invalidMessage,
  sendUncertain,
  rateLimited,
  requestConflict,
  archivedReadOnly,
  unavailable,
  operationFailed,
  refreshFailed,
  olderPageFailed,
  deleteUncertain,
}

enum ActiveListChatSendOutcome {
  sent,
  invalid,
  uncertain,
  rateLimited,
  requestConflict,
  archived,
  unavailable,
  failed,
  busy,
}

class ActiveListChatState {
  const ActiveListChatState({
    required this.messages,
    this.hasMore = false,
    this.nextBeforeMessagePosition,
    this.isRefreshing = false,
    this.isLoadingOlder = false,
    this.isSending = false,
    this.isMarkingRead = false,
    this.deletingMessageIds = const {},
    this.notice,
  });

  const ActiveListChatState.loading()
      : messages = const AsyncLoading(),
        hasMore = false,
        nextBeforeMessagePosition = null,
        isRefreshing = false,
        isLoadingOlder = false,
        isSending = false,
        isMarkingRead = false,
        deletingMessageIds = const {},
        notice = null;

  final AsyncValue<List<ActiveListChatMessage>> messages;
  final bool hasMore;
  final int? nextBeforeMessagePosition;
  final bool isRefreshing;
  final bool isLoadingOlder;
  final bool isSending;
  final bool isMarkingRead;
  final Set<String> deletingMessageIds;
  final ActiveListChatNotice? notice;

  ActiveListChatState copyWith({
    AsyncValue<List<ActiveListChatMessage>>? messages,
    bool? hasMore,
    int? nextBeforeMessagePosition,
    bool clearNextBeforeMessagePosition = false,
    bool? isRefreshing,
    bool? isLoadingOlder,
    bool? isSending,
    bool? isMarkingRead,
    Set<String>? deletingMessageIds,
    ActiveListChatNotice? notice,
    bool clearNotice = false,
  }) {
    return ActiveListChatState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      nextBeforeMessagePosition: clearNextBeforeMessagePosition
          ? null
          : nextBeforeMessagePosition ?? this.nextBeforeMessagePosition,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isSending: isSending ?? this.isSending,
      isMarkingRead: isMarkingRead ?? this.isMarkingRead,
      deletingMessageIds: deletingMessageIds ?? this.deletingMessageIds,
      notice: clearNotice ? null : notice ?? this.notice,
    );
  }
}

class ActiveListChatController extends StateNotifier<ActiveListChatState> {
  ActiveListChatController(
    this._repository,
    this.listId, {
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
    Future<void> Function()? refreshUnread,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _requestIdGenerator = requestIdGenerator,
        _refreshUnread = refreshUnread ?? _noopAsync,
        _requestTimeout = requestTimeout,
        assert(requestTimeout > Duration.zero),
        super(const ActiveListChatState.loading());

  final ActiveListChatRepository _repository;
  final String listId;
  final CreationRequestIdGenerator _requestIdGenerator;
  final Future<void> Function() _refreshUnread;
  final Duration _requestTimeout;

  int _loadGeneration = 0;
  Completer<void>? _mutationCompleted;
  Completer<void>? _paginationCompleted;
  String? _pendingSendBody;
  String? _pendingSendRequestId;
  int _lastMarkedPosition = 0;
  ActiveListChatMessage? _pendingReadTarget;
  bool _readRunning = false;
  bool _loadRunning = false;
  bool _reconciliationRunning = false;
  bool _reconciliationPending = false;

  String? get pendingSendBody => _pendingSendBody;

  Future<void> load() async {
    if (_loadRunning) return;
    await _waitForExclusiveOperations();
    if (!mounted || _loadRunning) return;
    _loadRunning = true;
    final generation = ++_loadGeneration;
    final existing = state.messages.valueOrNull;
    if (existing == null) {
      state = const ActiveListChatState.loading();
    } else {
      state = state.copyWith(isRefreshing: true, clearNotice: true);
    }
    try {
      final page = await _repository
          .listMessages(
            listId,
            pageSize: activeListChatInitialPageSize,
          )
          .timeout(_requestTimeout);
      if (!mounted || generation != _loadGeneration) return;
      final chronological = _validatedChronological(page.messages);
      state = state.copyWith(
        messages: AsyncData(chronological),
        hasMore: page.hasMore,
        nextBeforeMessagePosition: page.nextBeforeMessagePosition,
        clearNextBeforeMessagePosition: !page.hasMore,
        isRefreshing: false,
        clearNotice: true,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        messages: existing == null
            ? AsyncError(error, stackTrace)
            : AsyncData(existing),
        isRefreshing: false,
        notice: _noticeFor(error, refresh: true),
      );
    } finally {
      _loadRunning = false;
    }
  }

  Future<void> reconcile() async {
    await _waitForExclusiveOperations();
    if (!mounted) return;
    if (_reconciliationRunning) {
      _reconciliationPending = true;
      return;
    }
    _reconciliationRunning = true;
    try {
      do {
        _reconciliationPending = false;
        await _reconcileOnce();
      } while (mounted && _reconciliationPending);
    } finally {
      _reconciliationRunning = false;
    }
  }

  Future<void> _reconcileOnce() async {
    final existing = state.messages.valueOrNull;
    if (existing == null) {
      await load();
      return;
    }
    final generation = ++_loadGeneration;
    state = state.copyWith(isRefreshing: true, clearNotice: true);
    try {
      final refreshedNewestFirst = <ActiveListChatMessage>[];
      int? before;
      var hasMore = false;
      final oldestLoadedPosition =
          existing.isEmpty ? null : existing.first.messagePosition;
      do {
        final page = await _repository
            .listMessages(
              listId,
              pageSize: activeListChatMaximumPageSize,
              beforeMessagePosition: before,
            )
            .timeout(_requestTimeout);
        refreshedNewestFirst.addAll(page.messages);
        hasMore = page.hasMore;
        before = page.nextBeforeMessagePosition;
        if (!hasMore ||
            oldestLoadedPosition == null ||
            refreshedNewestFirst.last.messagePosition <= oldestLoadedPosition) {
          break;
        }
      } while (true);
      if (!mounted || generation != _loadGeneration) return;
      final merged = _mergeAuthoritativeWindow(
        existing,
        refreshedNewestFirst,
      );
      final retainedOlder = refreshedNewestFirst.isNotEmpty &&
          existing.isNotEmpty &&
          existing.first.messagePosition <
              refreshedNewestFirst.last.messagePosition;
      state = state.copyWith(
        messages: AsyncData(merged),
        hasMore: retainedOlder ? state.hasMore : hasMore,
        nextBeforeMessagePosition:
            retainedOlder ? state.nextBeforeMessagePosition : before,
        clearNextBeforeMessagePosition: !retainedOlder && !hasMore,
        isRefreshing: false,
        clearNotice: true,
      );
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        messages: AsyncData(existing),
        isRefreshing: false,
        notice: _noticeFor(error, refresh: true),
      );
    }
  }

  Future<void> loadOlder() async {
    final existing = state.messages.valueOrNull;
    final before = state.nextBeforeMessagePosition;
    if (existing == null ||
        state.isLoadingOlder ||
        state.isRefreshing ||
        _mutationCompleted != null ||
        _reconciliationRunning ||
        !state.hasMore ||
        before == null) {
      return;
    }
    final pagination = Completer<void>();
    _paginationCompleted = pagination;
    state = state.copyWith(isLoadingOlder: true, clearNotice: true);
    try {
      final page = await _repository
          .listMessages(
            listId,
            pageSize: activeListChatMaximumPageSize,
            beforeMessagePosition: before,
          )
          .timeout(_requestTimeout);
      if (!mounted) return;
      final older = _validatedChronological(page.messages);
      final current = state.messages.valueOrNull ?? existing;
      final merged = _mergePages(older, current);
      state = state.copyWith(
        messages: AsyncData(merged),
        hasMore: page.hasMore,
        nextBeforeMessagePosition: page.nextBeforeMessagePosition,
        clearNextBeforeMessagePosition: !page.hasMore,
        isLoadingOlder: false,
        clearNotice: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingOlder: false,
        notice: ActiveListChatNotice.olderPageFailed,
      );
    } finally {
      if (identical(_paginationCompleted, pagination)) {
        _paginationCompleted = null;
      }
      if (!pagination.isCompleted) pagination.complete();
    }
  }

  Future<ActiveListChatSendOutcome> send(String rawBody) async {
    final normalized = normalizeActiveListChatBody(rawBody);
    if (!isValidActiveListChatBody(normalized)) {
      state = state.copyWith(notice: ActiveListChatNotice.invalidMessage);
      return ActiveListChatSendOutcome.invalid;
    }
    if (state.isSending ||
        _loadRunning ||
        state.isRefreshing ||
        state.isLoadingOlder ||
        _mutationCompleted != null ||
        _reconciliationRunning) {
      return ActiveListChatSendOutcome.busy;
    }

    final requestId = _pendingSendBody == normalized
        ? _pendingSendRequestId!
        : _requestIdGenerator();
    _pendingSendBody = normalized;
    _pendingSendRequestId = requestId;
    final mutation = Completer<void>();
    _mutationCompleted = mutation;
    state = state.copyWith(isSending: true, clearNotice: true);
    try {
      final message = await _repository
          .sendMessage(listId, normalized, requestId: requestId)
          .timeout(_requestTimeout);
      if (!mounted) return ActiveListChatSendOutcome.sent;
      final existing = state.messages.valueOrNull ?? const [];
      final merged = _mergePages(existing, [message]);
      _pendingSendBody = null;
      _pendingSendRequestId = null;
      state = state.copyWith(
        messages: AsyncData(merged),
        isSending: false,
        clearNotice: true,
      );
      await _refreshUnreadSafely();
      return ActiveListChatSendOutcome.sent;
    } catch (error) {
      if (!mounted) return ActiveListChatSendOutcome.failed;
      final failure = _failureCode(error);
      final uncertain = error is TimeoutException ||
          failure == ActiveListChatFailureCode.transport;
      if (!uncertain) {
        _pendingSendBody = null;
        _pendingSendRequestId = null;
      }
      final notice = switch (failure) {
        ActiveListChatFailureCode.invalid =>
          ActiveListChatNotice.invalidMessage,
        ActiveListChatFailureCode.unavailable =>
          ActiveListChatNotice.unavailable,
        ActiveListChatFailureCode.requestConflict =>
          ActiveListChatNotice.requestConflict,
        ActiveListChatFailureCode.archived =>
          ActiveListChatNotice.archivedReadOnly,
        ActiveListChatFailureCode.rateLimited =>
          ActiveListChatNotice.rateLimited,
        ActiveListChatFailureCode.transport =>
          ActiveListChatNotice.sendUncertain,
        ActiveListChatFailureCode.generic => uncertain
            ? ActiveListChatNotice.sendUncertain
            : ActiveListChatNotice.operationFailed,
      };
      state = state.copyWith(isSending: false, notice: notice);
      return switch (notice) {
        ActiveListChatNotice.sendUncertain =>
          ActiveListChatSendOutcome.uncertain,
        ActiveListChatNotice.rateLimited =>
          ActiveListChatSendOutcome.rateLimited,
        ActiveListChatNotice.requestConflict =>
          ActiveListChatSendOutcome.requestConflict,
        ActiveListChatNotice.archivedReadOnly =>
          ActiveListChatSendOutcome.archived,
        ActiveListChatNotice.unavailable =>
          ActiveListChatSendOutcome.unavailable,
        ActiveListChatNotice.invalidMessage =>
          ActiveListChatSendOutcome.invalid,
        _ => ActiveListChatSendOutcome.failed,
      };
    } finally {
      if (identical(_mutationCompleted, mutation)) {
        _mutationCompleted = null;
      }
      if (!mutation.isCompleted) mutation.complete();
    }
  }

  Future<void> delete(
    ActiveListChatMessage message, {
    required bool isOwner,
  }) async {
    if (message.isDeleted ||
        (!message.isMine && !isOwner) ||
        _loadRunning ||
        state.isRefreshing ||
        state.isLoadingOlder ||
        _mutationCompleted != null ||
        _reconciliationRunning ||
        state.deletingMessageIds.contains(message.id)) {
      return;
    }
    final mutation = Completer<void>();
    _mutationCompleted = mutation;
    state = state.copyWith(
      deletingMessageIds: {...state.deletingMessageIds, message.id},
      clearNotice: true,
    );
    try {
      final deleted = await _repository
          .deleteMessage(listId, message.id)
          .timeout(_requestTimeout);
      if (!mounted) return;
      final existing = state.messages.valueOrNull ?? const [];
      state = state.copyWith(
        messages: AsyncData(_mergePages(existing, [deleted])),
        deletingMessageIds: {
          for (final id in state.deletingMessageIds)
            if (id != message.id) id,
        },
        clearNotice: true,
      );
      await _refreshUnreadSafely();
    } catch (error) {
      if (!mounted) return;
      final failure = _failureCode(error);
      final uncertain = error is TimeoutException ||
          failure == ActiveListChatFailureCode.transport;
      state = state.copyWith(
        deletingMessageIds: {
          for (final id in state.deletingMessageIds)
            if (id != message.id) id,
        },
        notice: uncertain ? null : _noticeFor(error),
        clearNotice: uncertain,
      );
      if (uncertain) {
        unawaited(_reconcileAfterUncertainDeletion());
      }
    } finally {
      if (identical(_mutationCompleted, mutation)) {
        _mutationCompleted = null;
      }
      if (!mutation.isCompleted) mutation.complete();
    }
  }

  void markReadThrough(ActiveListChatMessage message) {
    if (message.messagePosition <= _lastMarkedPosition) return;
    final pending = _pendingReadTarget;
    if (pending == null || message.messagePosition > pending.messagePosition) {
      _pendingReadTarget = message;
    }
    if (!_readRunning) unawaited(_drainReadMarks());
  }

  Future<void> _drainReadMarks() async {
    if (_readRunning) return;
    _readRunning = true;
    if (mounted) state = state.copyWith(isMarkingRead: true);
    try {
      while (mounted && _pendingReadTarget != null) {
        final target = _pendingReadTarget!;
        _pendingReadTarget = null;
        try {
          final result = await _repository
              .markRead(listId, target.id)
              .timeout(_requestTimeout);
          if (!mounted) return;
          if (result.lastReadMessagePosition > _lastMarkedPosition) {
            _lastMarkedPosition = result.lastReadMessagePosition;
          }
          if (result.changed) await _refreshUnread();
        } catch (error) {
          if (!mounted) return;
          state = state.copyWith(notice: _noticeFor(error));
        }
      }
    } finally {
      _readRunning = false;
      if (mounted) state = state.copyWith(isMarkingRead: false);
    }
  }

  void clearNotice() {
    if (state.notice != null) state = state.copyWith(clearNotice: true);
  }

  Future<void> _reconcileAfterUncertainDeletion() async {
    await reconcile();
    if (mounted && state.notice == null) {
      state = state.copyWith(notice: ActiveListChatNotice.deleteUncertain);
    }
  }

  Future<void> _waitForExclusiveOperations() async {
    while (mounted) {
      final mutation = _mutationCompleted;
      final pagination = _paginationCompleted;
      if (mutation == null && pagination == null) return;
      await Future.wait([
        if (mutation != null) mutation.future,
        if (pagination != null) pagination.future,
      ]);
    }
  }

  Future<void> _refreshUnreadSafely() async {
    try {
      await _refreshUnread();
    } catch (_) {
      // A confirmed Chat mutation remains confirmed. The scoped account
      // invalidation and the next resume/manual refresh retry the badge.
    }
  }

  List<ActiveListChatMessage> _mergeAuthoritativeWindow(
    List<ActiveListChatMessage> existing,
    List<ActiveListChatMessage> refreshedNewestFirst,
  ) {
    if (refreshedNewestFirst.isEmpty) return const [];
    final refreshed = _validatedChronological(refreshedNewestFirst);
    final existingById = {
      for (final message in existing) message.id: message,
    };
    final existingIdByPosition = {
      for (final message in existing) message.messagePosition: message.id,
    };
    for (final message in refreshed) {
      final previous = existingById[message.id];
      if (previous != null) _validateCompatible(previous, message);
      final previousId = existingIdByPosition[message.messagePosition];
      if (previousId != null && previousId != message.id) {
        throw const FormatException('conflicting Chat message position');
      }
    }
    final firstCoveredPosition = refreshed.first.messagePosition;
    final retained = existing
        .where((message) => message.messagePosition < firstCoveredPosition)
        .toList(growable: false);
    return _mergePages(retained, refreshed);
  }

  List<ActiveListChatMessage> _mergePages(
    Iterable<ActiveListChatMessage> first,
    Iterable<ActiveListChatMessage> second,
  ) {
    final byId = <String, ActiveListChatMessage>{};
    final idByPosition = <int, String>{};
    for (final message in [...first, ...second]) {
      final positionId = idByPosition[message.messagePosition];
      if (positionId != null && positionId != message.id) {
        throw const FormatException('conflicting Chat message position');
      }
      final previous = byId[message.id];
      if (previous != null) {
        _validateCompatible(previous, message);
      }
      byId[message.id] = message;
      idByPosition[message.messagePosition] = message.id;
    }
    final result = byId.values.toList()
      ..sort(
        (left, right) => left.messagePosition.compareTo(right.messagePosition),
      );
    return List.unmodifiable(result);
  }

  List<ActiveListChatMessage> _validatedChronological(
    Iterable<ActiveListChatMessage> newestFirst,
  ) {
    return _mergePages(const [], newestFirst);
  }

  void _validateCompatible(
    ActiveListChatMessage previous,
    ActiveListChatMessage current,
  ) {
    if (previous.messagePosition != current.messagePosition ||
        previous.createdAt != current.createdAt ||
        previous.isMine != current.isMine ||
        (previous.isDeleted && !current.isDeleted) ||
        (previous.isDeleted &&
            previous.deletionKind != current.deletionKind &&
            current.deletionKind != ActiveListChatDeletionKind.account) ||
        (previous.deletionKind == ActiveListChatDeletionKind.account &&
            current.deletionKind != ActiveListChatDeletionKind.account) ||
        (!previous.isDeleted &&
            !current.isDeleted &&
            previous.body != current.body)) {
      throw const FormatException('conflicting Chat message identity');
    }
  }

  ActiveListChatNotice _noticeFor(
    Object error, {
    bool refresh = false,
  }) {
    return switch (_failureCode(error)) {
      ActiveListChatFailureCode.unavailable => ActiveListChatNotice.unavailable,
      ActiveListChatFailureCode.archived =>
        ActiveListChatNotice.archivedReadOnly,
      ActiveListChatFailureCode.rateLimited => ActiveListChatNotice.rateLimited,
      ActiveListChatFailureCode.requestConflict =>
        ActiveListChatNotice.requestConflict,
      _ => refresh
          ? ActiveListChatNotice.refreshFailed
          : ActiveListChatNotice.operationFailed,
    };
  }

  ActiveListChatFailureCode _failureCode(Object error) {
    if (error is ActiveListChatFailure) return error.code;
    if (error is TimeoutException) return ActiveListChatFailureCode.transport;
    return ActiveListChatFailureCode.generic;
  }

  static Future<void> _noopAsync() async {}
}

class ActiveListChatUnreadController
    extends StateNotifier<AsyncValue<ActiveListChatUnreadCount>> {
  ActiveListChatUnreadController(
    this._repository,
    this.listId, {
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _requestTimeout = requestTimeout,
        super(const AsyncLoading());

  final ActiveListChatRepository _repository;
  final String listId;
  final Duration _requestTimeout;
  int _generation = 0;

  Future<void> load() => _load(preserveExisting: false);

  Future<void> reconcile() => _load(preserveExisting: true);

  Future<void> _load({required bool preserveExisting}) async {
    final generation = ++_generation;
    final existing = state.valueOrNull;
    if (existing == null && !preserveExisting) {
      state = const AsyncLoading();
    }
    try {
      final count =
          await _repository.getUnreadCount(listId).timeout(_requestTimeout);
      if (!mounted || generation != _generation) return;
      state = AsyncData(count);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      if (existing == null) {
        state = AsyncError(error, stackTrace);
      }
    }
  }
}
