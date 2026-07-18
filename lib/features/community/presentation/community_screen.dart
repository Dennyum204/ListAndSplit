import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/community/presentation/community_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(communitySearchControllerProvider);
    return FormPageFrame(
      title: localizations.communityTitle,
      description: localizations.communityDescription,
      leading: IconButton(
        onPressed: () => context.go(AppRoutes.foundation),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('manageFriendshipsButton'),
                  onPressed: state.isBusy
                      ? null
                      : () => context.go(AppRoutes.friendships),
                  icon: const Icon(Icons.people_alt_outlined),
                  label: Text(localizations.manageFriendshipsButton),
                ),
                TextButton.icon(
                  key: const Key('manageBlockedUsersButton'),
                  onPressed: state.isBusy
                      ? null
                      : () => context.go(AppRoutes.blockedUsers),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(localizations.manageBlockedUsersButton),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FormMessageBanner(
            message: state.message == null
                ? null
                : communitySearchMessageText(
                    localizations,
                    state.message!,
                  ),
          ),
          TextField(
            key: const Key('communityUsername'),
            controller: _username,
            enabled: !state.isBusy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.search,
            onChanged: (_) => ref
                .read(communitySearchControllerProvider.notifier)
                .clearResultForEditedQuery(),
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: localizations.usernameLabel,
              helperText: localizations.communityUsernameHelper,
              prefixIcon: const Icon(Icons.person_search_rounded),
              errorText: state.usernameError == null
                  ? null
                  : communityUsernameValidationText(
                      localizations,
                      state.usernameError!,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          SubmissionButton(
            label: localizations.communitySearchButton,
            isSubmitting: state.isSearching,
            onPressed: state.isBusy ? null : _search,
          ),
          if (state.result != null) ...[
            const SizedBox(height: 24),
            _DiscoveryResultCard(
              profile: state.result!,
              relationship: state.relationship,
              activeAction: state.activeAction,
              isBusy: state.isBusy,
              onBlock: _confirmBlock,
              onSend: () => ref
                  .read(communitySearchControllerProvider.notifier)
                  .sendFriendRequest(),
              onCancel: () => ref
                  .read(communitySearchControllerProvider.notifier)
                  .cancelFriendRequest(),
              onAccept: () => ref
                  .read(communitySearchControllerProvider.notifier)
                  .acceptFriendRequest(),
              onDecline: () => ref
                  .read(communitySearchControllerProvider.notifier)
                  .declineFriendRequest(),
            ),
          ],
        ],
      ),
    );
  }

  void _search() {
    ref.read(communitySearchControllerProvider.notifier).search(_username.text);
  }

  Future<void> _confirmBlock() async {
    final profile = ref.read(communitySearchControllerProvider).result;
    if (profile == null) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.communityBlockDialogTitle(profile.username)),
        content: Text(localizations.communityBlockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmBlockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(communitySearchControllerProvider.notifier).blockResult();
    }
  }
}

class _DiscoveryResultCard extends StatelessWidget {
  const _DiscoveryResultCard({
    required this.profile,
    required this.relationship,
    required this.activeAction,
    required this.isBusy,
    required this.onBlock,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.onDecline,
  });

  final DiscoveredProfile profile;
  final FriendshipSummary? relationship;
  final CommunitySearchAction? activeAction;
  final bool isBusy;
  final VoidCallback onBlock;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Card(
      key: const Key('communitySearchResult'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              profile.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '@${profile.username}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._relationshipActions(context, localizations),
                FilledButton.tonalIcon(
                  key: const Key('blockSearchResultButton'),
                  onPressed: isBusy ? null : onBlock,
                  icon: activeAction == null && isBusy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel:
                                localizations.friendshipActionInProgressLabel,
                          ),
                        )
                      : const Icon(Icons.block_rounded),
                  label: Text(localizations.communityBlockButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _relationshipActions(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    return switch (relationship?.status) {
      FriendshipStatus.canSend => [
          FilledButton.icon(
            key: const Key('sendFriendRequestButton'),
            onPressed: isBusy ? null : onSend,
            icon: _actionIcon(
              CommunitySearchAction.send,
              Icons.person_add_alt_1_rounded,
              localizations.friendshipActionInProgressLabel,
            ),
            label: Text(localizations.friendRequestSendButton),
          ),
        ],
      FriendshipStatus.outgoingPending => [
          FilledButton.tonalIcon(
            key: const Key('cancelFriendRequestButton'),
            onPressed: isBusy ? null : onCancel,
            icon: _actionIcon(
              CommunitySearchAction.cancel,
              Icons.close_rounded,
              localizations.friendshipActionInProgressLabel,
            ),
            label: Text(localizations.friendRequestCancelButton),
          ),
        ],
      FriendshipStatus.incomingPending => [
          FilledButton.icon(
            key: const Key('acceptFriendRequestButton'),
            onPressed: isBusy ? null : onAccept,
            icon: _actionIcon(
              CommunitySearchAction.accept,
              Icons.check_rounded,
              localizations.friendshipActionInProgressLabel,
            ),
            label: Text(localizations.friendRequestAcceptButton),
          ),
          OutlinedButton.icon(
            key: const Key('declineFriendRequestButton'),
            onPressed: isBusy ? null : onDecline,
            icon: _actionIcon(
              CommunitySearchAction.decline,
              Icons.close_rounded,
              localizations.friendshipActionInProgressLabel,
            ),
            label: Text(localizations.friendRequestDeclineButton),
          ),
        ],
      FriendshipStatus.friends => [
          Chip(
            avatar: const Icon(Icons.people_alt_rounded, size: 18),
            label: Text(localizations.friendshipStatusFriends),
          ),
        ],
      FriendshipStatus.unavailable || null => [
          Text(
            localizations.friendshipUnavailableMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
    };
  }

  Widget _actionIcon(
    CommunitySearchAction action,
    IconData icon,
    String progressLabel,
  ) {
    if (activeAction == action) {
      return SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: progressLabel,
        ),
      );
    }
    return Icon(icon);
  }
}
