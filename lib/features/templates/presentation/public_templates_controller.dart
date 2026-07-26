import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';

enum PublicTemplatesMessage {
  copied,
  reported,
  staleReview,
  unavailable,
  capacity,
  operationFailed,
}

class PublicProfileTemplatesState {
  const PublicProfileTemplatesState({
    required this.page,
    this.isLoadingMore = false,
    this.isBlocking = false,
    this.message,
  });

  const PublicProfileTemplatesState.loading()
      : page = const AsyncLoading(),
        isLoadingMore = false,
        isBlocking = false,
        message = null;

  final AsyncValue<PublicTemplatePage> page;
  final bool isLoadingMore;
  final bool isBlocking;
  final PublicTemplatesMessage? message;

  bool get isBusy => isLoadingMore || isBlocking;

  PublicProfileTemplatesState copyWith({
    AsyncValue<PublicTemplatePage>? page,
    bool? isLoadingMore,
    bool? isBlocking,
    PublicTemplatesMessage? message,
    bool clearMessage = false,
  }) {
    return PublicProfileTemplatesState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isBlocking: isBlocking ?? this.isBlocking,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class PublicProfileTemplatesController
    extends StateNotifier<PublicProfileTemplatesState> {
  PublicProfileTemplatesController(
    this._repository,
    this._communityRepository,
    this.profileId, {
    required bool hasAuthenticatedUser,
    required bool canBlock,
    required void Function() invalidateCommunity,
    required void Function() invalidateNotifications,
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        _canBlock = canBlock,
        _invalidateCommunity = invalidateCommunity,
        _invalidateNotifications = invalidateNotifications,
        super(const PublicProfileTemplatesState.loading());

  final PublicTemplateRepository _repository;
  final CommunityRepository _communityRepository;
  final String profileId;
  final bool _hasAuthenticatedUser;
  final bool _canBlock;
  final void Function() _invalidateCommunity;
  final void Function() _invalidateNotifications;
  int _generation = 0;
  bool _reconciliationPending = false;

  Future<void> load() async {
    if (!_hasAuthenticatedUser || state.isBlocking) return;
    final generation = ++_generation;
    final cached = state.page.valueOrNull;
    if (cached == null) {
      state = const PublicProfileTemplatesState.loading();
    } else {
      state = state.copyWith(clearMessage: true);
    }
    try {
      final page = await _repository.listProfileTemplates(profileId);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        page: AsyncData(page),
        isLoadingMore: false,
        clearMessage: true,
      );
    } on PublicTemplateFailure catch (failure, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        page: cached == null
            ? AsyncError(failure, stackTrace)
            : AsyncData(cached),
        isLoadingMore: false,
        message: failure.code == PublicTemplateFailureCode.unavailable
            ? PublicTemplatesMessage.unavailable
            : PublicTemplatesMessage.operationFailed,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        page:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        isLoadingMore: false,
        message: PublicTemplatesMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<void> loadMore() async {
    final current = state.page.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || state.isBusy) return;
    state = state.copyWith(isLoadingMore: true, clearMessage: true);
    try {
      final page = await _repository.listProfileTemplates(
        profileId,
        cursor: cursor,
      );
      if (!mounted) return;
      if (page.profile.id != current.profile.id) {
        throw const PublicTemplateFailure(PublicTemplateFailureCode.generic);
      }
      final byId = <String, PublicTemplateSummary>{
        for (final template in current.templates) template.id: template,
      };
      for (final template in page.templates) {
        byId.putIfAbsent(template.id, () => template);
      }
      state = state.copyWith(
        page: AsyncData(
          PublicTemplatePage(
            profile: page.profile,
            templates: byId.values.toList(growable: false),
            nextCursor: page.nextCursor,
          ),
        ),
        isLoadingMore: false,
        clearMessage: true,
      );
    } on PublicTemplateFailure catch (failure) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        message: failure.code == PublicTemplateFailureCode.unavailable
            ? PublicTemplatesMessage.unavailable
            : PublicTemplatesMessage.operationFailed,
      );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isLoadingMore: false,
          message: PublicTemplatesMessage.operationFailed,
        );
      }
    }
    _drainReconciliation();
  }

  Future<bool> blockProfile() async {
    if (!_canBlock ||
        state.isBusy ||
        state.page.valueOrNull == null ||
        state.message == PublicTemplatesMessage.unavailable) {
      return false;
    }
    state = state.copyWith(isBlocking: true, clearMessage: true);
    try {
      await _communityRepository.blockProfile(profileId);
      if (!mounted) return false;
      _invalidateCommunity();
      _invalidateNotifications();
      state = state.copyWith(
        isBlocking: false,
        message: PublicTemplatesMessage.unavailable,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isBlocking: false,
        message: PublicTemplatesMessage.operationFailed,
      );
      return false;
    }
  }

  Future<void> reconcile() async {
    if (state.isBusy) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isBusy) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

class PublicTemplateDetailState {
  const PublicTemplateDetailState({
    required this.detail,
    this.isMutating = false,
    this.message,
    this.copiedTemplateId,
  });

  const PublicTemplateDetailState.loading()
      : detail = const AsyncLoading(),
        isMutating = false,
        message = null,
        copiedTemplateId = null;

  final AsyncValue<PublicTemplateDetail> detail;
  final bool isMutating;
  final PublicTemplatesMessage? message;
  final String? copiedTemplateId;

  PublicTemplateDetailState copyWith({
    AsyncValue<PublicTemplateDetail>? detail,
    bool? isMutating,
    PublicTemplatesMessage? message,
    bool clearMessage = false,
    String? copiedTemplateId,
    bool clearCopiedTemplate = false,
  }) {
    return PublicTemplateDetailState(
      detail: detail ?? this.detail,
      isMutating: isMutating ?? this.isMutating,
      message: clearMessage ? null : message ?? this.message,
      copiedTemplateId: clearCopiedTemplate
          ? null
          : copiedTemplateId ?? this.copiedTemplateId,
    );
  }
}

class PublicTemplateDetailController
    extends StateNotifier<PublicTemplateDetailState> {
  PublicTemplateDetailController(
    this._repository,
    this._communityRepository,
    this.profileId,
    this.templateId, {
    required bool canBlock,
    required void Function() invalidatePrivateTemplates,
    required void Function() invalidateCommunity,
    required void Function() invalidateNotifications,
    CreationRequestIdGenerator requestIdGenerator = secureCreationRequestId,
  })  : _canBlock = canBlock,
        _invalidatePrivateTemplates = invalidatePrivateTemplates,
        _invalidateCommunity = invalidateCommunity,
        _invalidateNotifications = invalidateNotifications,
        _requestIdGenerator = requestIdGenerator,
        super(const PublicTemplateDetailState.loading());

  final PublicTemplateRepository _repository;
  final CommunityRepository _communityRepository;
  final String profileId;
  final String templateId;
  final bool _canBlock;
  final void Function() _invalidatePrivateTemplates;
  final void Function() _invalidateCommunity;
  final void Function() _invalidateNotifications;
  final CreationRequestIdGenerator _requestIdGenerator;
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
    if (cached == null) {
      state = const PublicTemplateDetailState.loading();
    } else {
      state = state.copyWith(clearMessage: true);
    }
    try {
      final detail = await _repository.getTemplate(profileId, templateId);
      if (!mounted || generation != _generation) return;
      if (_pendingPayload != null &&
          _pendingPayload != _copyPayload(detail.summary)) {
        _clearPendingCopy();
      }
      state = state.copyWith(
        detail: AsyncData(detail),
        clearMessage: true,
        clearCopiedTemplate: true,
      );
    } on PublicTemplateFailure catch (failure, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail: cached == null
            ? AsyncError(failure, stackTrace)
            : AsyncData(cached),
        message: failure.code == PublicTemplateFailureCode.unavailable
            ? PublicTemplatesMessage.unavailable
            : PublicTemplatesMessage.operationFailed,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        detail:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        message: PublicTemplatesMessage.operationFailed,
      );
    }
    _drainReconciliation();
  }

  Future<String?> copyTemplate() async {
    final detail = state.detail.valueOrNull;
    if (detail == null || state.isMutating) return null;
    final payload = _copyPayload(detail.summary);
    if (_pendingPayload != payload) {
      _pendingPayload = payload;
      _pendingRequestId = _requestIdGenerator();
    }
    state = state.copyWith(
      isMutating: true,
      clearMessage: true,
      clearCopiedTemplate: true,
    );
    try {
      final result = await _repository.copyTemplate(
        templateId,
        expectedVersion: detail.summary.version,
        requestId: _pendingRequestId!,
      );
      if (!mounted) return null;
      _clearPendingCopy();
      _invalidatePrivateTemplates();
      state = state.copyWith(
        isMutating: false,
        message: PublicTemplatesMessage.copied,
        copiedTemplateId: result.template.id,
      );
      _drainReconciliation();
      return result.template.id;
    } on PublicTemplateFailure catch (failure) {
      if (!mounted) return null;
      state = state.copyWith(
        isMutating: false,
        message: _messageFor(failure),
      );
      if (failure.code == PublicTemplateFailureCode.stale) {
        _clearPendingCopy();
        await load();
        if (mounted &&
            state.message != PublicTemplatesMessage.unavailable &&
            state.detail.valueOrNull != null) {
          state = state.copyWith(message: PublicTemplatesMessage.staleReview);
        }
      }
      _drainReconciliation();
      return null;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PublicTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return null;
    }
  }

  Future<bool> reportTemplate(
    PublicTemplateReportReason reason,
    String? explanation,
  ) async {
    final detail = state.detail.valueOrNull;
    if (detail == null || state.isMutating || !_canBlock) return false;
    state = state.copyWith(
      isMutating: true,
      clearMessage: true,
      clearCopiedTemplate: true,
    );
    try {
      await _repository.reportTemplate(
        templateId,
        expectedVersion: detail.summary.version,
        reason: reason,
        explanation: explanation,
      );
      if (!mounted) return false;
      _reconciliationPending = false;
      state = state.copyWith(
        isMutating: false,
        message: PublicTemplatesMessage.reported,
      );
      return true;
    } on PublicTemplateFailure catch (failure) {
      if (!mounted) return false;
      state = state.copyWith(
        isMutating: false,
        message: _messageFor(failure),
      );
      if (failure.code == PublicTemplateFailureCode.stale) {
        await load();
        if (mounted &&
            state.message != PublicTemplatesMessage.unavailable &&
            state.detail.valueOrNull != null) {
          state = state.copyWith(message: PublicTemplatesMessage.staleReview);
        }
      }
      _drainReconciliation();
      return false;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          isMutating: false,
          message: PublicTemplatesMessage.operationFailed,
        );
      }
      _drainReconciliation();
      return false;
    }
  }

  Future<bool> blockProfile() async {
    if (!_canBlock ||
        state.isMutating ||
        state.detail.valueOrNull == null ||
        state.message == PublicTemplatesMessage.unavailable) {
      return false;
    }
    state = state.copyWith(isMutating: true, clearMessage: true);
    try {
      await _communityRepository.blockProfile(profileId);
      if (!mounted) return false;
      _invalidateCommunity();
      _invalidateNotifications();
      state = state.copyWith(
        isMutating: false,
        message: PublicTemplatesMessage.unavailable,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isMutating: false,
        message: PublicTemplatesMessage.operationFailed,
      );
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

  String _copyPayload(PublicTemplateSummary summary) =>
      '${summary.id}\u0000${summary.version}';

  void _clearPendingCopy() {
    _pendingPayload = null;
    _pendingRequestId = null;
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || state.isMutating) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}

PublicTemplatesMessage _messageFor(PublicTemplateFailure failure) {
  return switch (failure.code) {
    PublicTemplateFailureCode.unavailable => PublicTemplatesMessage.unavailable,
    PublicTemplateFailureCode.stale => PublicTemplatesMessage.staleReview,
    PublicTemplateFailureCode.capacity => PublicTemplatesMessage.capacity,
    PublicTemplateFailureCode.invalid ||
    PublicTemplateFailureCode.retryConflict ||
    PublicTemplateFailureCode.transport ||
    PublicTemplateFailureCode.generic =>
      PublicTemplatesMessage.operationFailed,
  };
}
