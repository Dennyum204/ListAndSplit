import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_controller.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ModerationCaseScreen extends ConsumerStatefulWidget {
  const ModerationCaseScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<ModerationCaseScreen> createState() =>
      _ModerationCaseScreenState();
}

class _ModerationCaseScreenState extends ConsumerState<ModerationCaseScreen>
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
      ref.read(_provider.notifier).load();
    }
  }

  AutoDisposeStateNotifierProvider<ModerationCaseController,
          ModerationCaseState>
      get _provider => moderationCaseControllerProvider(widget.groupId);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    ref.listen<ModerationCaseState>(_provider, (previous, next) {
      if (next.message == null || next.message == previous?.message) return;
      if (next.message == ModerationMessage.accessRevoked) {
        _exitForRevocation(localizations);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(localizations, next.message!))),
        );
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.detail.valueOrNull?.reportedSnapshot.name ??
              localizations.moderationCaseTitle,
        ),
        actions: [
          IconButton(
            key: const Key('refreshModerationCaseButton'),
            onPressed: state.isMutating
                ? null
                : () => ref.read(_provider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: localizations.moderationRefreshAction,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: state.detail.when(
              loading: () => Semantics(
                label: localizations.moderationLoadingLabel,
                liveRegion: true,
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Center(
                child: FilledButton.tonal(
                  key: const Key('retryModerationCaseButton'),
                  onPressed: () => ref.read(_provider.notifier).load(),
                  child: Text(localizations.tryAgainButton),
                ),
              ),
              data: (detail) => _CaseBody(
                detail: detail,
                isMutating: state.isMutating,
                onDismiss: () => _confirmAction(
                  PublicTemplateModerationAction.dismiss,
                ),
                onTakeDown: () => _confirmAction(
                  PublicTemplateModerationAction.takeDown,
                ),
                onRestore: () => _confirmAction(
                  PublicTemplateModerationAction.restore,
                ),
                onRefresh: () => ref.read(_provider.notifier).load(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAction(PublicTemplateModerationAction action) async {
    final input = await showDialog<_ModerationActionInput>(
      context: context,
      builder: (_) => _ModerationActionDialog(action: action),
    );
    if (input == null || !mounted) return;
    final controller = ref.read(_provider.notifier);
    switch (action) {
      case PublicTemplateModerationAction.dismiss:
        await controller.dismiss(input.privateNote);
      case PublicTemplateModerationAction.takeDown:
        await controller.takeDown(input.reason!, input.privateNote);
      case PublicTemplateModerationAction.restore:
        await controller.restore(input.privateNote);
    }
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

class _CaseBody extends StatelessWidget {
  const _CaseBody({
    required this.detail,
    required this.isMutating,
    required this.onDismiss,
    required this.onTakeDown,
    required this.onRestore,
    required this.onRefresh,
  });

  final PublicTemplateModerationCase detail;
  final bool isMutating;
  final VoidCallback onDismiss;
  final VoidCallback onTakeDown;
  final VoidCallback onRestore;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final current = detail.currentTemplate;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const Key('moderationCaseScroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _StatusCard(detail: detail),
          const SizedBox(height: 12),
          Text(
            localizations.moderationReportedSnapshotTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _TemplateSnapshotCard(
            key: const Key('moderationReportedSnapshot'),
            snapshot: detail.reportedSnapshot,
          ),
          const SizedBox(height: 16),
          Text(
            localizations.moderationCurrentContentTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (current == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(localizations.moderationContentDeletedLabel),
              ),
            )
          else
            _TemplateSnapshotCard(
              key: const Key('moderationCurrentContent'),
              snapshot: ModerationTemplateSnapshot(
                name: current.name,
                items: current.items,
              ),
              status: current.isPublic
                  ? localizations.templatesPublicLabel
                  : localizations.templatesPrivateLabel,
            ),
          const SizedBox(height: 16),
          Text(
            localizations.moderationReportsTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final report in detail.reports) ...[
            _ReportCard(report: report),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          if (isMutating)
            const Center(child: CircularProgressIndicator())
          else if (detail.summary.status == 'open') ...[
            FilledButton.tonalIcon(
              key: const Key('dismissModerationCaseButton'),
              onPressed: onDismiss,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(localizations.moderationDismissAction),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('takeDownModerationCaseButton'),
              onPressed: current == null ? null : onTakeDown,
              icon: const Icon(Icons.gavel_rounded),
              label: Text(localizations.moderationTakeDownAction),
            ),
          ] else if (detail.restriction?.active == true)
            FilledButton.icon(
              key: const Key('restoreModerationCaseButton'),
              onPressed: current == null ? null : onRestore,
              icon: const Icon(Icons.restore_rounded),
              label: Text(localizations.moderationRestoreAction),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detail});

  final PublicTemplateModerationCase detail;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final labels = <String>[
      if (detail.summary.sourceChanged) localizations.moderationStatusChanged,
      if (detail.summary.sourceUnpublished)
        localizations.moderationStatusUnpublished,
      if (detail.summary.sourceDeleted)
        localizations.moderationStatusContentDeleted,
      if (detail.restriction?.active == true)
        localizations.moderationStatusTakenDown,
    ];
    if (labels.isEmpty) labels.add(localizations.moderationStatusOpen);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline_rounded),
        title: Text(
          localizations.moderationReportCount(detail.reports.length),
        ),
        subtitle: Text(labels.join(' · ')),
      ),
    );
  }
}

class _TemplateSnapshotCard extends StatelessWidget {
  const _TemplateSnapshotCard({
    required this.snapshot,
    this.status,
    super.key,
  });

  final ModerationTemplateSnapshot snapshot;
  final String? status;

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
              snapshot.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(status!),
            ],
            const SizedBox(height: 8),
            if (snapshot.items.isEmpty)
              Text(localizations.moderationNoItemsLabel)
            else
              for (final item in snapshot.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text('${item.position}')),
                  title: Text(item.name),
                  subtitle: Text(item.quantity.format()),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final ModerationReport report;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final reporter = report.reporter;
    return Card(
      key: Key('moderationReport-${report.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reporter == null
                  ? localizations.moderationDeletedReporterLabel
                  : '${reporter.displayName} (@${reporter.username})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(_reasonLabel(localizations, report.reason)),
            if (report.explanation != null) ...[
              const SizedBox(height: 8),
              Text(report.explanation!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModerationActionInput {
  const _ModerationActionInput({
    required this.privateNote,
    required this.reason,
  });

  final String privateNote;
  final PublicTemplateReportReason? reason;
}

class _ModerationActionDialog extends StatefulWidget {
  const _ModerationActionDialog({required this.action});

  final PublicTemplateModerationAction action;

  @override
  State<_ModerationActionDialog> createState() =>
      _ModerationActionDialogState();
}

class _ModerationActionDialogState extends State<_ModerationActionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  PublicTemplateReportReason _reason =
      PublicTemplateReportReason.spamScamDeceptive;
  bool _isClosing = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_actionTitle(localizations, widget.action)),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_actionDescription(localizations, widget.action)),
                if (widget.action ==
                    PublicTemplateModerationAction.takeDown) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<PublicTemplateReportReason>(
                    key: const Key('moderationOwnerReasonField'),
                    // ignore: deprecated_member_use
                    value: _reason,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: localizations.moderationOwnerReasonLabel,
                    ),
                    items: [
                      for (final reason in PublicTemplateReportReason.values)
                        DropdownMenuItem(
                          value: reason,
                          child: Text(
                            _reasonLabel(localizations, reason),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (reason) {
                      if (reason != null) setState(() => _reason = reason);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('moderationPrivateNoteField'),
                  controller: _note,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: localizations.moderationPrivateNoteLabel,
                    helperText: localizations.moderationPrivateNoteHelper,
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.isEmpty) {
                      return localizations.moderationPrivateNoteRequired;
                    }
                    if (normalized.characters.length > 1000) {
                      return localizations.moderationPrivateNoteTooLong;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelModerationActionButton'),
          onPressed: _isClosing
              ? null
              : () {
                  _isClosing = true;
                  Navigator.of(context).pop();
                },
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('confirmModerationActionButton'),
          onPressed: _isClosing ? null : _submit,
          child: Text(localizations.confirmButton),
        ),
      ],
    );
  }

  void _submit() {
    if (_isClosing) return;
    if (_formKey.currentState?.validate() != true) return;
    _isClosing = true;
    Navigator.of(context).pop(
      _ModerationActionInput(
        privateNote: _note.text.trim(),
        reason: widget.action == PublicTemplateModerationAction.takeDown
            ? _reason
            : null,
      ),
    );
  }
}

String _reasonLabel(
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

String _actionTitle(
  AppLocalizations localizations,
  PublicTemplateModerationAction action,
) =>
    switch (action) {
      PublicTemplateModerationAction.dismiss =>
        localizations.moderationDismissDialogTitle,
      PublicTemplateModerationAction.takeDown =>
        localizations.moderationTakeDownDialogTitle,
      PublicTemplateModerationAction.restore =>
        localizations.moderationRestoreDialogTitle,
    };

String _actionDescription(
  AppLocalizations localizations,
  PublicTemplateModerationAction action,
) =>
    switch (action) {
      PublicTemplateModerationAction.dismiss =>
        localizations.moderationDismissDialogDescription,
      PublicTemplateModerationAction.takeDown =>
        localizations.moderationTakeDownDialogDescription,
      PublicTemplateModerationAction.restore =>
        localizations.moderationRestoreDialogDescription,
    };

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
