import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.signUp),
    );
    return FormPageFrame(
      title: localizations.signUpTitle,
      description: localizations.signUpDescription,
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
              key: const Key('signUpEmail'),
              controller: _email,
              enabled: !state.isSubmitting,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: localizations.emailLabel,
                errorText: _error(
                  localizations,
                  state.fieldErrors[AuthField.email],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('signUpPassword'),
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
              key: const Key('signUpPasswordConfirmation'),
              controller: _passwordConfirmation,
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
              label: localizations.createAccountButton,
              isSubmitting: state.isSubmitting,
              onPressed: _submit,
            ),
            TextButton(
              onPressed:
                  state.isSubmitting ? null : () => context.go('/sign-in'),
              child: Text(localizations.alreadyHaveAccountButton),
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
          authActionsControllerProvider(AuthActionFlow.signUp).notifier,
        )
        .signUp(
          email: _email.text,
          password: _password.text,
          passwordConfirmation: _passwordConfirmation.text,
        );
  }
}
