import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class FoundationScreen extends ConsumerWidget {
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localizations = AppLocalizations.of(context);
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final actionState = ref.watch(
      authActionsControllerProvider(AuthActionFlow.session),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BrandMark(semanticLabel: localizations.appTitle),
                  const SizedBox(height: 28),
                  Text(
                    localizations.appTitle,
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile?.displayName == null
                        ? localizations.foundationTagline
                        : localizations
                            .foundationWelcome(profile!.displayName!),
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localizations.foundationAuthenticatedDescription,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _FoundationBadge(label: localizations.foundationReady),
                  const SizedBox(height: 28),
                  FilledButton.tonalIcon(
                    onPressed: actionState.isSubmitting
                        ? null
                        : () => context.go('/profile'),
                    icon: const Icon(Icons.person_outline_rounded),
                    label: Text(localizations.editProfileButton),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: actionState.isSubmitting
                        ? null
                        : () => ref
                            .read(
                              authActionsControllerProvider(
                                AuthActionFlow.session,
                              ).notifier,
                            )
                            .signOut(),
                    icon: actionState.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: Text(localizations.signOutButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 52,
              color: colorScheme.onPrimaryContainer,
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.surface,
                    width: 3,
                  ),
                ),
                child: Icon(
                  Icons.group_rounded,
                  size: 17,
                  color: colorScheme.onTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoundationBadge extends StatelessWidget {
  const _FoundationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
