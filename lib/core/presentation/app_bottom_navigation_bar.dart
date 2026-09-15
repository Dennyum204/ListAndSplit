import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Keeps each destination's icon and translated label inside the same pill.
/// Selection remains owned by the router; this widget holds no tab state.
class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                        key: destinations[index].key,
                        container: true,
                        button: true,
                        selected: index == selectedIndex,
                        label: destinations[index].label,
                        hint: MaterialLocalizations.of(context).tabLabel(
                          tabIndex: index + 1,
                          tabCount: destinations.length,
                        ),
                        onTap: () => onDestinationSelected(index),
                        child: ExcludeSemantics(
                          child: Material(
                            key: Key('navigationPill-$index'),
                            color: index == selectedIndex
                                ? AppPalette.orange
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => onDestinationSelected(index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconTheme(
                                      data: IconThemeData(
                                        size: 24,
                                        color: index == selectedIndex
                                            ? AppPalette.navy
                                            : theme.colorScheme.onSurface,
                                      ),
                                      child: index == selectedIndex
                                          ? destinations[index].selectedIcon ??
                                              destinations[index].icon
                                          : destinations[index].icon,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      destinations[index].label,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 12,
                                        letterSpacing: 0,
                                        fontWeight: index == selectedIndex
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: index == selectedIndex
                                            ? AppPalette.navy
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
