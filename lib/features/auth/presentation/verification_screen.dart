import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_ui.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final pendingEmail = ref.watch(pendingVerificationEmailProvider);
    final sessionEmail =
        ref.watch(authSessionProvider).valueOrNull?.user?.email;
    final email = pendingEmail ?? sessionEmail;
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.verification),
    );

    return FormPageFrame(
      title: localizations.verificationTitle,
      description: email == null
          ? localizations.verificationFallbackDescription
          : localizations.verificationDescription(email),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormMessageBanner(
            message: state.message == null
                ? null
                : authMessageText(localizations, state.message!),
          ),
          SubmissionButton(
            label: localizations.resendVerificationButton,
            isSubmitting: state.isSubmitting,
            onPressed: email == null
                ? null
                : () => ref
                    .read(
                      authActionsControllerProvider(AuthActionFlow.verification)
                          .notifier,
                    )
                    .resendVerification(email),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: state.isSubmitting
                ? null
                : () => ref
                    .read(
                      authActionsControllerProvider(
                        AuthActionFlow.verification,
                      ).notifier,
                    )
                    .signOut(),
            child: Text(localizations.backToSignInButton),
          ),
        ],
      ),
    );
  }
}
