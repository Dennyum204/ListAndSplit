import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/presentation/form_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/features/settings/domain/language_preference.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

class LanguagePreferenceSelector extends ConsumerWidget {
  const LanguagePreferenceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final state = ref.watch(languagePreferenceControllerProvider);

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogField(
            label: strings.languageTitle,
            child: DropdownButtonFormField<LanguagePreference>(
              isDense: false,
              key: const Key('languagePreference'),
              style: AppPalette.inputTextStyle(context),
              dropdownColor: AppPalette.inputCream,
              iconEnabledColor: AppPalette.navy,
              // Keep Flutter 3.19 compatibility.
              // ignore: deprecated_member_use
              value: state.preference,
              isExpanded: true,
              decoration:
                  InputDecoration(helperText: strings.languageDeviceHelper),
              items: [
                for (final preference in LanguagePreference.values)
                  DropdownMenuItem(
                    value: preference,
                    child: Text(switch (preference) {
                      LanguagePreference.system => strings.languageSystem,
                      LanguagePreference.en => 'English',
                      LanguagePreference.pt => 'Português',
                    }),
                  ),
              ],
              onChanged: state.isLoading || state.isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        ref
                            .read(languagePreferenceControllerProvider.notifier)
                            .select(value);
                      }
                    },
            ),
          ),
          FormMessageBanner(
              message: state.readFailed
                  ? strings.languageReadFailed
                  : state.saveFailed
                      ? strings.languageSaveFailed
                      : null),
          if (state.readFailed)
            TextButton(
                onPressed: state.isLoading || state.isSaving
                    ? null
                    : () => ref
                        .read(languagePreferenceControllerProvider.notifier)
                        .restore(),
                child: Text(strings.tryAgainButton)),
        ],
      ),
    );
  }
}
