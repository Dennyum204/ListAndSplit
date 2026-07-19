import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_ui.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class FriendshipManagementScreen extends ConsumerWidget {
  const FriendshipManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(friendshipManagementControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.community),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: Text(localizations.friendshipsTitle),
        actions: [
          const NotificationBell(),
          IconButton(
            key: const Key('refreshFriendshipsButton'),
            onPressed: () => ref
                .read(friendshipManagementControllerProvider.notifier)
                .load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.friendshipsRefreshButton,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    localizations.friendshipsDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FormMessageBanner(
                    message: state.message == null
                        ? null
                        : friendshipManagementMessageText(
                            localizations,
                            state.message!,
                          ),
                  ),
                  Expanded(
                    child: state.relationships.when(
                      loading: () => _LoadingState(
                        label: localizations.friendshipsLoadingLabel,
                      ),
                      error: (_, __) => _LoadErrorState(
                        onRetry: () => ref
                            .read(
                              friendshipManagementControllerProvider.notifier,
                            )
                            .load(),
                      ),
                      data: (_) => _RelationshipList(state: state),
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
          const Icon(Icons.cloud_off_rounded, size: 40),
          const SizedBox(height: 12),
          Text(
            localizations.operationFailedMessage,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('retryFriendshipsButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

class _RelationshipList extends ConsumerWidget {
  const _RelationshipList({required this.state});

  final FriendshipManagementState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final isCompletelyEmpty =
        state.friends.isEmpty && state.incoming.isEmpty && state.sent.isEmpty;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(friendshipManagementControllerProvider.notifier).load(),
      child: ListView(
        key: const Key('friendshipManagementList'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (isCompletelyEmpty) ...[
            const SizedBox(height: 36),
            Icon(
              Icons.people_outline_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.friendshipsEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              localizations.friendshipsEmptyDescription,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
          ],
          _RelationshipSection(
            title: localizations.friendshipsFriendsSection,
            emptyText: localizations.friendshipsFriendsEmpty,
            relationships: state.friends,
            state: state,
          ),
          const SizedBox(height: 24),
          _RelationshipSection(
            title: localizations.friendshipsIncomingSection,
            emptyText: localizations.friendshipsIncomingEmpty,
            relationships: state.incoming,
            state: state,
          ),
          const SizedBox(height: 24),
          _RelationshipSection(
            title: localizations.friendshipsSentSection,
            emptyText: localizations.friendshipsSentEmpty,
            relationships: state.sent,
            state: state,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RelationshipSection extends StatelessWidget {
  const _RelationshipSection({
    required this.title,
    required this.emptyText,
    required this.relationships,
    required this.state,
  });

  final String title;
  final String emptyText;
  final List<FriendshipSummary> relationships;
  final FriendshipManagementState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (relationships.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          for (var index = 0; index < relationships.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _RelationshipCard(
              relationship: relationships[index],
              isBusy: state.isBusy(relationships[index].id),
            ),
          ],
      ],
    );
  }
}

class _RelationshipCard extends ConsumerWidget {
  const _RelationshipCard({
    required this.relationship,
    required this.isBusy,
  });

  final FriendshipSummary relationship;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: Key('friendship-${relationship.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              relationship.displayName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text('@${relationship.username}'),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isBusy)
                  SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel:
                          localizations.friendshipActionInProgressLabel,
                    ),
                  ),
                ..._statusActions(context, ref, localizations),
                OutlinedButton.icon(
                  key: Key('blockFriend-${relationship.id}'),
                  onPressed: isBusy ? null : () => _confirmBlock(context, ref),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(localizations.communityBlockButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _statusActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
  ) {
    final controller =
        ref.read(friendshipManagementControllerProvider.notifier);
    return switch (relationship.status) {
      FriendshipStatus.incomingPending => [
          FilledButton.icon(
            key: Key('acceptFriend-${relationship.id}'),
            onPressed: isBusy ? null : () => controller.accept(relationship),
            icon: const Icon(Icons.check_rounded),
            label: Text(localizations.friendRequestAcceptButton),
          ),
          TextButton(
            key: Key('declineFriend-${relationship.id}'),
            onPressed: isBusy ? null : () => controller.decline(relationship),
            child: Text(localizations.friendRequestDeclineButton),
          ),
        ],
      FriendshipStatus.outgoingPending => [
          FilledButton.tonalIcon(
            key: Key('cancelFriend-${relationship.id}'),
            onPressed: isBusy ? null : () => controller.cancel(relationship),
            icon: const Icon(Icons.close_rounded),
            label: Text(localizations.friendRequestCancelButton),
          ),
        ],
      FriendshipStatus.friends => [
          FilledButton.tonalIcon(
            key: Key('removeFriend-${relationship.id}'),
            onPressed: isBusy ? null : () => _confirmRemove(context, ref),
            icon: const Icon(Icons.person_remove_alt_1_rounded),
            label: Text(localizations.friendshipRemoveButton),
          ),
        ],
      FriendshipStatus.canSend || FriendshipStatus.unavailable => const [],
    };
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          localizations.friendshipRemoveDialogTitle(relationship.username),
        ),
        content: Text(localizations.friendshipRemoveDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmRemoveFriendButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.friendshipRemoveButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(friendshipManagementControllerProvider.notifier)
          .end(relationship);
    }
  }

  Future<void> _confirmBlock(BuildContext context, WidgetRef ref) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          localizations.communityBlockDialogTitle(relationship.username),
        ),
        content: Text(localizations.friendshipBlockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmFriendshipBlockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(friendshipManagementControllerProvider.notifier)
          .block(relationship);
    }
  }
}
