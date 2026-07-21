import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/presentation/active_list_members_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ActiveListMembersScreen extends ConsumerWidget {
  const ActiveListMembersScreen({required this.listId, super.key});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(activeListMembersControllerProvider(listId));
    ref.listen<ActiveListMembersState>(
      activeListMembersControllerProvider(listId),
      (previous, next) {
        if (next.message == ActiveListMembersMessage.unavailable &&
            previous?.message != ActiveListMembersMessage.unavailable) {
          context.go(AppRoutes.lists);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.listAccessRevokedMessage)),
          );
        }
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text(localizations.listMembersTitle)),
      body: SafeArea(
        child: state.data.when(
          loading: () => Center(
            child: CircularProgressIndicator(
              semanticsLabel: localizations.listMembersLoadingLabel,
            ),
          ),
          error: (_, __) => Center(
            child: FilledButton.tonal(
              key: const Key('retryListMembersButton'),
              onPressed: () => ref
                  .read(activeListMembersControllerProvider(listId).notifier)
                  .load(),
              child: Text(localizations.tryAgainButton),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () => ref
                .read(activeListMembersControllerProvider(listId).notifier)
                .load(),
            child: ListView(
              key: const Key('listMembersView'),
              padding: const EdgeInsets.all(16),
              children: [
                FormMessageBanner(
                  message: _message(localizations, state.message),
                ),
                Text(
                  localizations.listAcceptedMembersTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...data.participants.map(
                  (profile) => ListTile(
                    key: Key('participant-${profile.profileId}'),
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(profile.displayName),
                    subtitle: Text('@${profile.username}'),
                    trailing: profile.isOwner
                        ? Chip(label: Text(localizations.listOwnerLabel))
                        : data.summary.isOwner
                            ? IconButton(
                                key: Key('removeMember-${profile.profileId}'),
                                onPressed: state.busyProfileIds
                                        .contains(profile.profileId)
                                    ? null
                                    : () => _confirmRemove(
                                          context,
                                          ref,
                                          profile,
                                        ),
                                tooltip: localizations.listRemoveMemberButton,
                                icon: const Icon(Icons.person_remove_outlined),
                              )
                            : null,
                  ),
                ),
                if (data.summary.isOwner) ...[
                  const Divider(height: 32),
                  Text(
                    localizations.listPendingInvitationsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(localizations.listNoPendingInvitations),
                    ),
                  ...data.pending.map(
                    (profile) => ListTile(
                      key: Key('pending-${profile.profileId}'),
                      title: Text(profile.displayName),
                      subtitle: Text('@${profile.username}'),
                      trailing: TextButton(
                        key: Key('cancelInvitation-${profile.profileId}'),
                        onPressed: state.busyProfileIds
                                .contains(profile.profileId)
                            ? null
                            : () => ref
                                .read(
                                  activeListMembersControllerProvider(listId)
                                      .notifier,
                                )
                                .cancel(profile),
                        child: Text(localizations.listCancelInvitationButton),
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  Text(
                    localizations.listInviteFriendsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.eligible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(localizations.listNoEligibleFriends),
                    ),
                  ...data.eligible.map(
                    (profile) => ListTile(
                      key: Key('eligible-${profile.profileId}'),
                      title: Text(profile.displayName),
                      subtitle: Text('@${profile.username}'),
                      trailing: FilledButton.tonal(
                        key: Key('inviteMember-${profile.profileId}'),
                        onPressed: state.busyProfileIds
                                .contains(profile.profileId)
                            ? null
                            : () => ref
                                .read(
                                  activeListMembersControllerProvider(listId)
                                      .notifier,
                                )
                                .invite(profile),
                        child: Text(localizations.listInviteButton),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ActiveListParticipant profile,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.listRemoveMemberTitle),
        content: Text(
            localizations.listRemoveMemberDescription(profile.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmRemoveMemberButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.listRemoveMemberButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final version = profile.accessVersion;
    if (version != null) {
      await ref
          .read(activeListMembersControllerProvider(listId).notifier)
          .remove(profile, version);
    }
  }

  String? _message(
    AppLocalizations localizations,
    ActiveListMembersMessage? message,
  ) =>
      switch (message) {
        ActiveListMembersMessage.invited =>
          localizations.listInvitationSentMessage,
        ActiveListMembersMessage.invitationCancelled =>
          localizations.listInvitationCancelledMessage,
        ActiveListMembersMessage.memberRemoved =>
          localizations.listMemberRemovedMessage,
        ActiveListMembersMessage.capacityReached =>
          localizations.listCapacityReachedMessage,
        ActiveListMembersMessage.staleRefreshed =>
          localizations.listStaleMessage,
        ActiveListMembersMessage.unavailable =>
          localizations.listAccessRevokedMessage,
        ActiveListMembersMessage.operationFailed =>
          localizations.operationFailedMessage,
        null => null,
      };
}
