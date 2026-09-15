import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
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
  bool _hidePassword = true;

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
      centerTitle: true,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed:
                  state.isSubmitting ? null : () => context.go('/sign-up'),
              child: Text(localizations.createAccountButton),
            ),
            const SizedBox(height: 20),
            FormMessageBanner(
              message: state.message == null
                  ? null
                  : authMessageText(localizations, state.message!),
            ),
            Semantics(
                label: localizations.emailLabel,
                child: TextField(
                  style: AppPalette.inputTextStyle(context),
                  key: const Key('signInEmail'),
                  controller: _email,
                  enabled: !state.isSubmitting,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    hint: ExcludeSemantics(
                        child: Text(localizations.emailLabel,
                            style: Theme.of(context)
                                .inputDecorationTheme
                                .hintStyle)),
                    errorText: _errorText(
                      localizations,
                      state.fieldErrors[AuthField.email],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            Semantics(
                label: localizations.passwordLabel,
                child: TextField(
                  style: AppPalette.inputTextStyle(context),
                  key: const Key('signInPassword'),
                  controller: _password,
                  enabled: !state.isSubmitting,
                  autofillHints: const [AutofillHints.password],
                  obscureText: _hidePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      key: const Key('signInPasswordVisibility'),
                      tooltip: _hidePassword
                          ? localizations.showPasswordButton
                          : localizations.hidePasswordButton,
                      onPressed: state.isSubmitting
                          ? null
                          : () =>
                              setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(_hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                    hint: ExcludeSemantics(
                        child: Text(localizations.passwordLabel,
                            style: Theme.of(context)
                                .inputDecorationTheme
                                .hintStyle)),
                    errorText: _errorText(
                      localizations,
                      state.fieldErrors[AuthField.password],
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => context.go('/forgot-password'),
              child: Text(localizations.forgotPasswordButton),
            ),
            const SizedBox(height: 48),
            SubmissionButton(
              label: localizations.signInButton,
              isSubmitting: state.isSubmitting,
              onPressed: _submit,
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
