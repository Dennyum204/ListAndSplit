import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/presentation/friend_public_template_feed_controller.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class FriendPublicTemplateFeedScreen extends ConsumerWidget {
  const FriendPublicTemplateFeedScreen({
    this.isCommunityHome = false,
    super.key,
  });

  final bool isCommunityHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(friendPublicTemplateFeedControllerProvider);
    ref.listen<FriendPublicTemplateFeedState>(
      friendPublicTemplateFeedControllerProvider,
      (previous, next) {
        if (next.message == null || next.message == previous?.message) return;
        final text = switch (next.message!) {
          FriendPublicTemplateFeedMessage.refreshFailed =>
            localizations.friendTemplatesRefreshFailed,
          FriendPublicTemplateFeedMessage.loadMoreFailed =>
            localizations.friendTemplatesLoadMoreFailed,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      },
    );
    return Scaffold(
      appBar: AppPageHeader(
        automaticallyImplyLeading: false,
        leading: isCommunityHome
            ? null
            : IconButton(
                onPressed: () => _goBack(context),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
        title: Text(isCommunityHome
            ? localizations.shellCommunityTab
            : localizations.friendTemplatesTitle),
        actions: [
          if (isCommunityHome)
            IconButton(
              key: const Key('openCommunityFriendsButton'),
              onPressed: () => context.push(AppRoutes.communityFriends),
              icon: const Icon(Icons.people_outline_rounded),
              tooltip: localizations.communitySearchButton,
            ),
          IconButton(
            key: const Key('refreshFriendTemplatesButton'),
            onPressed: state.isBusy
                ? null
                : () => ref
                    .read(friendPublicTemplateFeedControllerProvider.notifier)
                    .load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.friendTemplatesRefreshTooltip,
          ),
          if (isCommunityHome) const NotificationBell(),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.page.when(
              loading: () => Semantics(
                label: localizations.friendTemplatesLoadingLabel,
                liveRegion: true,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _FriendTemplateFeedError(
                onRetry: () => ref
                    .read(friendPublicTemplateFeedControllerProvider.notifier)
                    .load(),
              ),
              data: (page) => RefreshIndicator(
                onRefresh: () => ref
                    .read(friendPublicTemplateFeedControllerProvider.notifier)
                    .load(),
                child: ListView(
                  key: const Key('friendTemplateFeedList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Text(
                      localizations.friendTemplatesDescription,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    if (page.entries.isEmpty)
                      const _FriendTemplateFeedEmpty()
                    else
                      for (final entry in page.entries) ...[
                        _FriendTemplateCard(entry: entry),
                        const SizedBox(height: 8),
                      ],
                    if (page.nextCursor != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        button: true,
                        label: state.isLoadingMore
                            ? localizations.friendTemplatesLoadingMoreLabel
                            : state.loadMoreFailed
                                ? localizations.friendTemplatesRetryLoadMore
                                : localizations.friendTemplatesLoadMore,
                        child: FilledButton.tonalIcon(
                          key: const Key('loadMoreFriendTemplatesButton'),
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                  .read(
                                    friendPublicTemplateFeedControllerProvider
                                        .notifier,
                                  )
                                  .loadMore(),
                          icon: state.isLoadingMore
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  state.loadMoreFailed
                                      ? Icons.refresh_rounded
                                      : Icons.expand_more_rounded,
                                ),
                          label: Text(
                            state.isLoadingMore
                                ? localizations.friendTemplatesLoadingMoreLabel
                                : state.loadMoreFailed
                                    ? localizations.friendTemplatesRetryLoadMore
                                    : localizations.friendTemplatesLoadMore,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.community);
    }
  }
}

class _FriendTemplateCard extends StatelessWidget {
  const _FriendTemplateCard({required this.entry});

  final FriendPublicTemplateEntry entry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final template = entry.template;
    final profile = entry.profile;
    final publishedDate = MaterialLocalizations.of(context)
        .formatMediumDate(template.publishedAt.toLocal());
    return AppSectionCard(
      key: Key('friendTemplateCard-${template.id}'),
      tonal: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: localizations.friendTemplatesOwnerSemantics(
              profile.displayName,
              profile.username,
            ),
            child: InkWell(
              key: Key('openFriendTemplateOwner-${profile.id}'),
              onTap: () => context.push(AppRoutes.publicProfile(profile.id)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      IdentityBadge(label: profile.displayName, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.displayName,
                                style: Theme.of(context).textTheme.labelLarge),
                            Text('@${profile.username}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          localizations.publicTemplatesViewProfileButton,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: localizations.friendTemplatesCardSemantics(
              template.name,
              profile.displayName,
              profile.username,
              template.itemCount,
              publishedDate,
            ),
            child: InkWell(
              key: Key('openFriendTemplate-${template.id}'),
              onTap: () => context.push(
                AppRoutes.publicTemplate(profile.id, template.id),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(template.name,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          localizations
                              .publicTemplatesPublishedAt(publishedDate),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          localizations.templatesItemCount(template.itemCount),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendTemplateFeedEmpty extends StatelessWidget {
  const _FriendTemplateFeedEmpty();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            localizations.friendTemplatesEmptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            localizations.friendTemplatesEmptyDescription,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FriendTemplateFeedError extends StatelessWidget {
  const _FriendTemplateFeedError({required this.onRetry});

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
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              localizations.friendTemplatesInitialError,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('retryFriendTemplatesButton'),
              onPressed: onRetry,
              child: Text(localizations.templatesRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}
