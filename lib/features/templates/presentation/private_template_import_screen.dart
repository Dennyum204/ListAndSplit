import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/private_templates_controller.dart';
import 'package:list_and_split/features/templates/presentation/template_selection_dialog.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class PrivateTemplateImportScreen extends ConsumerStatefulWidget {
  const PrivateTemplateImportScreen({
    required this.destinationListId,
    required this.templateId,
    super.key,
  });

  final String destinationListId;
  final String templateId;

  @override
  ConsumerState<PrivateTemplateImportScreen> createState() =>
      _PrivateTemplateImportScreenState();
}

class _PrivateTemplateImportScreenState
    extends ConsumerState<PrivateTemplateImportScreen> {
  bool _running = false;
  bool _completed = false;
  bool _failedToPrepare = false;
  bool _previewOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runImportFlow());
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      privateTemplateDetailControllerProvider(widget.templateId),
    );
    final templateName = state.detail.valueOrNull?.summary.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(templateName ?? localizations.templatesImportTitle),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _failedToPrepare
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync_problem_rounded, size: 52),
                      const SizedBox(height: 16),
                      Text(
                        localizations.templatesUnavailableMessage,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        key: const Key('retryFixedTemplateImportButton'),
                        onPressed: _running ? null : _runImportFlow,
                        child: Text(localizations.templatesRetryButton),
                      ),
                    ],
                  )
                : _previewOpen
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_all_outlined, size: 52),
                          const SizedBox(height: 12),
                          Text(localizations.templatesImportTitle),
                        ],
                      )
                    : Semantics(
                        liveRegion: true,
                        label: localizations.templatesImportTitle,
                        child: const CircularProgressIndicator(),
                      ),
          ),
        ),
      ),
    );
  }

  Future<void> _runImportFlow() async {
    if (_running || _completed || !mounted) return;
    setState(() {
      _running = true;
      _failedToPrepare = false;
    });
    final provider = privateTemplateDetailControllerProvider(widget.templateId);
    final controller = ref.read(provider.notifier);
    await controller.load();
    if (!mounted) return;
    final prepared = await controller.prepareImport(widget.destinationListId);
    if (!mounted) return;
    if (!prepared) {
      setState(() {
        _running = false;
        _failedToPrepare = true;
      });
      return;
    }

    while (mounted && !_completed) {
      final state = ref.read(provider);
      final detail = state.detail.valueOrNull;
      final destination = state.destination;
      if (detail == null || destination == null) {
        setState(() {
          _running = false;
          _failedToPrepare = true;
        });
        return;
      }
      setState(() => _previewOpen = true);
      final selection = await showDialog<TemplateSelectionInput>(
        context: context,
        builder: (_) => Consumer(
          builder: (context, dialogRef, _) {
            final liveState = dialogRef.watch(provider);
            final liveDetail = liveState.detail.valueOrNull ?? detail;
            final liveDestination = liveState.destination;
            return TemplateSelectionDialog(
              title: AppLocalizations.of(context).templatesImportTitle,
              items: liveDetail.items,
              remainingCapacity: liveDestination?.remainingCapacity ??
                  destination.remainingCapacity,
              destinationName: liveDestination?.detail.summary.title ??
                  destination.detail.summary.title,
              duplicateIds: liveDestination?.duplicateItemIds ??
                  destination.duplicateItemIds,
              submissionEnabled: liveDestination != null &&
                  liveState.message != PrivateTemplatesMessage.unavailable,
              confirmLabel:
                  AppLocalizations.of(context).templatesConfirmImportButton,
            );
          },
        ),
      );
      if (!mounted) return;
      setState(() => _previewOpen = false);
      if (selection == null) {
        _completed = true;
        context.pop(false);
        return;
      }

      final imported = await controller.importSelected(selection.selectedIds);
      if (!mounted) return;
      if (imported) {
        _completed = true;
        context.pop(true);
        return;
      }

      final refreshed = ref.read(provider);
      final message = refreshed.message;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _importMessage(AppLocalizations.of(context), message),
            ),
          ),
        );
      }
      if (refreshed.detail.valueOrNull == null ||
          refreshed.destination == null) {
        setState(() {
          _running = false;
          _failedToPrepare = true;
        });
        return;
      }
    }
  }
}

String _importMessage(
  AppLocalizations localizations,
  PrivateTemplatesMessage message,
) {
  return switch (message) {
    PrivateTemplatesMessage.capacity => localizations.templatesCapacityReached,
    PrivateTemplatesMessage.staleRefreshed =>
      localizations.templatesStaleMessage,
    PrivateTemplatesMessage.unavailable =>
      localizations.templatesUnavailableMessage,
    PrivateTemplatesMessage.invalidInput =>
      localizations.templatesInvalidInputMessage,
    PrivateTemplatesMessage.operationFailed =>
      localizations.templatesOperationFailedMessage,
    _ => localizations.templatesOperationFailedMessage,
  };
}
