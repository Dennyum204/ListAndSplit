import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ActiveListsScreen extends ConsumerStatefulWidget {
  const ActiveListsScreen({super.key});

  @override
  ConsumerState<ActiveListsScreen> createState() => _ActiveListsScreenState();
}

class _ActiveListsScreenState extends ConsumerState<ActiveListsScreen> {
  ActiveListStatus _status = ActiveListStatus.active;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(activeListsControllerProvider);
    final lists = state.listsFor(_status);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.listsTitle),
        actions: const [NotificationBell()],
      ),
      floatingActionButton: _status == ActiveListStatus.active
          ? FloatingActionButton.extended(
              key: const Key('createListButton'),
              onPressed: state.isCreating ? null : _showCreateDialog,
              icon: const Icon(Icons.add_rounded),
              label: Text(localizations.listsCreateButton),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<ActiveListStatus>(
                    segments: [
                      ButtonSegment(
                        value: ActiveListStatus.active,
                        label: Text(localizations.listsActiveFilter),
                        icon: const Icon(Icons.checklist_rounded),
                      ),
                      ButtonSegment(
                        value: ActiveListStatus.archived,
                        label: Text(localizations.listsArchivedFilter),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: (selection) {
                      setState(() => _status = selection.single);
                    },
                  ),
                  const SizedBox(height: 12),
                  FormMessageBanner(
                    message: _messageText(localizations, state.message),
                  ),
                  Expanded(
                    child: lists.when(
                      loading: () => Semantics(
                        liveRegion: true,
                        label: localizations.listsLoadingLabel,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => _ListsLoadError(
                        onRetry: () => ref
                            .read(activeListsControllerProvider.notifier)
                            .loadAll(),
                      ),
                      data: (entries) => _ListResults(
                        status: _status,
                        entries: entries,
                        hasMore: state.hasMoreFor(_status),
                        isLoadingMore: state.loadingMoreStatus == _status,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _messageText(
    AppLocalizations localizations,
    ActiveListsMessage? message,
  ) {
    return switch (message) {
      ActiveListsMessage.created => localizations.listsCreatedMessage,
      ActiveListsMessage.invalidTitle => localizations.listsInvalidTitleMessage,
      ActiveListsMessage.stale => localizations.listStaleMessage,
      ActiveListsMessage.operationFailed =>
        localizations.operationFailedMessage,
      null => null,
    };
  }

  Future<void> _showCreateDialog() async {
    var title = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, child) {
          final state = dialogRef.watch(activeListsControllerProvider);
          final localizations = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(localizations.listsCreateTitle),
            content: TextField(
              key: const Key('createListTitle'),
              autofocus: true,
              enabled: !state.isCreating,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: localizations.listsTitleLabel,
                helperText: localizations.listsTitleHelper,
              ),
              onChanged: (value) => title = value,
              onSubmitted: (_) => _createList(dialogContext, title),
            ),
            actions: [
              TextButton(
                onPressed: state.isCreating
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(localizations.cancelButton),
              ),
              FilledButton(
                key: const Key('confirmCreateListButton'),
                onPressed: state.isCreating
                    ? null
                    : () => _createList(dialogContext, title),
                child: state.isCreating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(localizations.listsCreateButton),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createList(BuildContext dialogContext, String title) async {
    final created =
        await ref.read(activeListsControllerProvider.notifier).create(title);
    if (created && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }
}

class _ListResults extends ConsumerWidget {
  const _ListResults({
    required this.status,
    required this.entries,
    required this.hasMore,
    required this.isLoadingMore,
  });

  final ActiveListStatus status;
  final List<ActiveListSummary> entries;
  final bool hasMore;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(activeListsControllerProvider.notifier);
    if (entries.isEmpty) {
      return _ListsEmpty(
          status: status, onRefresh: () => controller.refresh(status));
    }
    return RefreshIndicator(
      onRefresh: () => controller.refresh(status),
      child: ListView.separated(
        key: Key('${status.wireValue}Lists'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: entries.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == entries.length) {
            final localizations = AppLocalizations.of(context);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: FilledButton.tonal(
                key: const Key('loadMoreListsButton'),
                onPressed:
                    isLoadingMore ? null : () => controller.loadMore(status),
                child: isLoadingMore
                    ? Semantics(
                        label: localizations.listsLoadingMoreLabel,
                        child: const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Text(localizations.listsLoadMoreButton),
              ),
            );
          }
          return _ActiveListCard(summary: entries[index]);
        },
      ),
    );
  }
}

class _ActiveListCard extends StatelessWidget {
  const _ActiveListCard({required this.summary});

  final ActiveListSummary summary;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final timestamp = (summary.status == ActiveListStatus.active
            ? summary.updatedAt
            : summary.archivedAt!)
        .toLocal();
    final timestampLabel = summary.status == ActiveListStatus.active
        ? localizations.listsUpdatedAt(
            material.formatShortDate(timestamp),
            material.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp)),
          )
        : localizations.listsArchivedAt(
            material.formatShortDate(timestamp),
            material.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp)),
          );
    return Semantics(
      button: true,
      label:
          '${summary.title}, ${localizations.listsCompletedCount(summary.completedItemCount, summary.itemCount)}',
      child: Card(
        key: Key('list-${summary.id}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('${AppRoutes.lists}/${summary.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (summary.status == ActiveListStatus.archived)
                      const Icon(Icons.archive_outlined, size: 20),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  summary.isOwner
                      ? localizations.listOwnedByYouLabel
                      : localizations.listSharedByLabel(
                          summary.ownerDisplayName ?? '',
                        ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${localizations.listsItemCount(summary.itemCount)} · '
                  '${localizations.listsCompletedCount(summary.completedItemCount, summary.itemCount)}',
                ),
                const SizedBox(height: 4),
                Text(
                  timestampLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListsEmpty extends StatelessWidget {
  const _ListsEmpty({required this.status, required this.onRefresh});

  final ActiveListStatus status;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('listsEmptyState'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 72),
          Icon(
            status == ActiveListStatus.active
                ? Icons.playlist_add_rounded
                : Icons.archive_outlined,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            status == ActiveListStatus.active
                ? localizations.listsEmptyActiveTitle
                : localizations.listsEmptyArchivedTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            status == ActiveListStatus.active
                ? localizations.listsEmptyActiveDescription
                : localizations.listsEmptyArchivedDescription,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ListsLoadError extends StatelessWidget {
  const _ListsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 52),
          const SizedBox(height: 12),
          Text(
            localizations.listsLoadFailedTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(localizations.listsLoadFailedDescription),
          const SizedBox(height: 16),
          FilledButton.tonal(
            key: const Key('retryListsButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}
