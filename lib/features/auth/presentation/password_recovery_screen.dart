import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.passwordRecovery),
    );
    return FormPageFrame(
      title: localizations.passwordRecoveryTitle,
      description: localizations.passwordRecoveryDescription,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormMessageBanner(
              message: state.message == null
                  ? null
                  : authMessageText(localizations, state.message!),
            ),
            TextField(
              key: const Key('recoveryPassword'),
              controller: _password,
              enabled: !state.isSubmitting,
              autofillHints: const [AutofillHints.newPassword],
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: localizations.passwordLabel,
                errorText: _error(
                  localizations,
                  state.fieldErrors[AuthField.password],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('recoveryPasswordConfirmation'),
              controller: _confirmation,
              enabled: !state.isSubmitting,
              autofillHints: const [AutofillHints.newPassword],
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: localizations.confirmPasswordLabel,
                errorText: _error(
                  localizations,
                  state.fieldErrors[AuthField.passwordConfirmation],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SubmissionButton(
              label: localizations.updatePasswordButton,
              isSubmitting: state.isSubmitting,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => ref
                      .read(
                        authActionsControllerProvider(
                          AuthActionFlow.passwordRecovery,
                        ).notifier,
                      )
                      .signOut(),
              child: Text(localizations.cancelRecoveryButton),
            ),
          ],
        ),
      ),
    );
  }

  String? _error(
    AppLocalizations localizations,
    AuthValidationIssue? issue,
  ) =>
      issue == null ? null : authValidationText(localizations, issue);

  void _submit() {
    ref
        .read(
          authActionsControllerProvider(AuthActionFlow.passwordRecovery)
              .notifier,
        )
        .updatePassword(
          password: _password.text,
          passwordConfirmation: _confirmation.text,
        );
  }
}
