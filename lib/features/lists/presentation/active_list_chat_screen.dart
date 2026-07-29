import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ActiveListChatScreen extends ConsumerStatefulWidget {
  const ActiveListChatScreen({required this.listId, super.key});

  final String listId;

  @override
  ConsumerState<ActiveListChatScreen> createState() =>
      _ActiveListChatScreenState();
}

class _ActiveListChatScreenState extends ConsumerState<ActiveListChatScreen> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scrollController = ScrollController();
  bool _showNewMessages = false;
  bool _didExit = false;
  int? _lastRenderedNewestPosition;
  int _scrollGeneration = 0;

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = activeListChatControllerProvider(widget.listId);
    final detailProvider = activeListDetailControllerProvider(widget.listId);
    final chatState = ref.watch(chatProvider);
    final detailState = ref.watch(detailProvider);
    final detail = detailState.detail.valueOrNull;
    final archived = detail?.summary.status == ActiveListStatus.archived;
    final mutationInProgress =
        chatState.isSending || chatState.deletingMessageIds.isNotEmpty;
    final localizations = AppLocalizations.of(context);

    ref.listen<ActiveListChatState>(chatProvider, (previous, next) {
      _handleChatState(previous, next);
    });
    ref.listen<ActiveListDetailState>(detailProvider, (previous, next) {
      if (next.message == ActiveListDetailMessage.unavailable &&
          previous?.message != ActiveListDetailMessage.unavailable) {
        _exitForUnavailable();
      }
    });

    final title = detail == null
        ? localizations.listsTitle
        : localizations.listChatTitle(detail.summary.title);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            key: const Key('listChatRefreshButton'),
            onPressed: chatState.isRefreshing ||
                    chatState.isLoadingOlder ||
                    mutationInProgress
                ? null
                : () => ref.read(chatProvider.notifier).reconcile(),
            tooltip: localizations.listChatRefreshingLabel,
            icon: chatState.isRefreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _showNewMessages
          ? FloatingActionButton.extended(
              key: const Key('listChatNewMessagesButton'),
              onPressed: _scrollToNewest,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: Text(localizations.listChatNewMessagesButton),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (archived) const _ArchivedChatBanner(),
                Expanded(
                  child: chatState.messages.when(
                    loading: () => Semantics(
                      liveRegion: true,
                      label: localizations.listChatLoadingLabel,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => _ChatLoadError(
                      onRetry: () => ref.read(chatProvider.notifier).load(),
                    ),
                    data: (messages) => _buildMessages(
                      context,
                      chatState,
                      messages,
                      isOwner: detail?.summary.isOwner ?? false,
                      canMutate: detail != null &&
                          !archived &&
                          !chatState.isRefreshing &&
                          !chatState.isLoadingOlder,
                      archived: archived,
                    ),
                  ),
                ),
                if (detail != null && !archived && chatState.messages.hasValue)
                  _ChatComposer(
                    controller: _composer,
                    focusNode: _composerFocus,
                    isSending: chatState.isSending,
                    isBlocked: chatState.isRefreshing ||
                        chatState.isLoadingOlder ||
                        chatState.deletingMessageIds.isNotEmpty,
                    onSend: _send,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(
    BuildContext context,
    ActiveListChatState state,
    List<ActiveListChatMessage> messages, {
    required bool isOwner,
    required bool canMutate,
    required bool archived,
  }) {
    final localizations = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: () => ref
          .read(activeListChatControllerProvider(widget.listId).notifier)
          .reconcile(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            final atBottom = notification.metrics.extentAfter <= 24;
            if (atBottom) {
              if (_showNewMessages) {
                setState(() => _showNewMessages = false);
              }
              _markNewestRead();
            }
          }
          return false;
        },
        child: messages.isEmpty
            ? ListView(
                key: const Key('listChatMessages'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.42,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.forum_outlined, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              localizations.listChatEmptyTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              localizations.listChatEmptyDescription,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                key: const Key('listChatMessages'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _OlderMessagesControl(
                      state: state,
                      onLoad: _loadOlderPreservingAnchor,
                    );
                  }
                  final message = messages[index - 1];
                  return _ChatMessageCard(
                    key: Key('chat-message-${message.id}'),
                    message: message,
                    canDelete: canMutate &&
                        !state.isSending &&
                        (state.deletingMessageIds.isEmpty ||
                            state.deletingMessageIds.contains(message.id)) &&
                        !message.isDeleted &&
                        (isOwner || message.isMine),
                    isDeleting: state.deletingMessageIds.contains(message.id),
                    onDelete: () => _confirmDelete(message, isOwner: isOwner),
                  );
                },
              ),
      ),
    );
  }

  void _handleChatState(
    ActiveListChatState? previous,
    ActiveListChatState next,
  ) {
    final previousMessages = previous?.messages.valueOrNull;
    final nextMessages = next.messages.valueOrNull;
    if (nextMessages != null) {
      final newest =
          nextMessages.isEmpty ? null : nextMessages.last.messagePosition;
      final previousNewest =
          previousMessages == null || previousMessages.isEmpty
              ? _lastRenderedNewestPosition
              : previousMessages.last.messagePosition;
      _lastRenderedNewestPosition = newest;
      if (newest != null &&
          (previousNewest == null || newest > previousNewest)) {
        final wasAtBottom = _isAtBottom;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (previousNewest == null || wasAtBottom) {
            _scrollToNewest();
          } else if (!_showNewMessages) {
            setState(() => _showNewMessages = true);
          }
        });
      }
    }

    if (next.notice != null && next.notice != previous?.notice) {
      final notice = next.notice!;
      if (notice == ActiveListChatNotice.olderPageFailed) return;
      if (notice == ActiveListChatNotice.unavailable) {
        _exitForUnavailable();
      } else {
        if (notice == ActiveListChatNotice.archivedReadOnly) {
          unawaited(
            ref
                .read(
                  activeListDetailControllerProvider(widget.listId).notifier,
                )
                .reconcile(),
          );
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(_noticeText(notice))),
        );
      }
      ref
          .read(activeListChatControllerProvider(widget.listId).notifier)
          .clearNotice();
    }
  }

  String _noticeText(ActiveListChatNotice notice) {
    final localizations = AppLocalizations.of(context);
    return switch (notice) {
      ActiveListChatNotice.invalidMessage =>
        localizations.listChatInvalidMessage,
      ActiveListChatNotice.sendUncertain =>
        localizations.listChatSendUncertainMessage,
      ActiveListChatNotice.rateLimited =>
        localizations.listChatRateLimitedMessage,
      ActiveListChatNotice.requestConflict =>
        localizations.listChatRequestConflictMessage,
      ActiveListChatNotice.archivedReadOnly =>
        localizations.listChatArchivedBanner,
      ActiveListChatNotice.unavailable =>
        localizations.listChatAccessRemovedMessage,
      ActiveListChatNotice.refreshFailed =>
        localizations.listChatRefreshFailedMessage,
      ActiveListChatNotice.olderPageFailed =>
        localizations.listChatRefreshFailedMessage,
      ActiveListChatNotice.deleteUncertain =>
        localizations.listChatDeleteUncertainMessage,
      ActiveListChatNotice.operationFailed =>
        localizations.listChatOperationFailedMessage,
    };
  }

  Future<void> _send() async {
    final submitted = normalizeActiveListChatBody(_composer.text);
    final outcome = await ref
        .read(activeListChatControllerProvider(widget.listId).notifier)
        .send(_composer.text);
    if (!mounted) return;
    if (outcome == ActiveListChatSendOutcome.sent &&
        normalizeActiveListChatBody(_composer.text) == submitted) {
      _composer.clear();
    }
    if (outcome == ActiveListChatSendOutcome.sent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNewest());
    }
  }

  Future<void> _confirmDelete(
    ActiveListChatMessage message, {
    required bool isOwner,
  }) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.listChatDeleteTitle),
        content: Text(localizations.listChatDeleteDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmDeleteChatMessageButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.listChatDeleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(activeListChatControllerProvider(widget.listId).notifier)
        .delete(message, isOwner: isOwner);
  }

  Future<void> _loadOlderPreservingAnchor() async {
    final beforePixels =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final beforeMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    await ref
        .read(activeListChatControllerProvider(widget.listId).notifier)
        .loadOlder();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final addedExtent =
          _scrollController.position.maxScrollExtent - beforeMax;
      _scrollController.jumpTo(
        (beforePixels + addedExtent).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  void _scrollToNewest() {
    if (!mounted || !_scrollController.hasClients) return;
    final generation = ++_scrollGeneration;
    if (_showNewMessages) setState(() => _showNewMessages = false);
    unawaited(_performNewestScroll(generation, 0));
  }

  Future<void> _performNewestScroll(int generation, int attempt) async {
    if (!mounted ||
        generation != _scrollGeneration ||
        !_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted ||
        generation != _scrollGeneration ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter > 24 && attempt < 4) {
      final nextFrame = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => nextFrame.complete());
      await nextFrame.future;
      return _performNewestScroll(generation, attempt + 1);
    }
    _markNewestRead();
  }

  bool get _isAtBottom =>
      !_scrollController.hasClients ||
      _scrollController.position.extentAfter <= 24;

  void _markNewestRead() {
    if (!mounted || !_isAtBottom) return;
    final messages = ref
        .read(activeListChatControllerProvider(widget.listId))
        .messages
        .valueOrNull;
    if (messages == null || messages.isEmpty) return;
    ref
        .read(activeListChatControllerProvider(widget.listId).notifier)
        .markReadThrough(messages.last);
  }

  void _exitForUnavailable() {
    if (_didExit || !mounted) return;
    _didExit = true;
    final message = AppLocalizations.of(context).listChatAccessRemovedMessage;
    final messenger = ScaffoldMessenger.of(context);
    context.go(AppRoutes.lists);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.isBlocked,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool isBlocked;
  final Future<void> Function() onSend;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(covariant _ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleChange);
      widget.controller.addListener(_handleChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final normalized = normalizeActiveListChatBody(widget.controller.text);
    final count = normalized.runes.length;
    final valid = isValidActiveListChatBody(normalized);
    final onSend = valid && !widget.isSending && !widget.isBlocked
        ? () => widget.onSend()
        : null;
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('listChatComposer'),
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: localizations.listChatComposerLabel,
                  helperText: localizations.listChatComposerHelper,
                  counterText: localizations.listChatCharacterCount(count),
                  errorText: widget.controller.text.isNotEmpty && !valid
                      ? localizations.listChatInvalidMessage
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              enabled: onSend != null,
              excludeSemantics: true,
              label: widget.isSending
                  ? localizations.listChatSendingLabel
                  : localizations.listChatSendButton,
              onTap: onSend,
              child: IconButton.filled(
                key: const Key('listChatSendButton'),
                onPressed: onSend,
                tooltip: localizations.listChatSendButton,
                icon: widget.isSending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OlderMessagesControl extends StatelessWidget {
  const _OlderMessagesControl({
    required this.state,
    required this.onLoad,
  });

  final ActiveListChatState state;
  final Future<void> Function() onLoad;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (state.isLoadingOlder) {
      return Semantics(
        liveRegion: true,
        label: localizations.listChatLoadingOlderLabel,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (!state.hasMore) return const SizedBox(height: 8);
    final retry = state.notice == ActiveListChatNotice.olderPageFailed;
    return Center(
      child: TextButton.icon(
        key: const Key('listChatLoadOlderButton'),
        onPressed: state.isRefreshing ? null : onLoad,
        icon: Icon(retry ? Icons.refresh_rounded : Icons.history_rounded),
        label: Text(
          retry
              ? localizations.listChatRetryOlderButton
              : localizations.listChatLoadOlderButton,
        ),
      ),
    );
  }
}

class _ChatMessageCard extends StatelessWidget {
  const _ChatMessageCard({
    required this.message,
    required this.canDelete,
    required this.isDeleting,
    required this.onDelete,
    super.key,
  });

  final ActiveListChatMessage message;
  final bool canDelete;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final timestamp = message.createdAt.toLocal();
    final timestampLabel = localizations.listChatTimestamp(
      material.formatShortDate(timestamp),
      material.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp)),
    );
    final sender = message.isMine
        ? localizations.listChatYouLabel
        : message.deletionKind == ActiveListChatDeletionKind.account
            ? localizations.listChatDeletedAccountSenderLabel
            : localizations.listChatSenderLabel(
                message.senderDisplayName!,
                message.senderUsername!,
              );
    final displayedMessage = switch (message.deletionKind) {
      ActiveListChatDeletionKind.sender =>
        localizations.listChatDeletedBySender,
      ActiveListChatDeletionKind.owner => localizations.listChatDeletedByOwner,
      ActiveListChatDeletionKind.account =>
        localizations.listChatDeletedWithAccount,
      null => message.body!,
    };
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: localizations.listChatMessageSemantics(
        sender,
        timestampLabel,
        displayedMessage,
      ),
      child: Align(
        alignment:
            message.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Card(
            color: message.isMine
                ? colors.primaryContainer
                : colors.surfaceVariant,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.isDeleted) ...[
                              const Icon(Icons.delete_outline, size: 18),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                displayedMessage,
                                style: message.isDeleted
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontStyle: FontStyle.italic,
                                        )
                                    : null,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          timestampLabel,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      key: Key('delete-chat-message-${message.id}'),
                      onPressed: isDeleting ? null : onDelete,
                      tooltip: localizations.listChatDeleteButton,
                      icon: isDeleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchivedChatBanner extends StatelessWidget {
  const _ArchivedChatBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('listChatArchivedBanner'),
        width: double.infinity,
        color: colors.secondaryContainer,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.of(context).listChatArchivedBanner,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLoadError extends StatelessWidget {
  const _ChatLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              localizations.listChatLoadFailedTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.listChatLoadFailedDescription,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(localizations.tryAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}
