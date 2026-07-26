import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_controller.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  ConsumerState<ModerationQueueScreen> createState() =>
      _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen>
    with WidgetsBindingObserver {
  bool _didExitForRevocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(moderationQueueControllerProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(moderationQueueControllerProvider);
    ref.listen<ModerationQueueState>(
      moderationQueueControllerProvider,
      (previous, next) {
        if (next.message == previous?.message || next.message == null) return;
        if (next.message == ModerationMessage.accessRevoked) {
          _exitForRevocation(localizations);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_message(localizations, next.message!))),
          );
        }
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.moderationTitle),
        actions: [
          IconButton(
            key: const Key('refreshModerationQueueButton'),
            onPressed: state.isLoadingMore
                ? null
                : () =>
                    ref.read(moderationQueueControllerProvider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.moderationRefreshAction,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    localizations.moderationQueueDescription,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    key: const Key('moderationQueueFilters'),
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in ModerationQueueFilter.values)
                        ChoiceChip(
                          key: Key(
                            'moderationFilter-${filter.wireValue}',
                          ),
                          label: Text(_filterLabel(localizations, filter)),
                          selected: state.filter == filter,
                          onSelected: state.isLoadingMore
                              ? null
                              : (selected) {
                                  if (selected) {
                                    ref
                                        .read(
                                          moderationQueueControllerProvider
                                              .notifier,
                                        )
                                        .selectFilter(filter);
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: state.page.when(
                      loading: () => Semantics(
                        label: localizations.moderationLoadingLabel,
                        liveRegion: true,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (_, __) => _QueueError(
                        onRetry: () => ref
                            .read(
                              moderationQueueControllerProvider.notifier,
                            )
                            .load(),
                      ),
                      data: (page) => _QueueList(
                        page: page,
                        isLoadingMore: state.isLoadingMore,
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

  void _exitForRevocation(AppLocalizations localizations) {
    if (_didExitForRevocation) return;
    _didExitForRevocation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go(AppRoutes.profile);
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.moderationAccessRemovedMessage)),
      );
    });
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({
    required this.page,
    required this.isLoadingMore,
  });

  final ModerationQueuePage page;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    if (page.cases.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(moderationQueueControllerProvider.notifier).load(),
        child: ListView(
          key: const Key('moderationQueueEmpty'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 72),
            const Icon(Icons.fact_check_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              localizations.moderationQueueEmptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              localizations.moderationQueueEmptyDescription,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(moderationQueueControllerProvider.notifier).load(),
      child: ListView.separated(
        key: const Key('moderationQueueList'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: page.cases.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == page.cases.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (page.nextCursor != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FilledButton.tonal(
                  key: const Key('loadMoreModerationCasesButton'),
                  onPressed: () => ref
                      .read(moderationQueueControllerProvider.notifier)
                      .loadMore(),
                  child: Text(localizations.moderationLoadMoreAction),
                ),
              );
            }
            return const SizedBox(height: 16);
          }
          final item = page.cases[index];
          final status = _caseStatus(localizations, item);
          return Semantics(
            button: true,
            label: localizations.moderationCaseSemantics(
              item.templateName,
              item.reportCount,
              status,
            ),
            child: Card(
              child: ListTile(
                key: Key('moderationCase-${item.groupId}'),
                leading: Icon(
                  item.isRestricted ? Icons.gavel_rounded : Icons.flag_outlined,
                ),
                title: Text(item.templateName, maxLines: 2),
                subtitle: Text(
                  '${localizations.moderationReportCount(item.reportCount)}\n'
                  '$status',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(
                  AppRoutes.moderationCase(item.groupId),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QueueError extends StatelessWidget {
  const _QueueError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 44),
          const SizedBox(height: 12),
          Text(
            localizations.moderationLoadFailedMessage,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('retryModerationQueueButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

String _filterLabel(
  AppLocalizations localizations,
  ModerationQueueFilter filter,
) =>
    switch (filter) {
      ModerationQueueFilter.open => localizations.moderationFilterOpen,
      ModerationQueueFilter.takenDown =>
        localizations.moderationFilterTakenDown,
      ModerationQueueFilter.closed => localizations.moderationFilterClosed,
    };

String _caseStatus(
  AppLocalizations localizations,
  ModerationQueueCase item,
) {
  if (item.isRestricted) return localizations.moderationStatusTakenDown;
  if (item.sourceDeleted) return localizations.moderationStatusContentDeleted;
  if (item.status == 'dismissed') {
    return localizations.moderationStatusDismissed;
  }
  if (item.status == 'taken_down') {
    return localizations.moderationStatusRestored;
  }
  if (item.sourceUnpublished) {
    return localizations.moderationStatusUnpublished;
  }
  if (item.sourceChanged) return localizations.moderationStatusChanged;
  return localizations.moderationStatusOpen;
}

String _message(
  AppLocalizations localizations,
  ModerationMessage message,
) =>
    switch (message) {
      ModerationMessage.dismissed => localizations.moderationDismissedMessage,
      ModerationMessage.takenDown => localizations.moderationTakenDownMessage,
      ModerationMessage.restored => localizations.moderationRestoredMessage,
      ModerationMessage.staleRefreshed => localizations.moderationStaleMessage,
      ModerationMessage.accessRevoked =>
        localizations.moderationAccessRemovedMessage,
      ModerationMessage.operationFailed =>
        localizations.moderationOperationFailedMessage,
    };
