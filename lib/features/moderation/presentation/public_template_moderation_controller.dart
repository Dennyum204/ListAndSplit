import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

enum ModerationMessage {
  dismissed,
  takenDown,
  restored,
  staleRefreshed,
  accessRevoked,
  operationFailed,
}

class ModerationAccessController extends StateNotifier<AsyncValue<bool>> {
  ModerationAccessController(
    this._repository, {
    required bool hasAuthenticatedUser,
  }) : super(
          hasAuthenticatedUser ? const AsyncLoading() : const AsyncData(false),
        );

  final PublicTemplateModerationRepository _repository;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final allowed = await _repository.isModerator();
      if (!mounted || generation != _generation) return;
      state = AsyncData(allowed);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> reconcile() => load();
}

class ModerationQueueState {
  const ModerationQueueState({
    required this.page,
    required this.filter,
    this.isLoadingMore = false,
    this.message,
  });

  const ModerationQueueState.loading(this.filter)
      : page = const AsyncLoading(),
        isLoadingMore = false,
        message = null;

  final AsyncValue<ModerationQueuePage> page;
  final ModerationQueueFilter filter;
  final bool isLoadingMore;
  final ModerationMessage? message;

  ModerationQueueState copyWith({
    AsyncValue<ModerationQueuePage>? page,
    ModerationQueueFilter? filter,
    bool? isLoadingMore,
    ModerationMessage? message,
    bool clearMessage = false,
  }) {
    return ModerationQueueState(
      page: page ?? this.page,
      filter: filter ?? this.filter,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class ModerationQueueController extends StateNotifier<ModerationQueueState> {
  ModerationQueueController(
    this._repository, {
    required this.hasAuthenticatedUser,
  }) : super(
          const ModerationQueueState.loading(ModerationQueueFilter.open),
        );

  final PublicTemplateModerationRepository _repository;
  final bool hasAuthenticatedUser;
  int _generation = 0;

  Future<void> load() async {
    if (!hasAuthenticatedUser) return;
    final generation = ++_generation;
    final filter = state.filter;
    final cached = state.page.valueOrNull;
    if (cached == null || cached.filter != filter) {
      state = ModerationQueueState.loading(filter);
    } else {
      state = state.copyWith(clearMessage: true);
    }
    try {
      final page = await _repository.listQueue(filter);
      if (!mounted || generation != _generation || filter != state.filter) {
        return;
      }
      state = ModerationQueueState(page: AsyncData(page), filter: filter);
    } on PublicTemplateModerationFailure catch (failure, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = ModerationQueueState(
        page: cached == null ||
                failure.code == PublicTemplateModerationFailureCode.revoked
            ? AsyncError(failure, stackTrace)
            : AsyncData(cached),
        filter: filter,
        message: _messageFor(failure),
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = ModerationQueueState(
        page:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        filter: filter,
        message: ModerationMessage.operationFailed,
      );
    }
  }

  Future<void> selectFilter(ModerationQueueFilter filter) async {
    if (filter == state.filter || state.isLoadingMore) return;
    state = ModerationQueueState.loading(filter);
    await load();
  }

  Future<void> loadMore() async {
    final current = state.page.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || state.isLoadingMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearMessage: true);
    try {
      final next = await _repository.listQueue(
        state.filter,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      final ids = current.cases.map((entry) => entry.groupId).toSet();
      state = state.copyWith(
        page: AsyncData(
          ModerationQueuePage(
            filter: current.filter,
            cases: [
              ...current.cases,
              ...next.cases.where((entry) => ids.add(entry.groupId)),
            ],
            nextCursor: next.nextCursor,
          ),
        ),
        isLoadingMore: false,
      );
    } on PublicTemplateModerationFailure catch (failure, stackTrace) {
      if (!mounted) return;
      state = failure.code == PublicTemplateModerationFailureCode.revoked
          ? ModerationQueueState(
              page: AsyncError(failure, stackTrace),
              filter: state.filter,
              message: ModerationMessage.accessRevoked,
            )
          : state.copyWith(
              isLoadingMore: false,
              message: _messageFor(failure),
            );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isLoadingMore: false,
          message: ModerationMessage.operationFailed,
        );
      }
    }
  }

  Future<void> reconcile() => load();
}

class ModerationCaseState {
  const ModerationCaseState({
    required this.detail,
    this.isMutating = false,
    this.message,
  });

  const ModerationCaseState.loading()
      : detail = const AsyncLoading(),
        isMutating = false,
        message = null;

  final AsyncValue<PublicTemplateModerationCase> detail;
  final bool isMutating;
  final ModerationMessage? message;

  ModerationCaseState copyWith({
    AsyncValue<PublicTemplateModerationCase>? detail,
    bool? isMutating,
    ModerationMessage? message,
    bool clearMessage = false,
  }) {
    return ModerationCaseState(
      detail: detail ?? this.detail,
      isMutating: isMutating ?? this.isMutating,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class ModerationCaseController extends StateNotifier<ModerationCaseState> {
  ModerationCaseController(
    this._repository,
    this.groupId, {
    required bool hasAuthenticatedUser,
    required void Function() invalidateQueue,
    required void Function() invalidateOwnerState,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        _invalidateQueue = invalidateQueue,
        _invalidateOwnerState = invalidateOwnerState,
        _requestIdGenerator = requestIdGenerator,
        super(const ModerationCaseState.loading());

  final PublicTemplateModerationRepository _repository;
  final String groupId;
  final bool _hasAuthenticatedUser;
  final void Function() _invalidateQueue;
  final void Function() _invalidateOwnerState;
  final CreationRequestIdGenerator _requestIdGenerator;
  int _generation = 0;
  bool _reconciliationPending = false;
  String? _pendingPayload;
  String? _pendingRequestId;

  Future<void> load() async {
    if (!_hasAuthenticatedUser) return;
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    final generation = ++_generation;
    final cached = state.detail.valueOrNull;
    if (cached == null) {
      state = const ModerationCaseState.loading();
    } else {
      state = state.copyWith(clearMessage: true);
    }
    try {
      final detail = await _repository.getCase(groupId);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: AsyncData(detail),
        clearMessage: true,
      );
    } on PublicTemplateModerationFailure catch (failure, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: cached == null ||
                failure.code == PublicTemplateModerationFailureCode.revoked
            ? AsyncError(failure, stackTrace)
            : AsyncData(cached),
        message: _messageFor(failure),
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: ModerationMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<bool> dismiss(String privateNote) {
    final detail = state.detail.valueOrNull;
    if (detail == null) return Future.value(false);
    return _runAction(
      payload: 'dismiss\u0000${detail.summary.version}\u0000$privateNote',
      operation: (requestId) => _repository.dismiss(
        groupId,
        expectedGroupVersion: detail.summary.version,
        privateNote: privateNote,
        requestId: requestId,
      ),
      successMessage: ModerationMessage.dismissed,
    );
  }

  Future<bool> takeDown(
    PublicTemplateReportReason reason,
    String privateNote,
  ) {
    final detail = state.detail.valueOrNull;
    final current = detail?.currentTemplate;
    if (detail == null || current == null) return Future.value(false);
    return _runAction(
      payload:
          'take_down\u0000${detail.summary.version}\u0000${current.version}'
          '\u0000${reason.wireValue}\u0000$privateNote',
      operation: (requestId) => _repository.takeDown(
        groupId,
        expectedGroupVersion: detail.summary.version,
        expectedTemplateVersion: current.version,
        ownerReason: reason,
        privateNote: privateNote,
        requestId: requestId,
      ),
      successMessage: ModerationMessage.takenDown,
    );
  }

  Future<bool> restore(String privateNote) {
    final detail = state.detail.valueOrNull;
    final current = detail?.currentTemplate;
    final restriction = detail?.restriction;
    if (detail == null || current == null || restriction?.active != true) {
      return Future.value(false);
    }
    return _runAction(
      payload: 'restore\u0000${restriction!.version}\u0000${current.version}'
          '\u0000$privateNote',
      operation: (requestId) => _repository.restore(
        detail.summary.templateId,
        expectedRestrictionVersion: restriction.version,
        expectedTemplateVersion: current.version,
        privateNote: privateNote,
        requestId: requestId,
      ),
      successMessage: ModerationMessage.restored,
    );
  }

  Future<bool> _runAction({
    required String payload,
    required Future<ModerationActionResult> Function(String requestId)
        operation,
    required ModerationMessage successMessage,
  }) async {
    if (state.isMutating) return false;
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingRequestId = _requestIdGenerator();
    }
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      await operation(_pendingRequestId!);
      if (!mounted) return false;
      _clearPending();
      _invalidateQueue();
      _invalidateOwnerState();
      state = state.copyWith(
        isMutating: false,
        message: successMessage,
      );
      await load();
      if (mounted) state = state.copyWith(message: successMessage);
      _drainReconciliation();
      return true;
    } on PublicTemplateModerationFailure catch (failure, stackTrace) {
      if (!mounted) return false;
      final message = _messageFor(failure);
      if (failure.code != PublicTemplateModerationFailureCode.transport) {
        _clearPending();
      }
      state = failure.code == PublicTemplateModerationFailureCode.revoked
          ? ModerationCaseState(
              detail: AsyncError(failure, stackTrace),
              message: message,
            )
          : state.copyWith(isMutating: false, message: message);
      if (failure.code == PublicTemplateModerationFailureCode.stale ||
          failure.code == PublicTemplateModerationFailureCode.unavailable) {
        await load();
        if (mounted) state = state.copyWith(message: message);
      }
      _drainReconciliation();
      return false;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: ModerationMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return false;
    }
  }

  Future<void> reconcile() async {
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  void _clearPending() {
    _pendingPayload = null;
    _pendingRequestId = null;
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

ModerationMessage _messageFor(PublicTemplateModerationFailure failure) {
  return switch (failure.code) {
    PublicTemplateModerationFailureCode.revoked =>
      ModerationMessage.accessRevoked,
    PublicTemplateModerationFailureCode.stale =>
      ModerationMessage.staleRefreshed,
    PublicTemplateModerationFailureCode.invalid ||
    PublicTemplateModerationFailureCode.unavailable ||
    PublicTemplateModerationFailureCode.retryConflict ||
    PublicTemplateModerationFailureCode.transport ||
    PublicTemplateModerationFailureCode.generic =>
      ModerationMessage.operationFailed,
  };
}
