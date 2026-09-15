enum ThemePreference { system, light, dark }

abstract interface class ThemePreferenceRepository {
  Future<ThemePreference> read();

  Future<void> write(ThemePreference preference);
}
