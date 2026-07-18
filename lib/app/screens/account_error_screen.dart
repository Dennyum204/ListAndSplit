import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class AccountErrorScreen extends ConsumerWidget {
  const AccountErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(
      authActionsControllerProvider(AuthActionFlow.session),
    );
    return FormPageFrame(
      title: localizations.accountLoadErrorTitle,
      description: localizations.accountLoadErrorDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: state.isSubmitting
                ? null
                : () {
                    ref.invalidate(authRepositoryProvider);
                    ref.invalidate(ownProfileProvider);
                  },
            child: Text(localizations.tryAgainButton),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: state.isSubmitting
                ? null
                : () => ref
                    .read(
                      authActionsControllerProvider(AuthActionFlow.session)
                          .notifier,
                    )
                    .signOut(),
            child: Text(localizations.signOutButton),
          ),
        ],
      ),
    );
  }
}
