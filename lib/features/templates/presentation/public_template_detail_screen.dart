import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_templates_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class PublicTemplateDetailScreen extends ConsumerStatefulWidget {
  const PublicTemplateDetailScreen({
    required this.profileId,
    required this.templateId,
    super.key,
  });

  final String profileId;
  final String templateId;

  @override
  ConsumerState<PublicTemplateDetailScreen> createState() =>
      _PublicTemplateDetailScreenState();
}

class _PublicTemplateDetailScreenState
    extends ConsumerState<PublicTemplateDetailScreen> {
  bool _didExitForUnavailable = false;
  final Set<String> _announcedCopies = {};

  PublicTemplateLocation get _location => PublicTemplateLocation(
        profileId: widget.profileId,
        templateId: widget.templateId,
      );

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = publicTemplateDetailControllerProvider(_location);
    final state = ref.watch(provider);
    final detail = state.detail.valueOrNull;
    final ownUserId = ref.watch(verifiedUserIdProvider);
    final accessLossGuard = ref.watch(
      publicTemplateAccessLossGuardProvider(widget.profileId),
    );
    ref.listen<PublicTemplateDetailState>(provider, (previous, next) {
      if (next.message == null || next.message == previous?.message) return;
      switch (next.message!) {
        case PublicTemplatesMessage.unavailable:
          _exitForUnavailable(localizations, accessLossGuard);
        case PublicTemplatesMessage.copied:
          final copiedId = next.copiedTemplateId;
          if (copiedId != null && _announcedCopies.add(copiedId)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.publicTemplatesCopiedMessage),
                action: SnackBarAction(
                  label: localizations.publicTemplatesOpenCopyButton,
                  onPressed: () =>
                      context.go(AppRoutes.templateDetail(copiedId)),
                ),
              ),
            );
          }
        case PublicTemplatesMessage.staleReview:
          _showMessage(localizations.publicTemplatesStaleMessage);
        case PublicTemplatesMessage.capacity:
          _showMessage(localizations.publicTemplatesCapacityMessage);
        case PublicTemplatesMessage.operationFailed:
          _showMessage(localizations.publicTemplatesOperationFailed);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail?.summary.name ?? localizations.publicTemplatesDetailTitle,
        ),
        actions: [
          IconButton(
            key: const Key('refreshPublicTemplateButton'),
            onPressed: state.isMutating
                ? null
                : () => ref.read(provider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.publicTemplatesRefreshTooltip,
          ),
          if (detail != null && ownUserId != widget.profileId)
            IconButton(
              key: const Key('blockPublicTemplateOwnerButton'),
              onPressed: state.isMutating ? null : _confirmBlock,
              icon: const Icon(Icons.block_rounded),
              tooltip: localizations.communityBlockButton,
            ),
        ],
      ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('savePublicTemplateCopyButton'),
              onPressed: state.isMutating ? null : _confirmCopy,
              tooltip: localizations.publicTemplatesSaveCopyButton,
              icon: state.isMutating
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_copy_rounded),
              label: Text(localizations.publicTemplatesSaveCopyButton),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: state.detail.when(
              loading: () => Semantics(
                label: localizations.publicTemplatesLoadingLabel,
                liveRegion: true,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _PublicDetailLoadError(
                onRetry: () => ref.read(provider.notifier).load(),
              ),
              data: (loaded) => RefreshIndicator(
                onRefresh: () => ref.read(provider.notifier).load(),
                child: CustomScrollView(
                  key: const Key('publicTemplateDetailScroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  label: localizations
                                      .publicTemplatesOwnerSemantics(
                                    loaded.profile.displayName,
                                    loaded.profile.username,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.person_outline_rounded),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              loaded.profile.displayName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            Text(
                                              '@${loaded.profile.username}',
                                              key: const Key(
                                                'publicTemplateOwnerUsername',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Chip(
                                  avatar: const Icon(
                                    Icons.public_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    localizations.templatesPublicLabel,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  localizations.templatesItemCount(
                                    loaded.items.length,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (loaded.items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  localizations.publicTemplatesDetailEmptyTitle,
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  localizations
                                      .publicTemplatesDetailEmptyDescription,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                        sliver: SliverList.builder(
                          itemCount: loaded.items.length,
                          itemBuilder: (context, index) {
                            final item = loaded.items[index];
                            final quantity = item.quantity.format();
                            return Semantics(
                              label: localizations.publicTemplatesItemSemantics(
                                item.name,
                                quantity,
                              ),
                              child: Card(
                                key: Key('publicTemplateItem-$index'),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(item.name, maxLines: 2),
                                  subtitle: Text(quantity),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCopy() async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.publicTemplatesCopyDialogTitle),
        content: SingleChildScrollView(
          child: Text(localizations.publicTemplatesCopyDialogDescription),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmSavePublicTemplateCopyButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.publicTemplatesSaveCopyButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(publicTemplateDetailControllerProvider(_location).notifier)
          .copyTemplate();
    }
  }

  Future<void> _confirmBlock() async {
    final detail = ref
        .read(publicTemplateDetailControllerProvider(_location))
        .detail
        .valueOrNull;
    if (detail == null) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          localizations.communityBlockDialogTitle(detail.profile.username),
        ),
        content: Text(localizations.communityBlockDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmPublicTemplateOwnerBlockButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(publicTemplateDetailControllerProvider(_location).notifier)
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _PublicDetailLoadError extends StatelessWidget {
  const _PublicDetailLoadError({required this.onRetry});

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
              key: const Key('retryPublicTemplateButton'),
              onPressed: onRetry,
              child: Text(localizations.templatesRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}
