import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/templates/domain/friend_public_template_feed_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';

enum FriendPublicTemplateFeedMessage {
  refreshFailed,
  loadMoreFailed,
}

class FriendPublicTemplateFeedState {
  const FriendPublicTemplateFeedState({
    required this.page,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.message,
  });

  const FriendPublicTemplateFeedState.loading()
      : page = const AsyncLoading(),
        isRefreshing = false,
        isLoadingMore = false,
        loadMoreFailed = false,
        message = null;

  final AsyncValue<FriendPublicTemplatePage> page;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final FriendPublicTemplateFeedMessage? message;

  bool get isBusy => isRefreshing || isLoadingMore || page.isLoading;

  FriendPublicTemplateFeedState copyWith({
    AsyncValue<FriendPublicTemplatePage>? page,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    FriendPublicTemplateFeedMessage? message,
    bool clearMessage = false,
  }) {
    return FriendPublicTemplateFeedState(
      page: page ?? this.page,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class FriendPublicTemplateFeedController
    extends StateNotifier<FriendPublicTemplateFeedState> {
  FriendPublicTemplateFeedController(
    this._repository, {
    required bool hasAuthenticatedUser,
  })  : _hasAuthenticatedUser = hasAuthenticatedUser,
        super(const FriendPublicTemplateFeedState.loading());

  final FriendPublicTemplateFeedRepository _repository;
  final bool _hasAuthenticatedUser;
  bool _requestRunning = false;
  bool _reconciliationPending = false;

  Future<void> load() async {
    if (!_hasAuthenticatedUser || _requestRunning) return;
    _requestRunning = true;
    final cached = state.page.valueOrNull;
    state = cached == null
        ? const FriendPublicTemplateFeedState.loading()
        : state.copyWith(
            isRefreshing: true,
            isLoadingMore: false,
            loadMoreFailed: false,
            clearMessage: true,
          );
    try {
      final page = await _repository.listFriendFeed();
      if (!mounted) return;
      state = state.copyWith(
        page: AsyncData(page),
        isRefreshing: false,
        isLoadingMore: false,
        loadMoreFailed: false,
        clearMessage: true,
      );
    } on PublicTemplateFailure catch (error, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(
        page:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        isRefreshing: false,
        isLoadingMore: false,
        loadMoreFailed: false,
        message: cached == null
            ? null
            : FriendPublicTemplateFeedMessage.refreshFailed,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = state.copyWith(
        page:
            cached == null ? AsyncError(error, stackTrace) : AsyncData(cached),
        isRefreshing: false,
        isLoadingMore: false,
        loadMoreFailed: false,
        message: cached == null
            ? null
            : FriendPublicTemplateFeedMessage.refreshFailed,
      );
    } finally {
      _requestRunning = false;
      _drainReconciliation();
    }
  }

  Future<void> loadMore() async {
    final current = state.page.valueOrNull;
    final cursor = current?.nextCursor;
    if (!_hasAuthenticatedUser ||
        current == null ||
        cursor == null ||
        _requestRunning) {
      return;
    }
    _requestRunning = true;
    state = state.copyWith(
      isLoadingMore: true,
      loadMoreFailed: false,
      clearMessage: true,
    );
    try {
      final next = await _repository.listFriendFeed(cursor: cursor);
      if (!mounted) return;
      final byId = <String, FriendPublicTemplateEntry>{
        for (final entry in current.entries) entry.template.id: entry,
      };
      for (final entry in next.entries) {
        byId.putIfAbsent(entry.template.id, () => entry);
      }
      state = state.copyWith(
        page: AsyncData(
          FriendPublicTemplatePage(
            entries: byId.values.toList(growable: false),
            nextCursor: next.nextCursor,
          ),
        ),
        isLoadingMore: false,
        loadMoreFailed: false,
        clearMessage: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        loadMoreFailed: true,
        message: FriendPublicTemplateFeedMessage.loadMoreFailed,
      );
    } finally {
      _requestRunning = false;
      _drainReconciliation();
    }
  }

  Future<void> reconcile() async {
    if (_requestRunning) {
      _reconciliationPending = true;
      return;
    }
    await load();
  }

  void _drainReconciliation() {
    if (!_reconciliationPending || !mounted || _requestRunning) return;
    _reconciliationPending = false;
    unawaited(load());
  }
}
