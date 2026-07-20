import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
