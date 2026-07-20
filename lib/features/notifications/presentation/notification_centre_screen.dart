import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/presentation/notification_centre_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class NotificationCentreScreen extends ConsumerStatefulWidget {
  const NotificationCentreScreen({super.key});

  @override
  ConsumerState<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState
    extends ConsumerState<NotificationCentreScreen>
    with WidgetsBindingObserver {
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
      ref.read(notificationCentreControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(notificationCentreControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.lists);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: Text(localizations.notificationsTitle),
        actions: [
          IconButton(
            key: const Key('refreshNotificationsButton'),
            onPressed: () => ref
                .read(notificationCentreControllerProvider.notifier)
                .refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.notificationsRefreshButton,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    localizations.notificationsDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  FormMessageBanner(
                    message: state.message == null
                        ? null
                        : _messageText(localizations, state.message!),
                  ),
                  Expanded(
                    child: state.notifications.when(
                      loading: () => _LoadingState(
                        label: localizations.notificationsLoadingLabel,
                      ),
                      error: (_, __) => _LoadErrorState(
                        onRetry: () => ref
                            .read(
                              notificationCentreControllerProvider.notifier,
                            )
                            .load(),
                      ),
                      data: (notifications) => notifications.isEmpty
                          ? _EmptyState(
                              onRefresh: () => ref
                                  .read(
                                    notificationCentreControllerProvider
                                        .notifier,
                                  )
                                  .refresh(),
                            )
                          : _NotificationList(
                              notifications: notifications,
                              state: state,
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

  String _messageText(
    AppLocalizations localizations,
    NotificationCentreMessage message,
  ) {
    return switch (message) {
      NotificationCentreMessage.requestAccepted =>
        localizations.friendRequestAcceptedMessage,
      NotificationCentreMessage.requestDeclined =>
        localizations.friendRequestDeclinedMessage,
      NotificationCentreMessage.relationshipChanged =>
        localizations.friendshipChangedMessage,
      NotificationCentreMessage.readUpdateFailed =>
        localizations.notificationsReadFailedMessage,
      NotificationCentreMessage.operationFailed =>
        localizations.operationFailedMessage,
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  const _LoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 12),
          Text(
            localizations.operationFailedMessage,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('retryNotificationsButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('notificationsEmptyList'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 72),
          const Icon(Icons.notifications_none_rounded, size: 52),
          const SizedBox(height: 12),
          Text(
            localizations.notificationsEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            localizations.notificationsEmptyDescription,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({
    required this.notifications,
    required this.state,
  });

  final List<InAppNotification> notifications;
  final NotificationCentreState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final controller = ref.read(notificationCentreControllerProvider.notifier);
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        key: const Key('notificationCentreList'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: notifications.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index < notifications.length) {
            final notification = notifications[index];
            return _NotificationCard(
              notification: notification,
              isBusy: state.isBusy(notification.id),
            );
          }

          if (state.isLoadingMore) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: localizations.notificationsLoadingMoreLabel,
                ),
              ),
            );
          }
          if (state.paginationFailed) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.tonal(
                key: const Key('retryNotificationPageButton'),
                onPressed: controller.loadMore,
                child: Text(localizations.tryAgainButton),
              ),
            );
          }
          if (state.hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.tonal(
                key: const Key('loadMoreNotificationsButton'),
                onPressed: controller.loadMore,
                child: Text(localizations.notificationsLoadMoreButton),
              ),
            );
          }
          return const SizedBox(height: 16);
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({
    required this.notification,
    required this.isBusy,
  });

  final InAppNotification notification;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final materialLocalizations = MaterialLocalizations.of(context);
    final localCreatedAt = notification.createdAt.toLocal();
    final createdLabel = localizations.notificationsCreatedAt(
      materialLocalizations.formatShortDate(localCreatedAt),
      materialLocalizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(localCreatedAt),
      ),
    );
    return Card(
      key: Key('notification-${notification.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(
                    notification.actorDisplayName.characters.first
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.friendRequestNotificationTitle(
                          notification.actorDisplayName,
                        ),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text('@${notification.actorUsername}'),
                      const SizedBox(height: 4),
                      Text(
                        createdLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!notification.isRead)
                  Semantics(
                    label: localizations.notificationsUnreadLabel,
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.circle,
                        size: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _actions(context, ref, localizations),
          ],
        ),
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
  ) {
    final controller = ref.read(notificationCentreControllerProvider.notifier);
    return switch (notification.actionStatus) {
      NotificationActionStatus.actionable => Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isBusy)
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: localizations.friendshipActionInProgressLabel,
                ),
              ),
            FilledButton.icon(
              key: Key('acceptNotification-${notification.id}'),
              onPressed: isBusy ? null : () => controller.accept(notification),
              icon: const Icon(Icons.check_rounded),
              label: Text(localizations.friendRequestAcceptButton),
            ),
            OutlinedButton.icon(
              key: Key('declineNotification-${notification.id}'),
              onPressed: isBusy ? null : () => controller.decline(notification),
              icon: const Icon(Icons.close_rounded),
              label: Text(localizations.friendRequestDeclineButton),
            ),
          ],
        ),
      NotificationActionStatus.friends => Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Chip(
            avatar: const Icon(Icons.people_alt_rounded, size: 18),
            label: Text(localizations.friendshipStatusFriends),
          ),
        ),
      NotificationActionStatus.unavailable => Text(
          localizations.notificationUnavailableMessage,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
    };
  }
}
