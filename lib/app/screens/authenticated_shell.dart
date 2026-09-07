import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Theme(
        // The selected icon sits on orange in both modes, not on a dark card.
        data: theme.copyWith(
          colorScheme:
              theme.colorScheme.copyWith(onSecondaryContainer: AppPalette.navy),
        ),
        child: NavigationBar(
          height: 80,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: [
            NavigationDestination(
              key: const Key('listsDestination'),
              icon: const Icon(Icons.checklist_rounded),
              label: localizations.shellListsTab,
            ),
            NavigationDestination(
              key: const Key('templatesDestination'),
              icon: const Icon(Icons.copy_all_outlined),
              label: localizations.shellTemplatesTab,
            ),
            NavigationDestination(
              key: const Key('communityDestination'),
              icon: const Icon(Icons.people_outline_rounded),
              label: localizations.shellCommunityTab,
            ),
            NavigationDestination(
              key: const Key('profileDestination'),
              icon: const Icon(Icons.person_outline_rounded),
              label: localizations.shellProfileTab,
            ),
          ],
        ),
      ),
    );
  }
}
