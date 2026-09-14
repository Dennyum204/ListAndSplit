import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/settings/data/shared_preferences_language_preference_repository.dart';
import 'package:list_and_split/features/settings/domain/language_preference.dart';

final languagePreferenceRepositoryProvider =
    Provider<LanguagePreferenceRepository>(
  (ref) => SharedPreferencesLanguagePreferenceRepository(),
);

// Device-wide language survives navigation and sign-out, not account data.
final languagePreferenceControllerProvider = StateNotifierProvider<
    LanguagePreferenceController, LanguagePreferenceState>(
  (ref) => LanguagePreferenceController(
    ref.watch(languagePreferenceRepositoryProvider),
  ),
);

class LanguagePreferenceState {
  const LanguagePreferenceState({
    this.preference = LanguagePreference.system,
    this.isLoading = false,
    this.isSaving = false,
    this.saveFailed = false,
    this.readFailed = false,
  });

  final LanguagePreference preference;
  final bool isLoading;
  final bool isSaving;
  final bool saveFailed;
  final bool readFailed;

  Locale? get locale => switch (preference) {
        LanguagePreference.system => null,
        LanguagePreference.en => const Locale('en'),
        LanguagePreference.pt => const Locale('pt'),
      };
}

class LanguagePreferenceController
    extends StateNotifier<LanguagePreferenceState> {
  LanguagePreferenceController(this._repository)
      : super(const LanguagePreferenceState(isLoading: true)) {
    unawaited(restore());
  }

  final LanguagePreferenceRepository _repository;

  Future<void> restore() async {
    if (!mounted || state.isSaving) return;
    state =
        LanguagePreferenceState(preference: state.preference, isLoading: true);
    var readFailed = false;
    var preference = LanguagePreference.system;
    try {
      preference = await _repository.read();
    } catch (_) {
      // Startup remains available, but show that the saved choice is unknown.
      readFailed = true;
    }
    if (mounted) {
      state = LanguagePreferenceState(
          preference: preference, readFailed: readFailed);
    }
  }

  Future<void> select(LanguagePreference preference) async {
    if (!mounted || state.isLoading || state.isSaving) return;
    if (state.preference == preference &&
        !state.saveFailed &&
        !state.readFailed) {
      return;
    }
    final previous = state.preference;
    state = LanguagePreferenceState(preference: preference, isSaving: true);
    try {
      await _repository.write(preference);
      if (mounted) state = LanguagePreferenceState(preference: preference);
    } catch (_) {
      var persisted = previous;
      var readFailed = false;
      try {
        persisted = await _repository.read();
      } catch (_) {
        readFailed = true;
      }
      if (mounted) {
        state = LanguagePreferenceState(
            preference: persisted, saveFailed: true, readFailed: readFailed);
      }
    }
  }
}
