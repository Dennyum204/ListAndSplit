import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_templates_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class PublicTemplateProfileScreen extends ConsumerStatefulWidget {
  const PublicTemplateProfileScreen({
    required this.profileId,
    super.key,
  });

  final String profileId;

  @override
  ConsumerState<PublicTemplateProfileScreen> createState() =>
      _PublicTemplateProfileScreenState();
}

class _PublicTemplateProfileScreenState
    extends ConsumerState<PublicTemplateProfileScreen> {
  bool _didExitForUnavailable = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = publicProfileTemplatesControllerProvider(widget.profileId);
    final state = ref.watch(provider);
    final ownUserId = ref.watch(verifiedUserIdProvider);
    final accessLossGuard = ref.watch(
      publicTemplateAccessLossGuardProvider(widget.profileId),
    );
    ref.listen<PublicProfileTemplatesState>(provider, (previous, next) {
      if (next.message == previous?.message || next.message == null) return;
      if (next.message == PublicTemplatesMessage.unavailable) {
        _exitForUnavailable(localizations, accessLossGuard);
      } else if (next.message == PublicTemplatesMessage.operationFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.publicTemplatesOperationFailed)),
        );
      }
    });
    final page = state.page.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: Text(
          page?.profile.displayName ??
              localizations.publicTemplatesProfileTitle,
        ),
        actions: [
          IconButton(
            key: const Key('refreshPublicProfileButton'),
            onPressed:
                state.isBusy ? null : () => ref.read(provider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.publicTemplatesRefreshTooltip,
          ),
          if (page != null && ownUserId != widget.profileId)
            IconButton(
              key: const Key('blockPublicProfileButton'),
              onPressed: state.isBusy ? null : _confirmBlock,
              icon: const Icon(Icons.block_rounded),
              tooltip: localizations.communityBlockButton,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.page.when(
              loading: () => Semantics(
                label: localizations.publicTemplatesLoadingLabel,
                liveRegion: true,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _PublicTemplateLoadError(
                onRetry: () => ref.read(provider.notifier).load(),
              ),
              data: (loaded) => RefreshIndicator(
                onRefresh: () => ref.read(provider.notifier).load(),
                child: ListView(
                  key: const Key('publicProfileTemplateList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        loaded.profile.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${loaded.profile.username}',
                      key: const Key('publicProfileUsername'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(localizations.publicTemplatesProfileDescription),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        localizations.publicTemplatesSectionTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (loaded.templates.isEmpty)
                      _PublicTemplateEmptyState(
                        title: localizations.publicTemplatesEmptyTitle,
                        description:
                            localizations.publicTemplatesEmptyDescription,
                      )
                    else
                      for (final template in loaded.templates) ...[
                        _PublicTemplateCard(
                          profileId: widget.profileId,
                          template: template,
                        ),
                        const SizedBox(height: 8),
                      ],
                    if (loaded.nextCursor != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        button: true,
                        label: state.isLoadingMore
                            ? localizations.publicTemplatesLoadingMoreLabel
                            : localizations.publicTemplatesLoadMoreButton,
                        child: FilledButton.tonalIcon(
                          key: const Key('loadMorePublicTemplatesButton'),
                          onPressed: state.isBusy
                              ? null
                              : () => ref.read(provider.notifier).loadMore(),
                          icon: state.isLoadingMore
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(
                            state.isLoadingMore
                                ? localizations.publicTemplatesLoadingMoreLabel
                                : localizations.publicTemplatesLoadMoreButton,
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

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.community);
    }
  }

  Future<void> _confirmBlock() async {
    final page = ref
        .read(publicProfileTemplatesControllerProvider(widget.profileId))
        .page
        .valueOrNull;
    if (page == null) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          localizations.communityBlockDialogTitle(page.profile.username),
        ),
        content: Text(localizations.communityBlockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmPublicProfileBlockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(
            publicProfileTemplatesControllerProvider(widget.profileId).notifier,
          )
          .blockProfile();
    }
  }

  void _exitForUnavailable(
    AppLocalizations localizations,
    PublicTemplateAccessLossGuard accessLossGuard,
  ) {
    if (_didExitForUnavailable || !accessLossGuard.tryClaim()) return;
    _didExitForUnavailable = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go(AppRoutes.community);
      messenger.showSnackBar(
        SnackBar(
          content: Text(localizations.publicTemplatesUnavailableMessage),
        ),
      );
    });
  }
}

class _PublicTemplateCard extends StatelessWidget {
  const _PublicTemplateCard({
    required this.profileId,
    required this.template,
  });

  final String profileId;
  final PublicTemplateSummary template;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final publishedDate = MaterialLocalizations.of(context)
        .formatMediumDate(template.publishedAt.toLocal());
    return Semantics(
      button: true,
      label: localizations.publicTemplatesCardSemantics(
        template.name,
        template.itemCount,
        publishedDate,
      ),
      child: Card(
        key: Key('publicTemplate-${template.id}'),
        child: ListTile(
          minVerticalPadding: 12,
          leading: const Icon(Icons.public_rounded),
          title: Text(template.name, maxLines: 2),
          subtitle: Text(
            '${localizations.templatesItemCount(template.itemCount)}\n'
            '${localizations.publicTemplatesPublishedAt(publishedDate)}',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(
            AppRoutes.publicTemplate(profileId, template.id),
          ),
        ),
      ),
    );
  }
}

class _PublicTemplateEmptyState extends StatelessWidget {
  const _PublicTemplateEmptyState({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.public_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(description, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PublicTemplateLoadError extends StatelessWidget {
  const _PublicTemplateLoadError({required this.onRetry});

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
              localizations.publicTemplatesOperationFailed,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('retryPublicProfileButton'),
              onPressed: onRetry,
              child: Text(localizations.templatesRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}
