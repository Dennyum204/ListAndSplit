import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_controller.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class AccountDeletionAction extends ConsumerWidget {
  const AccountDeletionAction({
    required this.email,
    required this.confirmationTarget,
    required this.onDeleted,
    this.enabled = true,
    super.key,
  });

  final String email;
  final String confirmationTarget;
  final VoidCallback onDeleted;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(accountDeletionControllerProvider);
    return Column(
      key: const Key('accountDeletionSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        Text(
          localizations.accountDeletionTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          localizations.accountDeletionDescription,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: localizations.accountDeletionButtonSemanticLabel,
          button: true,
          child: OutlinedButton.icon(
            key: const Key('deleteAccountButton'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: enabled && !state.isSubmitting
                ? () => _openDialog(context, ref)
                : null,
            icon: const Icon(Icons.delete_forever_rounded),
            label: Text(localizations.accountDeletionButton),
          ),
        ),
      ],
    );
  }

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    ref.read(accountDeletionControllerProvider.notifier).resetFeedback();
    late final AccountDeletionListImpact impact;
    try {
      impact = await ref.read(accountDeletionImpactProvider.future);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).operationFailedMessage)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AccountDeletionDialog(
        email: email,
        confirmationTarget: confirmationTarget,
        impact: impact,
      ),
    );
    if (deleted == true && context.mounted) onDeleted();
  }
}

class _AccountDeletionDialog extends ConsumerStatefulWidget {
  const _AccountDeletionDialog({
    required this.email,
    required this.confirmationTarget,
    required this.impact,
  });

  final String email;
  final String confirmationTarget;
  final AccountDeletionListImpact impact;

  @override
  ConsumerState<_AccountDeletionDialog> createState() =>
      _AccountDeletionDialogState();
}

class _AccountDeletionDialogState
    extends ConsumerState<_AccountDeletionDialog> {
  final _confirmation = TextEditingController();
  final _password = TextEditingController();
  var _isFinallyConfirmed = false;

  @override
  void dispose() {
    _confirmation.clear();
    _password.clear();
    _confirmation.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(accountDeletionControllerProvider);
    final confirmationError =
        state.fieldErrors[AccountDeletionField.confirmation];
    final passwordError = state.fieldErrors[AccountDeletionField.password];
    final finalConfirmationError =
        state.fieldErrors[AccountDeletionField.finalConfirmation];
    return AlertDialog(
      key: const Key('accountDeletionDialog'),
      title: Text(localizations.accountDeletionDialogTitle),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(localizations.accountDeletionIrreversibleWarning),
              if (widget.impact.ownedSharedListCount > 0) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    localizations.accountDeletionSharedListImpact(
                      widget.impact.ownedSharedListCount,
                      widget.impact.affectedParticipantCount,
                    ),
                    key: const Key('accountDeletionSharedListImpact'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(localizations.accountDeletionConfirmationInstruction),
              const SizedBox(height: 4),
              SelectableText(
                widget.confirmationTarget,
                key: const Key('accountDeletionConfirmationTarget'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('accountDeletionConfirmationField'),
                controller: _confirmation,
                enabled: !state.isSubmitting,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: localizations.accountDeletionConfirmationLabel,
                  errorText: confirmationError == null
                      ? null
                      : _fieldIssueText(
                          localizations,
                          confirmationError,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('accountDeletionPasswordField'),
                controller: _password,
                enabled: !state.isSubmitting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: localizations.accountDeletionPasswordLabel,
                  errorText: passwordError == null
                      ? null
                      : localizations.passwordRequiredError,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('accountDeletionFinalConfirmation'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _isFinallyConfirmed,
                onChanged: state.isSubmitting
                    ? null
                    : (value) => setState(
                          () => _isFinallyConfirmed = value ?? false,
                        ),
                title: Text(localizations.accountDeletionFinalConfirmation),
                subtitle: finalConfirmationError == null
                    ? null
                    : Text(
                        localizations.accountDeletionFinalConfirmationError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
              ),
              FormMessageBanner(
                message: state.message == null
                    ? null
                    : _messageText(localizations, state.message!),
              ),
              if (state.isSubmitting)
                Semantics(
                  liveRegion: true,
                  label: localizations.accountDeletionProgressMessage,
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          localizations.accountDeletionProgressMessage,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelAccountDeletionButton'),
          onPressed: state.isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(localizations.cancelButton),
        ),
        FilledButton(
          key: const Key('confirmAccountDeletionButton'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: state.isSubmitting ? null : _submit,
          child: Text(localizations.accountDeletionConfirmButton),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final confirmation = _confirmation.text;
    final password = _password.text;
    final deleted = await ref
        .read(accountDeletionControllerProvider.notifier)
        .deleteAccount(
          email: widget.email,
          expectedConfirmation: widget.confirmationTarget,
          confirmation: confirmation,
          password: password,
          isFinallyConfirmed: _isFinallyConfirmed,
        );
    _confirmation.clear();
    _password.clear();
    if (!mounted) return;
    setState(() => _isFinallyConfirmed = false);
    if (deleted) Navigator.of(context).pop(true);
  }

  String _fieldIssueText(
    AppLocalizations localizations,
    AccountDeletionFieldIssue issue,
  ) {
    return switch (issue) {
      AccountDeletionFieldIssue.required =>
        localizations.accountDeletionConfirmationRequiredError,
      AccountDeletionFieldIssue.mismatch =>
        localizations.accountDeletionConfirmationMismatchError,
      AccountDeletionFieldIssue.finalConfirmationRequired =>
        localizations.accountDeletionFinalConfirmationError,
    };
  }

  String _messageText(
    AppLocalizations localizations,
    AccountDeletionMessage message,
  ) {
    return switch (message) {
      AccountDeletionMessage.wrongPassword =>
        localizations.accountDeletionWrongPasswordMessage,
      AccountDeletionMessage.confirmationMismatch =>
        localizations.accountDeletionConfirmationMismatchError,
      AccountDeletionMessage.reauthenticationRequired =>
        localizations.accountDeletionReauthenticationMessage,
      AccountDeletionMessage.retryable =>
        localizations.accountDeletionRetryableMessage,
      AccountDeletionMessage.offline =>
        localizations.accountDeletionOfflineMessage,
    };
  }
}
