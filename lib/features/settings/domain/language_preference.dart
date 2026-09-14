enum LanguagePreference { system, en, pt }

abstract interface class LanguagePreferenceRepository {
  Future<LanguagePreference> read();
  Future<void> write(LanguagePreference preference);
}
