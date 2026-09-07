import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/features/settings/domain/theme_preference.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class ThemePreferenceSelector extends ConsumerWidget {
  const ThemePreferenceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(themePreferenceControllerProvider);
    final busy = state.isLoading || state.isSaving;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(localizations.appearanceTitle,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(localizations.appearanceDeviceHelper),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preference in ThemePreference.values)
                ChoiceChip(
                  key: Key('themePreference-${preference.name}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  avatar: Icon(
                      switch (preference) {
                        ThemePreference.system => Icons.brightness_auto_rounded,
                        ThemePreference.light => Icons.light_mode_outlined,
                        ThemePreference.dark => Icons.dark_mode_outlined,
                      },
                      size: 20),
                  label: Text(switch (preference) {
                    ThemePreference.system => localizations.appearanceSystem,
                    ThemePreference.light => localizations.appearanceLight,
                    ThemePreference.dark => localizations.appearanceDark,
                  }),
                  selected: state.preference == preference,
                  onSelected: busy
                      ? null
                      : (_) => ref
                          .read(themePreferenceControllerProvider.notifier)
                          .select(preference),
                ),
            ],
          ),
          FormMessageBanner(
            message:
                state.saveFailed ? localizations.appearanceSaveFailed : null,
          ),
        ],
      ),
    );
  }
}
