import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/presentation/template_send_providers.dart';
import 'package:list_and_split/features/templates/presentation/template_sends_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class TemplateSendPreviewItem {
  const TemplateSendPreviewItem({
    required this.name,
    required this.quantity,
  });

  final String name;
  final ListQuantity quantity;
}

class TemplateSendPreview {
  TemplateSendPreview({
    required this.templateId,
    required this.templateVersion,
    required this.name,
    required List<TemplateSendPreviewItem> items,
  }) : items = List.unmodifiable(items);

  final String templateId;
  final int templateVersion;
  final String name;
  final List<TemplateSendPreviewItem> items;
}

Future<bool> showTemplateSendDialog(
  BuildContext context,
  TemplateSendPreview preview,
) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TemplateSendDialog(preview: preview),
      ) ??
      false;
}

class SharedTemplateSendsScreen extends ConsumerStatefulWidget {
  const SharedTemplateSendsScreen({super.key});

  @override
  ConsumerState<SharedTemplateSendsScreen> createState() =>
      _SharedTemplateSendsScreenState();
}

class _SharedTemplateSendsScreenState
    extends ConsumerState<SharedTemplateSendsScreen> {
  var _receivedHistory = false;
  var _sentHistory = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(sharedTemplateSendsControllerProvider);
    ref.listen<SharedTemplateSendsState>(
      sharedTemplateSendsControllerProvider,
      (previous, next) {
        if (next.message != null && next.message != previous?.message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(templateSendMessage(localizations, next.message!)),
            ),
          );
        }
      },
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.templateSendsTitle),
          actions: [
            IconButton(
              key: const Key('refreshTemplateSendsButton'),
              onPressed: state.isBusy
                  ? null
                  : () => ref
                      .read(sharedTemplateSendsControllerProvider.notifier)
                      .load(),
              tooltip: localizations.templatesRefreshTooltip,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const NotificationBell(),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                text: localizations.templateSendsReceivedTab,
              ),
              Tab(
                text: localizations.templateSendsSentTab,
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: state.data.when(
                loading: () => Semantics(
                  label: localizations.templateSendsLoading,
                  liveRegion: true,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => _TemplateSendLoadError(
                  onRetry: () => ref
                      .read(sharedTemplateSendsControllerProvider.notifier)
                      .load(),
                ),
                data: (data) => TabBarView(
                  children: [
                    _ReceivedSendsView(
                      items: _receivedHistory
                          ? data.receivedHistory
                          : data.receivedPending,
                      history: _receivedHistory,
                      hasMore: _receivedHistory
                          ? data.hasMoreReceivedHistory
                          : data.hasMoreReceivedPending,
                      isLoadingMore: state.loadingMore ==
                          (_receivedHistory
                              ? TemplateSendCollection.receivedHistory
                              : TemplateSendCollection.receivedPending),
                      onHistoryChanged: (value) {
                        setState(() => _receivedHistory = value);
                      },
                    ),
                    _SentSendsView(
                      items: _sentHistory ? data.sentHistory : data.sentPending,
                      history: _sentHistory,
                      hasMore: _sentHistory
                          ? data.hasMoreSentHistory
                          : data.hasMoreSentPending,
                      isLoadingMore: state.loadingMore ==
                          (_sentHistory
                              ? TemplateSendCollection.sentHistory
                              : TemplateSendCollection.sentPending),
                      revokingId: state.revokingId,
                      onHistoryChanged: (value) {
                        setState(() => _sentHistory = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReceivedTemplateSendScreen extends ConsumerWidget {
  const ReceivedTemplateSendScreen({
    required this.templateSendId,
    super.key,
  });

  final String templateSendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = receivedTemplateSendControllerProvider(templateSendId);
    final state = ref.watch(provider);
    ref.listen<ReceivedTemplateSendState>(provider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(templateSendMessage(localizations, next.message!)),
          ),
        );
        if (next.message == TemplateSendMessage.unavailable) {
          context.go(AppRoutes.sharedTemplates);
        }
      }
    });
    final detail = state.detail.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail?.summary.snapshotName ??
              localizations.templateSendReceivedDetailTitle,
        ),
        actions: [
          IconButton(
            onPressed: state.isMutating
                ? null
                : () => ref.read(provider.notifier).load(),
            tooltip: localizations.templatesRefreshTooltip,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.detail.when(
              loading: () => Semantics(
                label: localizations.templateSendsLoading,
                liveRegion: true,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _TemplateSendLoadError(
                onRetry: () => ref.read(provider.notifier).load(),
              ),
              data: (loaded) => RefreshIndicator(
                onRefresh: () => ref.read(provider.notifier).load(),
                child: ListView(
                  key: const Key('receivedTemplateSendDetailList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                  children: [
                    _ReceivedHeader(detail: loaded),
                    const SizedBox(height: 12),
                    if (loaded.items.isEmpty)
                      const _TemplateSendEmptySnapshot(
                        key: Key('templateSendEmptySnapshot'),
                      )
                    else
                      for (final item in loaded.items)
                        Card(
                          key: ValueKey('templateSendItem-${item.position}'),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text('${item.position}'),
                            ),
                            title: Text(item.name),
                            subtitle: Text(item.quantity.format()),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: detail == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: _ReceivedActions(
                detail: detail,
                isMutating: state.isMutating,
                acceptedTemplateId:
                    state.acceptedTemplateId ?? detail.acceptedTemplateId,
                onAccept: () => ref.read(provider.notifier).accept(),
                onDecline: () => _confirmDecline(context, ref),
              ),
            ),
    );
  }

  Future<void> _confirmDecline(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.templateSendDeclineDialogTitle),
        content: Text(localizations.templateSendDeclineDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmDeclineTemplateSendButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.templateSendDeclineButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(
            receivedTemplateSendControllerProvider(templateSendId).notifier,
          )
          .decline();
    }
  }
}

class _TemplateSendDialog extends ConsumerStatefulWidget {
  const _TemplateSendDialog({required this.preview});

  final TemplateSendPreview preview;

  @override
  ConsumerState<_TemplateSendDialog> createState() =>
      _TemplateSendDialogState();
}

class _TemplateSendDialogState extends ConsumerState<_TemplateSendDialog> {
  String? _recipientId;
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider =
        templateSendComposerControllerProvider(widget.preview.templateId);
    final state = ref.watch(provider);
    final recipients = state.recipients.valueOrNull ?? const [];
    if (_recipientId != null &&
        !recipients.any((recipient) => recipient.id == _recipientId)) {
      _recipientId = null;
    }
    return AlertDialog(
      title: Text(localizations.templateSendDialogTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.templateSendDialogDescription(
                  widget.preview.name,
                  widget.preview.items.length,
                ),
              ),
              const SizedBox(height: 16),
              state.recipients.when(
                loading: () => Semantics(
                  label: localizations.templateSendRecipientsLoading,
                  liveRegion: true,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => FilledButton.tonalIcon(
                  onPressed: state.isSending
                      ? null
                      : () => ref.read(provider.notifier).loadRecipients(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(localizations.tryAgainButton),
                ),
                data: (loaded) => loaded.isEmpty
                    ? Text(localizations.templateSendNoEligibleFriends)
                    : InputDecorator(
                        decoration: InputDecoration(
                          labelText: localizations.templateSendRecipientLabel,
                        ),
                        isEmpty: _recipientId == null,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            key: const Key('templateSendRecipientField'),
                            value: _recipientId,
                            isExpanded: true,
                            items: [
                              for (final recipient in loaded)
                                DropdownMenuItem(
                                  value: recipient.id,
                                  child: Text(
                                    '${recipient.displayName} '
                                    '(@${recipient.username})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: state.isSending
                                ? null
                                : (value) =>
                                    setState(() => _recipientId = value),
                          ),
                        ),
                      ),
              ),
              if (state.hasMore) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('loadMoreTemplateSendRecipientsButton'),
                  onPressed: state.isSending || state.isLoadingMore
                      ? null
                      : () => ref.read(provider.notifier).loadMoreRecipients(),
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(localizations.templateSendsLoadMore),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                localizations.templateSendSnapshotTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(localizations.templateSendSnapshotNotice),
              const SizedBox(height: 8),
              if (widget.preview.items.isEmpty)
                Text(localizations.templateSendBlankSnapshot)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    key: const Key('templateSendSnapshotList'),
                    shrinkWrap: true,
                    itemCount: widget.preview.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.preview.items[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text('${index + 1}.'),
                        title: Text(item.name),
                        trailing: Text(item.quantity.format()),
                      );
                    },
                  ),
                ),
              if (state.message != null &&
                  state.message != TemplateSendMessage.sent) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    templateSendMessage(localizations, state.message!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.isSending ? null : () => Navigator.pop(context),
          child: Text(localizations.cancelButton),
        ),
        FilledButton.icon(
          key: const Key('confirmTemplateSendButton'),
          onPressed: state.isSending || _recipientId == null ? null : _send,
          icon: state.isSending
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: localizations.templateSendSubmitting,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: Text(localizations.templateSendButton),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final recipientId = _recipientId;
    if (recipientId == null || _closed) return;
    final succeeded = await ref
        .read(
          templateSendComposerControllerProvider(widget.preview.templateId)
              .notifier,
        )
        .send(
          recipientProfileId: recipientId,
          expectedTemplateVersion: widget.preview.templateVersion,
        );
    if (!mounted || !succeeded || _closed) return;
    _closed = true;
    Navigator.pop(context, true);
  }
}

class _ReceivedSendsView extends ConsumerWidget {
  const _ReceivedSendsView({
    required this.items,
    required this.history,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onHistoryChanged,
  });

  final List<ReceivedTemplateSendSummary> items;
  final bool history;
  final bool hasMore;
  final bool isLoadingMore;
  final ValueChanged<bool> onHistoryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TemplateSendListLayout(
      history: history,
      onHistoryChanged: onHistoryChanged,
      emptyLabel: history
          ? AppLocalizations.of(context).templateSendsNoReceivedHistory
          : AppLocalizations.of(context).templateSendsNoReceivedPending,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _TemplateSendCard(
          key: ValueKey('received-${item.id}'),
          id: item.id,
          name: item.snapshotName,
          profile: item.sender,
          state: item.state,
          itemCount: item.itemCount,
          received: true,
          onTap: () => context.push(AppRoutes.receivedTemplateSend(item.id)),
        );
      },
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      onLoadMore: () =>
          ref.read(sharedTemplateSendsControllerProvider.notifier).loadMore(
                history
                    ? TemplateSendCollection.receivedHistory
                    : TemplateSendCollection.receivedPending,
              ),
      onRefresh: () =>
          ref.read(sharedTemplateSendsControllerProvider.notifier).load(),
    );
  }
}

class _SentSendsView extends ConsumerWidget {
  const _SentSendsView({
    required this.items,
    required this.history,
    required this.hasMore,
    required this.isLoadingMore,
    required this.revokingId,
    required this.onHistoryChanged,
  });

  final List<SentTemplateSendSummary> items;
  final bool history;
  final bool hasMore;
  final bool isLoadingMore;
  final String? revokingId;
  final ValueChanged<bool> onHistoryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TemplateSendListLayout(
      history: history,
      onHistoryChanged: onHistoryChanged,
      emptyLabel: history
          ? AppLocalizations.of(context).templateSendsNoSentHistory
          : AppLocalizations.of(context).templateSendsNoSentPending,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _TemplateSendCard(
          key: ValueKey('sent-${item.id}'),
          id: item.id,
          name: item.snapshotName,
          profile: item.recipient,
          state: item.state,
          itemCount: item.itemCount,
          received: false,
          isBusy: revokingId == item.id,
          onRevoke: item.state == TemplateSendState.pending
              ? () => _confirmRevoke(context, ref, item)
              : null,
        );
      },
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      onLoadMore: () =>
          ref.read(sharedTemplateSendsControllerProvider.notifier).loadMore(
                history
                    ? TemplateSendCollection.sentHistory
                    : TemplateSendCollection.sentPending,
              ),
      onRefresh: () =>
          ref.read(sharedTemplateSendsControllerProvider.notifier).load(),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    SentTemplateSendSummary summary,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.templateSendRevokeDialogTitle),
        content: Text(
          localizations.templateSendRevokeDialogDescription(
            summary.snapshotName,
            summary.recipient.displayName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmRevokeTemplateSendButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.templateSendRevokeButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(sharedTemplateSendsControllerProvider.notifier)
          .revoke(summary);
    }
  }
}

class _TemplateSendListLayout extends StatelessWidget {
  const _TemplateSendListLayout({
    required this.history,
    required this.onHistoryChanged,
    required this.emptyLabel,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onRefresh,
  });

  final bool history;
  final ValueChanged<bool> onHistoryChanged;
  final String emptyLabel;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(localizations.templateSendsPendingFilter),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.history_rounded),
                label: Text(localizations.templateSendsHistoryFilter),
              ),
            ],
            selected: {history},
            onSelectionChanged: (selection) {
              onHistoryChanged(selection.single);
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.builder(
              key: ValueKey('templateSendList-$history-$emptyLabel'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: itemCount == 0 ? 1 : itemCount + 1,
              itemBuilder: (context, index) {
                if (itemCount == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 72),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined, size: 52),
                        const SizedBox(height: 12),
                        Text(emptyLabel, textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }
                if (index < itemCount) return itemBuilder(context, index);
                if (isLoadingMore) {
                  return Semantics(
                    label: localizations.templateSendsLoadingMore,
                    liveRegion: true,
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                if (hasMore) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.tonal(
                      key: const Key('loadMoreTemplateSendsButton'),
                      onPressed: onLoadMore,
                      child: Text(localizations.templateSendsLoadMore),
                    ),
                  );
                }
                return const SizedBox(height: 16);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TemplateSendCard extends StatelessWidget {
  const _TemplateSendCard({
    required this.id,
    required this.name,
    required this.profile,
    required this.state,
    required this.itemCount,
    required this.received,
    this.onTap,
    this.onRevoke,
    this.isBusy = false,
    super.key,
  });

  final String id;
  final String name;
  final TemplateSendProfile profile;
  final TemplateSendState state;
  final int itemCount;
  final bool received;
  final VoidCallback? onTap;
  final VoidCallback? onRevoke;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minVerticalPadding: 12,
        leading: const Icon(Icons.send_and_archive_outlined),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              received
                  ? localizations.templateSendFrom(
                      profile.displayName,
                      profile.username,
                    )
                  : localizations.templateSendTo(
                      profile.displayName,
                      profile.username,
                    ),
            ),
            Text(localizations.templatesItemCount(itemCount)),
            const SizedBox(height: 6),
            _TemplateSendStateChip(state: state),
          ],
        ),
        trailing: onRevoke == null
            ? (onTap == null ? null : const Icon(Icons.chevron_right_rounded))
            : isBusy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: Key('revokeTemplateSend-$id'),
                    onPressed: onRevoke,
                    tooltip: localizations.templateSendRevokeButton,
                    icon: const Icon(Icons.undo_rounded),
                  ),
        onTap: onTap,
      ),
    );
  }
}

class _TemplateSendStateChip extends StatelessWidget {
  const _TemplateSendStateChip({required this.state});

  final TemplateSendState state;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final (icon, label) = switch (state) {
      TemplateSendState.pending => (
          Icons.schedule_rounded,
          localizations.templateSendStatePending
        ),
      TemplateSendState.accepted => (
          Icons.check_circle_outline_rounded,
          localizations.templateSendStateAccepted
        ),
      TemplateSendState.declined => (
          Icons.cancel_outlined,
          localizations.templateSendStateDeclined
        ),
      TemplateSendState.revoked => (
          Icons.undo_rounded,
          localizations.templateSendStateRevoked
        ),
      TemplateSendState.unavailable => (
          Icons.block_rounded,
          localizations.templateSendStateUnavailable
        ),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _ReceivedHeader extends StatelessWidget {
  const _ReceivedHeader({required this.detail});

  final ReceivedTemplateSendDetail detail;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              detail.summary.snapshotName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.templateSendFrom(
                detail.summary.sender.displayName,
                detail.summary.sender.username,
              ),
            ),
            Text(localizations.templatesItemCount(detail.summary.itemCount)),
            const SizedBox(height: 8),
            _TemplateSendStateChip(state: detail.summary.state),
            const SizedBox(height: 8),
            Text(
              localizations.templateSendImmutableDetailNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedActions extends StatelessWidget {
  const _ReceivedActions({
    required this.detail,
    required this.isMutating,
    required this.acceptedTemplateId,
    required this.onAccept,
    required this.onDecline,
  });

  final ReceivedTemplateSendDetail detail;
  final bool isMutating;
  final String? acceptedTemplateId;
  final Future<bool> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (detail.summary.state == TemplateSendState.accepted &&
        acceptedTemplateId != null) {
      return FilledButton.icon(
        key: const Key('openAcceptedTemplateButton'),
        onPressed: () =>
            context.go(AppRoutes.templateDetail(acceptedTemplateId!)),
        icon: const Icon(Icons.open_in_new_rounded),
        label: Text(localizations.templateSendOpenCopyButton),
      );
    }
    if (detail.summary.state != TemplateSendState.pending) {
      return Text(
        localizations.templateSendTerminalDescription,
        textAlign: TextAlign.center,
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('declineTemplateSendButton'),
            onPressed: isMutating ? null : onDecline,
            icon: const Icon(Icons.close_rounded),
            label: Text(localizations.templateSendDeclineButton),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('acceptTemplateSendButton'),
            onPressed: isMutating ? null : onAccept,
            icon: isMutating
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: localizations.templateSendSubmitting,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(localizations.templateSendAcceptButton),
          ),
        ),
      ],
    );
  }
}

class _TemplateSendEmptySnapshot extends StatelessWidget {
  const _TemplateSendEmptySnapshot({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 52),
          const SizedBox(height: 12),
          Text(
            localizations.templateSendBlankSnapshot,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TemplateSendLoadError extends StatelessWidget {
  const _TemplateSendLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          Text(
            localizations.operationFailedMessage,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

String templateSendMessage(
  AppLocalizations localizations,
  TemplateSendMessage message,
) =>
    switch (message) {
      TemplateSendMessage.sent => localizations.templateSendSentMessage,
      TemplateSendMessage.accepted => localizations.templateSendAcceptedMessage,
      TemplateSendMessage.declined => localizations.templateSendDeclinedMessage,
      TemplateSendMessage.revoked => localizations.templateSendRevokedMessage,
      TemplateSendMessage.stale => localizations.templateSendStaleMessage,
      TemplateSendMessage.unavailable =>
        localizations.templateSendUnavailableMessage,
      TemplateSendMessage.capacity => localizations.templateSendCapacityMessage,
      TemplateSendMessage.duplicatePending =>
        localizations.templateSendDuplicatePendingMessage,
      TemplateSendMessage.retryConflict =>
        localizations.templateSendRetryConflictMessage,
      TemplateSendMessage.operationFailed =>
        localizations.operationFailedMessage,
    };
