import 'package:list_and_split/features/settings/domain/language_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesLanguagePreferenceRepository
    implements LanguagePreferenceRepository {
  static const storageKey = 'language.locale';

  @override
  Future<LanguagePreference> read() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return switch (preferences.get(storageKey)) {
      'en' => LanguagePreference.en,
      'pt' => LanguagePreference.pt,
      _ => LanguagePreference.system,
    };
  }

  @override
  Future<void> write(LanguagePreference preference) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      if (!await preferences.setString(storageKey, preference.name)) {
        throw StateError('Could not save language preference.');
      }
    } catch (_) {
      // SharedPreferences updates its cache before the platform confirms a
      // write. Discard that speculative value on failure.
      await preferences.reload();
      rethrow;
    }
  }
}
