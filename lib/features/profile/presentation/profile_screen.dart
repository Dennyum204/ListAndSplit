import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();
    return _ProfileForm(profile: profile);
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.profile.displayName);
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(profileControllerProvider);
    final displayNameError = state.fieldErrors[ProfileField.displayName];
    return FormPageFrame(
      title: localizations.profileTitle,
      description: localizations.usernameImmutableHelper,
      leading: IconButton(
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormMessageBanner(
            message: state.message == null
                ? null
                : profileMessageText(localizations, state.message!),
          ),
          TextFormField(
            key: const Key('profileUsername'),
            initialValue: widget.profile.username,
            readOnly: true,
            enableInteractiveSelection: true,
            decoration: InputDecoration(
              labelText: localizations.usernameLabel,
              helperText: localizations.usernameImmutableHelper,
              suffixIcon: const Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('profileDisplayName'),
            controller: _displayName,
            enabled: !state.isSubmitting,
            autofillHints: const [AutofillHints.name],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 50,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: localizations.displayNameLabel,
              helperText: localizations.displayNameHelper,
              errorText: displayNameError == null
                  ? null
                  : profileValidationText(
                      localizations,
                      displayNameError,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          SubmissionButton(
            label: localizations.saveChangesButton,
            isSubmitting: state.isSubmitting,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  void _submit() {
    ref
        .read(profileControllerProvider.notifier)
        .updateDisplayName(_displayName.text);
  }
}
