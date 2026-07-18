import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/domain/auth_validation.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.signIn),
    );
    return FormPageFrame(
      title: localizations.signInTitle,
      description: localizations.signInDescription,
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
              key: const Key('signInEmail'),
              controller: _email,
              enabled: !state.isSubmitting,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: localizations.emailLabel,
                errorText: _errorText(
                  localizations,
                  state.fieldErrors[AuthField.email],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('signInPassword'),
              controller: _password,
              enabled: !state.isSubmitting,
              autofillHints: const [AutofillHints.password],
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: localizations.passwordLabel,
                errorText: _errorText(
                  localizations,
                  state.fieldErrors[AuthField.password],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SubmissionButton(
              label: localizations.signInButton,
              isSubmitting: state.isSubmitting,
              onPressed: _submit,
            ),
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => context.go('/forgot-password'),
              child: Text(localizations.forgotPasswordButton),
            ),
            TextButton(
              onPressed:
                  state.isSubmitting ? null : () => context.go('/sign-up'),
              child: Text(localizations.createAccountButton),
            ),
          ],
        ),
      ),
    );
  }

  String? _errorText(
    AppLocalizations localizations,
    AuthValidationIssue? issue,
  ) {
    if (issue == null) return null;
    return authValidationText(localizations, issue);
  }

  void _submit() {
    ref
        .read(
          authActionsControllerProvider(AuthActionFlow.signIn).notifier,
        )
        .signIn(
          email: _email.text,
          password: _password.text,
        );
  }
}
