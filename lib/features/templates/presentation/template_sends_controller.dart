import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';

enum TemplateSendMessage {
  sent,
  accepted,
  declined,
  revoked,
  stale,
  unavailable,
  capacity,
  duplicatePending,
  retryConflict,
  operationFailed,
}

enum TemplateSendCollection {
  receivedPending,
  receivedHistory,
  sentPending,
  sentHistory
}

class SharedTemplateSendsData {
  SharedTemplateSendsData({
    required List<ReceivedTemplateSendSummary> receivedPending,
    required List<ReceivedTemplateSendSummary> receivedHistory,
    required List<SentTemplateSendSummary> sentPending,
    required List<SentTemplateSendSummary> sentHistory,
    required this.hasMoreReceivedPending,
    required this.hasMoreReceivedHistory,
    required this.hasMoreSentPending,
    required this.hasMoreSentHistory,
  })  : receivedPending = List.unmodifiable(receivedPending),
        receivedHistory = List.unmodifiable(receivedHistory),
        sentPending = List.unmodifiable(sentPending),
        sentHistory = List.unmodifiable(sentHistory);

  final List<ReceivedTemplateSendSummary> receivedPending;
  final List<ReceivedTemplateSendSummary> receivedHistory;
  final List<SentTemplateSendSummary> sentPending;
  final List<SentTemplateSendSummary> sentHistory;
  final bool hasMoreReceivedPending;
  final bool hasMoreReceivedHistory;
  final bool hasMoreSentPending;
  final bool hasMoreSentHistory;

  bool hasMore(TemplateSendCollection collection) => switch (collection) {
        TemplateSendCollection.receivedPending => hasMoreReceivedPending,
        TemplateSendCollection.receivedHistory => hasMoreReceivedHistory,
        TemplateSendCollection.sentPending => hasMoreSentPending,
        TemplateSendCollection.sentHistory => hasMoreSentHistory,
      };

  SharedTemplateSendsData copyWith({
    List<ReceivedTemplateSendSummary>? receivedPending,
    List<ReceivedTemplateSendSummary>? receivedHistory,
    List<SentTemplateSendSummary>? sentPending,
    List<SentTemplateSendSummary>? sentHistory,
    bool? hasMoreReceivedPending,
    bool? hasMoreReceivedHistory,
    bool? hasMoreSentPending,
    bool? hasMoreSentHistory,
  }) {
    return SharedTemplateSendsData(
      receivedPending: receivedPending ?? this.receivedPending,
      receivedHistory: receivedHistory ?? this.receivedHistory,
      sentPending: sentPending ?? this.sentPending,
      sentHistory: sentHistory ?? this.sentHistory,
      hasMoreReceivedPending:
          hasMoreReceivedPending ?? this.hasMoreReceivedPending,
      hasMoreReceivedHistory:
          hasMoreReceivedHistory ?? this.hasMoreReceivedHistory,
      hasMoreSentPending: hasMoreSentPending ?? this.hasMoreSentPending,
      hasMoreSentHistory: hasMoreSentHistory ?? this.hasMoreSentHistory,
    );
  }
}

class SharedTemplateSendsState {
  const SharedTemplateSendsState({
    required this.data,
    this.loadingMore,
    this.revokingId,
    this.message,
  });

  const SharedTemplateSendsState.loading()
      : data = const AsyncLoading(),
        loadingMore = null,
        revokingId = null,
        message = null;

  final AsyncValue<SharedTemplateSendsData> data;
  final TemplateSendCollection? loadingMore;
  final String? revokingId;
  final TemplateSendMessage? message;

  bool get isBusy => loadingMore != null || revokingId != null;

  SharedTemplateSendsState copyWith({
    AsyncValue<SharedTemplateSendsData>? data,
    TemplateSendCollection? loadingMore,
    bool clearLoadingMore = false,
    String? revokingId,
    bool clearRevoking = false,
    TemplateSendMessage? message,
    bool clearMessage = false,
  }) {
    return SharedTemplateSendsState(
      data: data ?? this.data,
      loadingMore: clearLoadingMore ? null : loadingMore ?? this.loadingMore,
      revokingId: clearRevoking ? null : revokingId ?? this.revokingId,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class SharedTemplateSendsController
    extends StateNotifier<SharedTemplateSendsState> {
  SharedTemplateSendsController(
    this._repository, {
    required bool hasAuthenticatedUser,
    required void Function() invalidateNotifications,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        _invalidateNotifications = invalidateNotifications,
        _requestIdGenerator = requestIdGenerator,
        _requestTimeout = requestTimeout,
        super(const SharedTemplateSendsState.loading());

  static const pageSize = 20;

  final TemplateSendRepository _repository;
  final bool _hasAuthenticatedUser;
  final void Function() _invalidateNotifications;
  final CreationRequestIdGenerator _requestIdGenerator;
  final Duration _requestTimeout;
  int _generation = 0;
  bool _reconciliationPending = false;
  String? _pendingRevokePayload;
  String? _pendingRevokeRequestId;

  Future<void> load() async {
    if (!_hasAuthenticatedUser) return;
    if (state.isBusy) {
      _reconciliationPending = true;
      return;
    }
    final generation = ++_generation;
    final cached = state.data.valueOrNull;
    state = cached == null
        ? const SharedTemplateSendsState.loading()
        : state.copyWith(clearMessage: true);
    try {
      final results = await Future.wait<Object>([
        _repository.listReceived(pageSize: pageSize),
        _repository.listReceived(
          filter: TemplateSendHistoryFilter.history,
          pageSize: pageSize,
        ),
        _repository.listSent(pageSize: pageSize),
        _repository.listSent(
          filter: TemplateSendHistoryFilter.history,
          pageSize: pageSize,
        ),
      ]);
      if (!mounted || generation != _generation) return;
      final receivedPending = results[0] as List<ReceivedTemplateSendSummary>;
      final receivedHistory = results[1] as List<ReceivedTemplateSendSummary>;
      final sentPending = results[2] as List<SentTemplateSendSummary>;
      final sentHistory = results[3] as List<SentTemplateSendSummary>;
      state = state.copyWith(
        data: AsyncData(
          SharedTemplateSendsData(
            receivedPending: receivedPending,
            receivedHistory: receivedHistory,
            sentPending: sentPending,
            sentHistory: sentHistory,
            hasMoreReceivedPending: receivedPending.length == pageSize,
            hasMoreReceivedHistory: receivedHistory.length == pageSize,
            hasMoreSentPending: sentPending.length == pageSize,
            hasMoreSentHistory: sentHistory.length == pageSize,
          ),
        ),
        clearMessage: true,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        data:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: TemplateSendMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<void> reconcile() async {
    if (state.isBusy) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  Future<void> loadMore(TemplateSendCollection collection) async {
    final current = state.data.valueOrNull;
    if (current == null || state.isBusy || !current.hasMore(collection)) {
      return;
    }
    state = state.copyWith(
      loadingMore: collection,
      clearMessage: true,
    );
    try {
      final next = await _loadNextPage(current, collection);
      if (!mounted) return;
      state = state.copyWith(
        data: AsyncData(next),
        clearLoadingMore: true,
        clearMessage: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        clearLoadingMore: true,
        message: TemplateSendMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<SharedTemplateSendsData> _loadNextPage(
    SharedTemplateSendsData current,
    TemplateSendCollection collection,
  ) async {
    switch (collection) {
      case TemplateSendCollection.receivedPending:
        final page = await _repository.listReceived(
          pageSize: pageSize,
          cursor: _receivedCursor(current.receivedPending),
        );
        return current.copyWith(
          receivedPending: _mergeReceived(current.receivedPending, page),
          hasMoreReceivedPending: page.length == pageSize,
        );
      case TemplateSendCollection.receivedHistory:
        final page = await _repository.listReceived(
          filter: TemplateSendHistoryFilter.history,
          pageSize: pageSize,
          cursor: _receivedCursor(current.receivedHistory),
        );
        return current.copyWith(
          receivedHistory: _mergeReceived(current.receivedHistory, page),
          hasMoreReceivedHistory: page.length == pageSize,
        );
      case TemplateSendCollection.sentPending:
        final page = await _repository.listSent(
          pageSize: pageSize,
          cursor: _sentCursor(current.sentPending),
        );
        return current.copyWith(
          sentPending: _mergeSent(current.sentPending, page),
          hasMoreSentPending: page.length == pageSize,
        );
      case TemplateSendCollection.sentHistory:
        final page = await _repository.listSent(
          filter: TemplateSendHistoryFilter.history,
          pageSize: pageSize,
          cursor: _sentCursor(current.sentHistory),
        );
        return current.copyWith(
          sentHistory: _mergeSent(current.sentHistory, page),
          hasMoreSentHistory: page.length == pageSize,
        );
    }
  }

  Future<bool> revoke(SentTemplateSendSummary summary) async {
    if (state.isBusy || summary.state != TemplateSendState.pending) {
      return false;
    }
    final payload = '${summary.id}:${summary.version}:revoke';
    if (_pendingRevokePayload != payload) {
      _pendingRevokePayload = payload;
      _pendingRevokeRequestId = _requestIdGenerator();
    }
    state = state.copyWith(revokingId: summary.id, clearMessage: true);
    try {
      await _repository
          .revoke(
            summary.id,
            expectedVersion: summary.version,
            requestId: _pendingRevokeRequestId!,
          )
          .timeout(_requestTimeout);
      if (!mounted) return false;
      _pendingRevokePayload = null;
      _pendingRevokeRequestId = null;
      _invalidateNotifications();
      state = state.copyWith(
        clearRevoking: true,
        clearMessage: true,
      );
      await load();
      if (mounted) {
        state = state.copyWith(message: TemplateSendMessage.revoked);
      }
      return true;
    } on TemplateSendFailure catch (failure) {
      if (!mounted) return false;
      final message = _messageForFailure(failure.code);
      state = state.copyWith(clearRevoking: true, clearMessage: true);
      if (_shouldRefresh(failure.code)) {
        await load();
      }
      if (mounted) state = state.copyWith(message: message);
      return false;
    } on TimeoutException {
      if (!mounted) return false;
      state = state.copyWith(
        clearRevoking: true,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        clearRevoking: true,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    } finally {
      _drainReconciliation();
    }
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isBusy) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

class TemplateSendComposerState {
  const TemplateSendComposerState({
    required this.recipients,
    this.isSending = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.message,
    this.sentResult,
  });

  const TemplateSendComposerState.loading()
      : recipients = const AsyncLoading(),
        isSending = false,
        isLoadingMore = false,
        hasMore = false,
        message = null,
        sentResult = null;

  final AsyncValue<List<TemplateSendProfile>> recipients;
  final bool isSending;
  final bool isLoadingMore;
  final bool hasMore;
  final TemplateSendMessage? message;
  final TemplateSendMutationResult? sentResult;

  TemplateSendComposerState copyWith({
    AsyncValue<List<TemplateSendProfile>>? recipients,
    bool? isSending,
    bool? isLoadingMore,
    bool? hasMore,
    TemplateSendMessage? message,
    bool clearMessage = false,
    TemplateSendMutationResult? sentResult,
    bool clearResult = false,
  }) {
    return TemplateSendComposerState(
      recipients: recipients ?? this.recipients,
      isSending: isSending ?? this.isSending,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      message: clearMessage ? null : message ?? this.message,
      sentResult: clearResult ? null : sentResult ?? this.sentResult,
    );
  }
}

class TemplateSendComposerController
    extends StateNotifier<TemplateSendComposerState> {
  TemplateSendComposerController(
    this._repository,
    this.templateId, {
    required void Function() invalidateShared,
    required void Function() invalidateNotifications,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _invalidateShared = invalidateShared,
        _invalidateNotifications = invalidateNotifications,
        _requestIdGenerator = requestIdGenerator,
        _requestTimeout = requestTimeout,
        super(const TemplateSendComposerState.loading());

  final TemplateSendRepository _repository;
  final String templateId;
  final void Function() _invalidateShared;
  final void Function() _invalidateNotifications;
  final CreationRequestIdGenerator _requestIdGenerator;
  final Duration _requestTimeout;
  String? _pendingPayload;
  String? _pendingRequestId;
  static const recipientPageSize = 20;

  Future<void> loadRecipients() async {
    if (state.isSending) return;
    final cached = state.recipients.valueOrNull;
    state = state.copyWith(
      recipients: cached == null ? const AsyncLoading() : AsyncData(cached),
      clearMessage: true,
    );
    try {
      final recipients = await _repository.listEligibleRecipients(
        templateId,
        pageSize: recipientPageSize,
      );
      if (!mounted) return;
      state = state.copyWith(
        recipients: AsyncData(recipients),
        isLoadingMore: false,
        hasMore: recipients.length == recipientPageSize,
        clearMessage: true,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(
        recipients:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        isLoadingMore: false,
        message: TemplateSendMessage.operationFailed,
      );
    }
  }

  Future<void> loadMoreRecipients() async {
    final current = state.recipients.valueOrNull;
    if (current == null ||
        current.isEmpty ||
        !state.hasMore ||
        state.isLoadingMore ||
        state.isSending) {
      return;
    }
    final last = current.last;
    state = state.copyWith(isLoadingMore: true, clearMessage: true);
    try {
      final page = await _repository.listEligibleRecipients(
        templateId,
        pageSize: recipientPageSize,
        cursor: TemplateSendRecipientCursor(
          username: last.username,
          profileId: last.id,
        ),
      );
      if (!mounted) return;
      final byId = <String, TemplateSendProfile>{
        for (final recipient in current) recipient.id: recipient,
      };
      for (final recipient in page) {
        byId.putIfAbsent(recipient.id, () => recipient);
      }
      state = state.copyWith(
        recipients: AsyncData(byId.values.toList(growable: false)),
        isLoadingMore: false,
        hasMore: page.length == recipientPageSize,
        clearMessage: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        message: TemplateSendMessage.operationFailed,
      );
    }
  }

  Future<bool> send({
    required String recipientProfileId,
    required int expectedTemplateVersion,
  }) async {
    if (state.isSending) return false;
    final eligible = state.recipients.valueOrNull ?? const [];
    if (!eligible.any((profile) => profile.id == recipientProfileId)) {
      state = state.copyWith(message: TemplateSendMessage.unavailable);
      return false;
    }
    final payload =
        '$templateId:$recipientProfileId:$expectedTemplateVersion:send';
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingRequestId = _requestIdGenerator();
    }
    state = state.copyWith(
      isSending: true,
      clearMessage: true,
      clearResult: true,
    );
    try {
      final result = await _repository
          .sendTemplate(
            templateId,
            recipientProfileId,
            expectedTemplateVersion: expectedTemplateVersion,
            requestId: _pendingRequestId!,
          )
          .timeout(_requestTimeout);
      if (!mounted) return false;
      _pendingPayload = null;
      _pendingRequestId = null;
      _invalidateShared();
      _invalidateNotifications();
      state = state.copyWith(
        isSending: false,
        message: TemplateSendMessage.sent,
        sentResult: result,
      );
      return true;
    } on TemplateSendFailure catch (failure) {
      if (!mounted) return false;
      final message = _messageForFailure(failure.code);
      state = state.copyWith(isSending: false, clearMessage: true);
      if (_shouldRefresh(failure.code)) {
        await loadRecipients();
      }
      if (mounted) state = state.copyWith(message: message);
      return false;
    } on TimeoutException {
      if (!mounted) return false;
      state = state.copyWith(
        isSending: false,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isSending: false,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    }
  }
}

class ReceivedTemplateSendState {
  const ReceivedTemplateSendState({
    required this.detail,
    this.isMutating = false,
    this.message,
    this.acceptedTemplateId,
  });

  const ReceivedTemplateSendState.loading()
      : detail = const AsyncLoading(),
        isMutating = false,
        message = null,
        acceptedTemplateId = null;

  final AsyncValue<ReceivedTemplateSendDetail> detail;
  final bool isMutating;
  final TemplateSendMessage? message;
  final String? acceptedTemplateId;

  ReceivedTemplateSendState copyWith({
    AsyncValue<ReceivedTemplateSendDetail>? detail,
    bool? isMutating,
    TemplateSendMessage? message,
    bool clearMessage = false,
    String? acceptedTemplateId,
    bool clearAcceptedTemplate = false,
  }) {
    return ReceivedTemplateSendState(
      detail: detail ?? this.detail,
      isMutating: isMutating ?? this.isMutating,
      message: clearMessage ? null : message ?? this.message,
      acceptedTemplateId: clearAcceptedTemplate
          ? null
          : acceptedTemplateId ?? this.acceptedTemplateId,
    );
  }
}

class ReceivedTemplateSendController
    extends StateNotifier<ReceivedTemplateSendState> {
  ReceivedTemplateSendController(
    this._repository,
    this.templateSendId, {
    required void Function() invalidateShared,
    required void Function() invalidateTemplates,
    required void Function() invalidateNotifications,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _invalidateShared = invalidateShared,
        _invalidateTemplates = invalidateTemplates,
        _invalidateNotifications = invalidateNotifications,
        _requestIdGenerator = requestIdGenerator,
        _requestTimeout = requestTimeout,
        super(const ReceivedTemplateSendState.loading());

  final TemplateSendRepository _repository;
  final String templateSendId;
  final void Function() _invalidateShared;
  final void Function() _invalidateTemplates;
  final void Function() _invalidateNotifications;
  final CreationRequestIdGenerator _requestIdGenerator;
  final Duration _requestTimeout;
  int _generation = 0;
  bool _reconciliationPending = false;
  String? _pendingPayload;
  String? _pendingRequestId;

  Future<void> load() async {
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    final generation = ++_generation;
    final cached = state.detail.valueOrNull;
    state = cached == null
        ? const ReceivedTemplateSendState.loading()
        : state.copyWith(clearMessage: true);
    try {
      final detail = await _repository.getReceived(templateSendId);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: AsyncData(detail),
        acceptedTemplateId: detail.acceptedTemplateId,
        clearMessage: true,
      );
    } on TemplateSendFailure catch (failure, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: cached == null ||
                failure.code == TemplateSendFailureCode.unavailable
            ? AsyncError(failure, stackTrace)
            : AsyncData(cached),
        message: _messageForFailure(failure.code),
        clearAcceptedTemplate:
            failure.code == TemplateSendFailureCode.unavailable,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: TemplateSendMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<void> reconcile() async {
    if (state.isMutating) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  Future<bool> accept() => _mutate(TemplateSendState.accepted);

  Future<bool> decline() => _mutate(TemplateSendState.declined);

  Future<bool> _mutate(TemplateSendState desiredState) async {
    final detail = state.detail.valueOrNull;
    if (state.isMutating ||
        detail == null ||
        detail.summary.state != TemplateSendState.pending) {
      return false;
    }
    final payload =
        '$templateSendId:${detail.summary.version}:${desiredState.wireValue}';
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingRequestId = _requestIdGenerator();
    }
    state = state.copyWith(
      isMutating: true,
      clearMessage: true,
      clearAcceptedTemplate: desiredState != TemplateSendState.accepted,
    );
    try {
      final request = desiredState == TemplateSendState.accepted
          ? _repository.accept(
              templateSendId,
              expectedVersion: detail.summary.version,
              requestId: _pendingRequestId!,
            )
          : _repository.decline(
              templateSendId,
              expectedVersion: detail.summary.version,
              requestId: _pendingRequestId!,
            );
      final result = await request.timeout(_requestTimeout);
      if (!mounted) return false;
      _pendingPayload = null;
      _pendingRequestId = null;
      _invalidateShared();
      _invalidateNotifications();
      if (desiredState == TemplateSendState.accepted) {
        _invalidateTemplates();
      }
      state = state.copyWith(
        isMutating: false,
        clearMessage: true,
        acceptedTemplateId: result.acceptedTemplateId,
      );
      await load();
      if (mounted) {
        state = state.copyWith(
          message: desiredState == TemplateSendState.accepted
              ? TemplateSendMessage.accepted
              : TemplateSendMessage.declined,
          acceptedTemplateId: result.acceptedTemplateId,
        );
      }
      return true;
    } on TemplateSendFailure catch (failure) {
      if (!mounted) return false;
      final message = _messageForFailure(failure.code);
      state = state.copyWith(isMutating: false, clearMessage: true);
      if (_shouldRefresh(failure.code)) {
        await load();
      }
      if (mounted) state = state.copyWith(message: message);
      return false;
    } on TimeoutException {
      if (!mounted) return false;
      state = state.copyWith(
        isMutating: false,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isMutating: false,
        message: TemplateSendMessage.operationFailed,
      );
      return false;
    } finally {
      _drainReconciliation();
    }
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

TemplateSendCursor? _receivedCursor(
  List<ReceivedTemplateSendSummary> summaries,
) {
  if (summaries.isEmpty) return null;
  final last = summaries.last;
  return TemplateSendCursor(
    stateChangedAt: last.stateChangedAt,
    templateSendId: last.id,
  );
}

TemplateSendCursor? _sentCursor(List<SentTemplateSendSummary> summaries) {
  if (summaries.isEmpty) return null;
  final last = summaries.last;
  return TemplateSendCursor(
    stateChangedAt: last.stateChangedAt,
    templateSendId: last.id,
  );
}

List<ReceivedTemplateSendSummary> _mergeReceived(
  List<ReceivedTemplateSendSummary> current,
  List<ReceivedTemplateSendSummary> page,
) {
  final result = <String, ReceivedTemplateSendSummary>{
    for (final item in current) item.id: item,
  };
  for (final item in page) {
    result.putIfAbsent(item.id, () => item);
  }
  return result.values.toList(growable: false);
}

List<SentTemplateSendSummary> _mergeSent(
  List<SentTemplateSendSummary> current,
  List<SentTemplateSendSummary> page,
) {
  final result = <String, SentTemplateSendSummary>{
    for (final item in current) item.id: item,
  };
  for (final item in page) {
    result.putIfAbsent(item.id, () => item);
  }
  return result.values.toList(growable: false);
}

TemplateSendMessage _messageForFailure(TemplateSendFailureCode code) =>
    switch (code) {
      TemplateSendFailureCode.invalid => TemplateSendMessage.operationFailed,
      TemplateSendFailureCode.unavailable => TemplateSendMessage.unavailable,
      TemplateSendFailureCode.stale => TemplateSendMessage.stale,
      TemplateSendFailureCode.duplicatePending =>
        TemplateSendMessage.duplicatePending,
      TemplateSendFailureCode.retryConflict =>
        TemplateSendMessage.retryConflict,
      TemplateSendFailureCode.capacity => TemplateSendMessage.capacity,
      TemplateSendFailureCode.noLongerPending => TemplateSendMessage.stale,
      TemplateSendFailureCode.transport ||
      TemplateSendFailureCode.generic =>
        TemplateSendMessage.operationFailed,
    };

bool _shouldRefresh(TemplateSendFailureCode code) =>
    code == TemplateSendFailureCode.stale ||
    code == TemplateSendFailureCode.noLongerPending ||
    code == TemplateSendFailureCode.unavailable ||
    code == TemplateSendFailureCode.capacity;
