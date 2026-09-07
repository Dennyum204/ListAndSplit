import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/settings/data/shared_preferences_theme_preference_repository.dart';
import 'package:list_and_split/features/settings/domain/theme_preference.dart';

final themePreferenceRepositoryProvider = Provider<ThemePreferenceRepository>(
  (ref) => SharedPreferencesThemePreferenceRepository(),
);

// Device-wide appearance survives navigation and sign-out, not account data.
final themePreferenceControllerProvider =
    StateNotifierProvider<ThemePreferenceController, ThemePreferenceState>(
  (ref) => ThemePreferenceController(
    ref.watch(themePreferenceRepositoryProvider),
  ),
);

class ThemePreferenceState {
  const ThemePreferenceState({
    this.preference = ThemePreference.system,
    this.isLoading = false,
    this.isSaving = false,
    this.saveFailed = false,
  });

  final ThemePreference preference;
  final bool isLoading;
  final bool isSaving;
  final bool saveFailed;

  ThemeMode get themeMode => switch (preference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };
}

class ThemePreferenceController extends StateNotifier<ThemePreferenceState> {
  ThemePreferenceController(this._repository)
      : super(const ThemePreferenceState(isLoading: true)) {
    unawaited(_restore());
  }

  final ThemePreferenceRepository _repository;

  Future<void> _restore() async {
    var preference = ThemePreference.system;
    try {
      preference = await _repository.read();
    } catch (_) {
      // An unavailable local preference must not block startup or authentication.
    }
    if (mounted) state = ThemePreferenceState(preference: preference);
  }

  Future<void> select(ThemePreference preference) async {
    if (!mounted || state.isLoading || state.isSaving) return;
    if (state.preference == preference && !state.saveFailed) return;
    final previous = state.preference;
    state = ThemePreferenceState(preference: preference, isSaving: true);
    try {
      await _repository.write(preference);
      if (mounted) state = ThemePreferenceState(preference: preference);
    } catch (_) {
      if (mounted) {
        state = ThemePreferenceState(preference: previous, saveFailed: true);
      }
    }
  }
}
