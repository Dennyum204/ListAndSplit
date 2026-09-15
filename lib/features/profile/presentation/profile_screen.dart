import 'package:flutter/material.dart';
import 'package:list_and_split/features/profile/presentation/profile_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_action.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_action.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/notifications/presentation/notification_bell.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_ui.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_selector.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_selector.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import 'package:list_and_split/features/push/presentation/push_settings_card.dart';

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
    final exportState = ref.watch(accountDataExportControllerProvider);
    final deletionState = ref.watch(accountDeletionControllerProvider);
    final authActions = ref.watch(
      authActionsControllerProvider(AuthActionFlow.session),
    );
    final email = ref.watch(authSessionProvider).valueOrNull?.user?.email;
    final hasModerationAccess =
        ref.watch(moderationAccessControllerProvider).valueOrNull == true;
    final isBusy = state.isSubmitting ||
        exportState.isBusy ||
        deletionState.isSubmitting ||
        authActions.isSubmitting;
    final displayNameError = state.fieldErrors[ProfileField.displayName];
    return Scaffold(
      appBar: AppPageHeader(
        title: Text(localizations.profileTitle),
        automaticallyImplyLeading: false,
        actions: const [NotificationBell()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormMessageBanner(
                    message: state.message == null
                        ? null
                        : profileMessageText(localizations, state.message!),
                  ),
                  FormMessageBanner(
                    message:
                        authActions.message == AuthActionMessage.operationFailed
                            ? localizations.operationFailedMessage
                            : null,
                  ),
                  LayoutBuilder(builder: (context, constraints) {
                    final identity = ProfileAvatar(
                      target: AvatarTarget.profile(widget.profile.id),
                      label: widget.profile.displayName ??
                          widget.profile.username!,
                      size: 72,
                    );
                    final username = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(localizations.usernameLabel),
                        const SizedBox(height: 6),
                        Semantics(
                          label: localizations.usernameLabel,
                          child: TextFormField(
                            key: const Key('profileUsername'),
                            style: AppPalette.inputTextStyle(context),
                            initialValue: widget.profile.username,
                            readOnly: true,
                            enableInteractiveSelection: true,
                            decoration: const InputDecoration(
                              suffixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 440 &&
                        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 12),
                          username
                        ],
                      );
                    }
                    return Row(
                      children: [
                        identity,
                        const SizedBox(width: 16),
                        Expanded(child: username)
                      ],
                    );
                  }),
                  const SizedBox(height: 8),
                  AvatarEditorActions(disabled: isBusy),
                  Text(localizations.usernameImmutableHelper,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Text(localizations.displayNameLabel),
                  const SizedBox(height: 6),
                  Semantics(
                    label: localizations.displayNameLabel,
                    child: TextField(
                      key: const Key('profileDisplayName'),
                      style: AppPalette.inputTextStyle(context),
                      controller: _displayName,
                      enabled: !isBusy,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      maxLength: 50,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        errorText: displayNameError == null
                            ? null
                            : profileValidationText(
                                localizations,
                                displayNameError,
                              ),
                      ),
                    ),
                  ),
                  Text(localizations.displayNameHelper,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 20),
                  SubmissionButton(
                    label: localizations.saveChangesButton,
                    isSubmitting: state.isSubmitting,
                    onPressed: exportState.isBusy || deletionState.isSubmitting
                        ? null
                        : _submit,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('previewPublicProfileButton'),
                    onPressed: isBusy
                        ? null
                        : () => context.push(
                              AppRoutes.publicProfile(widget.profile.id),
                            ),
                    icon: const Icon(Icons.public_rounded),
                    label:
                        Text(localizations.publicTemplatesPreviewProfileButton),
                  ),
                  if (hasModerationAccess)
                    TextButton.icon(
                      key: const Key('openModerationButton'),
                      onPressed: isBusy
                          ? null
                          : () => context.push(AppRoutes.moderation),
                      icon: const Icon(Icons.gavel_rounded),
                      label: Text(localizations.moderationSettingsAction),
                    ),
                  const SizedBox(height: 20),
                  const ThemePreferenceSelector(),
                  const SizedBox(height: 16),
                  const LanguagePreferenceSelector(),
                  const SizedBox(height: 16),
                  const PushSettingsCard(),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    key: const Key('profileSignOutButton'),
                    onPressed: isBusy
                        ? null
                        : () => ref
                            .read(
                              authActionsControllerProvider(
                                      AuthActionFlow.session)
                                  .notifier,
                            )
                            .signOut(),
                    icon: authActions.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: Text(localizations.signOutButton),
                  ),
                  AccountDataExportAction(
                    enabled: !state.isSubmitting && !deletionState.isSubmitting,
                  ),
                  if (email != null)
                    AccountDeletionAction(
                      email: email,
                      confirmationTarget: widget.profile.username!,
                      enabled: !state.isSubmitting && !exportState.isBusy,
                      onDeleted: () => context.go(AppRoutes.signIn),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    ref
        .read(profileControllerProvider.notifier)
        .updateDisplayName(_displayName.text);
  }
}
