import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.onSignOut, super.key});

  final Future<bool> Function() onSignOut;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  var _isSigningOut = false;
  var _didSignOutFail = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(profileControllerProvider);
    final isBusy = state.isSubmitting || _isSigningOut;
    return FormPageFrame(
      title: localizations.onboardingTitle,
      description: localizations.onboardingDescription,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormMessageBanner(
              message: _didSignOutFail
                  ? localizations.operationFailedMessage
                  : state.message == null
                      ? null
                      : profileMessageText(localizations, state.message!),
            ),
            TextField(
              key: const Key('onboardingUsername'),
              controller: _username,
              enabled: !isBusy,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: localizations.usernameLabel,
                helperText: localizations.usernameHelper,
                errorText: _error(
                  localizations,
                  state.fieldErrors[ProfileField.username],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('onboardingDisplayName'),
              controller: _displayName,
              enabled: !isBusy,
              autofillHints: const [AutofillHints.name],
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              maxLength: 50,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: localizations.displayNameLabel,
                helperText: localizations.displayNameHelper,
                errorText: _error(
                  localizations,
                  state.fieldErrors[ProfileField.displayName],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SubmissionButton(
              label: localizations.finishProfileButton,
              isSubmitting: state.isSubmitting,
              onPressed: _isSigningOut ? null : _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: isBusy ? null : _signOut,
              child: Text(localizations.signOutButton),
            ),
          ],
        ),
      ),
    );
  }

  String? _error(
    AppLocalizations localizations,
    ProfileValidationIssue? issue,
  ) =>
      issue == null ? null : profileValidationText(localizations, issue);

  void _submit() {
    ref.read(profileControllerProvider.notifier).completeOnboarding(
          username: _username.text,
          displayName: _displayName.text,
        );
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() {
      _isSigningOut = true;
      _didSignOutFail = false;
    });
    final didSignOut = await widget.onSignOut();
    if (mounted) {
      setState(() {
        _isSigningOut = false;
        _didSignOutFail = !didSignOut;
      });
    }
  }
}
