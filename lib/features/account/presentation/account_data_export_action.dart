import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_controller.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class AccountDataExportAction extends ConsumerWidget {
  const AccountDataExportAction({
    this.enabled = true,
    super.key,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(accountDataExportControllerProvider);
    final progressMessage = switch (state.stage) {
      AccountDataExportStage.idle => null,
      AccountDataExportStage.preparing =>
        localizations.accountDataExportPreparingMessage,
      AccountDataExportStage.sharing =>
        localizations.accountDataExportSharingMessage,
    };
    final resultMessage = switch (state.message) {
      AccountDataExportMessage.shared =>
        localizations.accountDataExportSharedMessage,
      AccountDataExportMessage.dismissed =>
        localizations.accountDataExportDismissedMessage,
      AccountDataExportMessage.failed =>
        localizations.accountDataExportFailedMessage,
      null => null,
    };

    return Column(
      key: const Key('accountDataExportSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        Text(
          localizations.accountDataSectionTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          localizations.accountDataExportDescription,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        FormMessageBanner(message: resultMessage),
        if (progressMessage != null)
          Semantics(
            liveRegion: true,
            label: progressMessage,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(progressMessage)),
                ],
              ),
            ),
          ),
        Builder(
          builder: (buttonContext) => Semantics(
            label: localizations.accountDataExportButtonSemanticLabel,
            button: true,
            child: OutlinedButton.icon(
              key: const Key('downloadAccountDataButton'),
              onPressed: enabled && !state.isBusy
                  ? () => _confirmAndDownload(buttonContext, ref)
                  : null,
              icon: const Icon(Icons.download_rounded),
              label: Text(localizations.accountDataExportButton),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndDownload(
    BuildContext buttonContext,
    WidgetRef ref,
  ) async {
    final localizations = AppLocalizations.of(buttonContext);
    final confirmed = await showDialog<bool>(
      context: buttonContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.accountDataExportDialogTitle),
        content: Text(localizations.accountDataExportDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.cancelButton),
          ),
          FilledButton(
            key: const Key('confirmAccountDataExportButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.accountDataExportConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !buttonContext.mounted) return;

    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    final topLeft = renderBox?.localToGlobal(Offset.zero);
    final size = renderBox?.size;
    final origin = topLeft == null || size == null
        ? null
        : AccountDataShareOrigin(
            left: topLeft.dx,
            top: topLeft.dy,
            width: size.width,
            height: size.height,
          );
    await ref
        .read(accountDataExportControllerProvider.notifier)
        .download(origin: origin);
  }
}
