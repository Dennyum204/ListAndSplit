import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.forgotPassword),
    );
    final emailIssue = state.fieldErrors[AuthField.email];
    return FormPageFrame(
      title: localizations.forgotPasswordTitle,
      description: localizations.forgotPasswordDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormMessageBanner(
            message: state.message == null
                ? null
                : authMessageText(localizations, state.message!),
          ),
          TextField(
            key: const Key('forgotPasswordEmail'),
            controller: _email,
            enabled: !state.isSubmitting,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: localizations.emailLabel,
              errorText: emailIssue == null
                  ? null
                  : authValidationText(
                      localizations,
                      emailIssue,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          SubmissionButton(
            label: localizations.sendResetLinkButton,
            isSubmitting: state.isSubmitting,
            onPressed: _submit,
          ),
          TextButton(
            onPressed: state.isSubmitting ? null : () => context.go('/sign-in'),
            child: Text(localizations.backToSignInButton),
          ),
        ],
      ),
    );
  }

  void _submit() {
    ref
        .read(
          authActionsControllerProvider(AuthActionFlow.forgotPassword).notifier,
        )
        .requestPasswordReset(_email.text);
  }
}
