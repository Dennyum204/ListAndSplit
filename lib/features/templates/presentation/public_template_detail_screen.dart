import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
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
        case PublicTemplatesMessage.reported:
        // The submitting flow owns the privacy confirmation and navigation.
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
              key: const Key('reportPublicTemplateButton'),
              onPressed: state.isMutating ? null : _confirmReport,
              icon: const Icon(Icons.flag_outlined),
              tooltip: localizations.publicTemplateReportAction,
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

  Future<void> _confirmReport() async {
    final localizations = AppLocalizations.of(context);
    final draft = await showDialog<_PublicTemplateReportDraft>(
      context: context,
      builder: (_) => const _PublicTemplateReportDialog(),
    );
    if (draft == null || !mounted) return;

    final reported = await ref
        .read(publicTemplateDetailControllerProvider(_location).notifier)
        .reportTemplate(draft.reason, draft.explanation);
    if (!reported || !mounted) return;

    var resultChosen = false;
    final shouldBlock = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.publicTemplateReportSuccessTitle),
        content: SingleChildScrollView(
          child: Text(localizations.publicTemplateReportSuccessDescription),
        ),
        actions: [
          TextButton(
            key: const Key('finishPublicTemplateReportButton'),
            onPressed: () {
              if (resultChosen) return;
              resultChosen = true;
              Navigator.of(dialogContext).pop(false);
            },
            child: Text(localizations.doneButton),
          ),
          FilledButton.tonalIcon(
            key: const Key('blockAfterPublicTemplateReportButton'),
            onPressed: () {
              if (resultChosen) return;
              resultChosen = true;
              Navigator.of(dialogContext).pop(true);
            },
            icon: const Icon(Icons.block_rounded),
            label: Text(localizations.communityBlockButton),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (shouldBlock == true) {
      final blocked = await ref
          .read(publicTemplateDetailControllerProvider(_location).notifier)
          .blockProfile();
      if (blocked || !mounted) return;
    }
    _exitAfterReport(localizations);
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

  void _exitAfterReport(AppLocalizations localizations) {
    if (_didExitForUnavailable) return;
    _didExitForUnavailable = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go(AppRoutes.community);
      messenger.showSnackBar(
        SnackBar(
          content: Text(localizations.publicTemplateReportSuccessMessage),
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

class _PublicTemplateReportDraft {
  const _PublicTemplateReportDraft({
    required this.reason,
    required this.explanation,
  });

  final PublicTemplateReportReason reason;
  final String? explanation;
}

class _PublicTemplateReportDialog extends StatefulWidget {
  const _PublicTemplateReportDialog();

  @override
  State<_PublicTemplateReportDialog> createState() =>
      _PublicTemplateReportDialogState();
}

class _PublicTemplateReportDialogState
    extends State<_PublicTemplateReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _explanation = TextEditingController();
  PublicTemplateReportReason _reason =
      PublicTemplateReportReason.spamScamDeceptive;
  bool _isClosing = false;

  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.publicTemplateReportDialogTitle),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(localizations.publicTemplateReportPrivacyDescription),
                const SizedBox(height: 16),
                DropdownButtonFormField<PublicTemplateReportReason>(
                  key: const Key('publicTemplateReportReason'),
                  // ignore: deprecated_member_use
                  value: _reason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: localizations.publicTemplateReportReasonLabel,
                  ),
                  items: [
                    for (final reason in PublicTemplateReportReason.values)
                      DropdownMenuItem(
                        value: reason,
                        child: Text(
                          _reportReasonLabel(localizations, reason),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (reason) {
                    if (reason != null) setState(() => _reason = reason);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('publicTemplateReportExplanation'),
                  controller: _explanation,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText:
                        localizations.publicTemplateReportExplanationLabel,
                    helperText:
                        localizations.publicTemplateReportExplanationHelper,
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (_reason.requiresExplanation && normalized.isEmpty) {
                      return localizations
                          .publicTemplateReportExplanationRequired;
                    }
                    if (normalized.characters.length > 500) {
                      return localizations
                          .publicTemplateReportExplanationTooLong;
                    }
                    return null;
                  },
                ),
                if (_reason ==
                    PublicTemplateReportReason.copyrightTrademark) ...[
                  const SizedBox(height: 8),
                  Text(
                    localizations.publicTemplateCopyrightSignalNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelPublicTemplateReportButton'),
          onPressed: _isClosing
              ? null
              : () {
                  _isClosing = true;
                  Navigator.of(context).pop();
                },
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('submitPublicTemplateReportButton'),
          onPressed: _isClosing ? null : _submit,
          child: Text(localizations.publicTemplateReportSubmitButton),
        ),
      ],
    );
  }

  void _submit() {
    if (_isClosing) return;
    if (_formKey.currentState?.validate() != true) return;
    _isClosing = true;
    final normalized = _explanation.text.trim();
    Navigator.of(context).pop(
      _PublicTemplateReportDraft(
        reason: _reason,
        explanation: normalized.isEmpty ? null : normalized,
      ),
    );
  }
}

String _reportReasonLabel(
  AppLocalizations localizations,
  PublicTemplateReportReason reason,
) =>
    switch (reason) {
      PublicTemplateReportReason.spamScamDeceptive =>
        localizations.publicTemplateReportReasonSpam,
      PublicTemplateReportReason.hateHarassmentBullying =>
        localizations.publicTemplateReportReasonHate,
      PublicTemplateReportReason.sexualContent =>
        localizations.publicTemplateReportReasonSexual,
      PublicTemplateReportReason.violenceDangerous =>
        localizations.publicTemplateReportReasonViolence,
      PublicTemplateReportReason.illegalRegulated =>
        localizations.publicTemplateReportReasonIllegal,
      PublicTemplateReportReason.personalConfidentialInformation =>
        localizations.publicTemplateReportReasonPersonalInformation,
      PublicTemplateReportReason.copyrightTrademark =>
        localizations.publicTemplateReportReasonCopyright,
      PublicTemplateReportReason.other =>
        localizations.publicTemplateReportReasonOther,
    };

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
