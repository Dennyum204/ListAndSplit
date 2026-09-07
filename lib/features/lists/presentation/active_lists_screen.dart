import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
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
    final displayName = ref.watch(ownProfileProvider).valueOrNull?.displayName;
    final PreferredSizeWidget header;
    if (displayName == null || displayName.isEmpty) {
      header = AppPageHeader(
        title: Text(localizations.listsTitle),
        actions: const [NotificationBell()],
      );
    } else {
      header = PreferredSize(
        preferredSize: Size.fromHeight(
            MediaQuery.textScalerOf(context).scale(24) * 2 + 48),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Material(
              color: Theme.of(context).appBarTheme.backgroundColor,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${localizations.listsWelcomeLabel}\n$displayName',
                        key: const Key('listsGreeting'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .appBarTheme
                            .titleTextStyle
                            ?.copyWith(height: 1.2),
                      ),
                    ),
                    const IconTheme(
                      data: IconThemeData(color: AppPalette.lightText),
                      child: NotificationBell(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: header,
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
            scrollable: true,
            titlePadding: EdgeInsets.zero,
            title: AppDialogTitle(localizations.listsCreateTitle),
            content: SingleChildScrollView(
                child: AppDialogField(
              label: localizations.listsTitleLabel,
              child: TextField(
                style: AppPalette.inputTextStyle(context),
                key: const Key('createListTitle'),
                autofocus: true,
                enabled: !state.isCreating,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  helperText: localizations.listsTitleHelper,
                ),
                onChanged: (value) => title = value,
                onSubmitted: (_) => _createList(dialogContext, title),
              ),
            )),
            actions: [
              OutlinedButton(
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
    final participantCount = summary.participantCount;
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
    final colors = Theme.of(context).colorScheme;
    final ownershipLabel = summary.isOwner
        ? localizations.listOwnedByYouLabel
        : localizations.listSharedByLabel(summary.ownerDisplayName ?? '');
    final semanticLabel = [
      summary.title,
      ownershipLabel,
      localizations.listsItemCount(summary.itemCount),
      localizations.listsCompletedCount(
          summary.completedItemCount, summary.itemCount),
      if (participantCount != null)
        localizations.listsParticipantCount(participantCount),
      timestampLabel,
    ].join('. ');
    void openList() => context.push('${AppRoutes.lists}/${summary.id}');
    return Semantics(
      key: Key('list-semantics-${summary.id}'),
      button: true,
      label: semanticLabel,
      onTap: openList,
      child: ExcludeSemantics(
          child: Card(
        key: Key('list-${summary.id}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openList,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              summary.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (participantCount != null) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: localizations
                                  .listsParticipantCount(participantCount),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$participantCount',
                                    key: Key('list-participants-${summary.id}'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: colors.primary),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(Icons.people_outline_rounded,
                                      color: colors.primary, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                key: Key('list-progress-${summary.id}'),
                                minHeight: 8,
                                color: AppPalette.orange,
                                value: summary.itemCount == 0
                                    ? 0
                                    : summary.completedItemCount /
                                        summary.itemCount,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${summary.completedItemCount} / ${summary.itemCount}',
                            key: Key('list-completion-${summary.id}'),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: colors.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.chevron_right_rounded,
                    color: colors.primary, size: 28),
              ],
            ),
          ),
        ),
      )),
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
