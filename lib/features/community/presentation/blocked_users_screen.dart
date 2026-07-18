import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(blockedUsersControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.community),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: Text(localizations.blockedUsersTitle),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    localizations.blockedUsersDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FormMessageBanner(
                    message: state.message == null
                        ? null
                        : blockedUsersMessageText(
                            localizations,
                            state.message!,
                          ),
                  ),
                  Expanded(
                    child: state.profiles.when(
                      loading: () => _LoadingState(
                        label: localizations.blockedUsersLoadingLabel,
                      ),
                      error: (_, __) => _LoadErrorState(
                        onRetry: () => ref
                            .read(blockedUsersControllerProvider.notifier)
                            .load(),
                      ),
                      data: (profiles) => profiles.isEmpty
                          ? const _EmptyState()
                          : _BlockedProfileList(
                              profiles: profiles,
                              unblockingProfileId: state.unblockingProfileId,
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

class _LoadErrorState extends ConsumerWidget {
  const _LoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            key: const Key('retryBlockedUsersButton'),
            onPressed: onRetry,
            child: Text(localizations.tryAgainButton),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            localizations.blockedUsersEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            localizations.blockedUsersEmptyDescription,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BlockedProfileList extends ConsumerWidget {
  const _BlockedProfileList({
    required this.profiles,
    required this.unblockingProfileId,
  });

  final List<BlockedProfile> profiles;
  final String? unblockingProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      key: const Key('blockedUsersList'),
      itemCount: profiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final isUnblocking = unblockingProfileId == profile.id;
        return _BlockedProfileCard(
          profile: profile,
          isUnblocking: isUnblocking,
          isEnabled: unblockingProfileId == null,
          onUnblock: () => _confirmUnblock(context, ref, profile),
        );
      },
    );
  }

  Future<void> _confirmUnblock(
    BuildContext context,
    WidgetRef ref,
    BlockedProfile profile,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(localizations.communityUnblockDialogTitle(profile.username)),
        content: Text(localizations.communityUnblockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmUnblockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityUnblockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(blockedUsersControllerProvider.notifier).unblock(profile);
    }
  }
}

class _BlockedProfileCard extends StatelessWidget {
  const _BlockedProfileCard({
    required this.profile,
    required this.isUnblocking,
    required this.isEnabled,
    required this.onUnblock,
  });

  final BlockedProfile profile;
  final bool isUnblocking;
  final bool isEnabled;
  final VoidCallback onUnblock;

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
              profile.displayName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text('@${profile.username}'),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                key: Key('unblockProfile-${profile.id}'),
                onPressed: isEnabled ? onUnblock : null,
                icon: isUnblocking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.undo_rounded),
                label: Text(localizations.communityUnblockButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
