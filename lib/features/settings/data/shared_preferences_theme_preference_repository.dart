import 'package:list_and_split/features/settings/domain/theme_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesThemePreferenceRepository
    implements ThemePreferenceRepository {
  static const storageKey = 'appearance.theme_mode';

  @override
  Future<ThemePreference> read() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.get(storageKey)) {
      'light' => ThemePreference.light,
      'dark' => ThemePreference.dark,
      _ => ThemePreference.system,
    };
  }

  @override
  Future<void> write(ThemePreference preference) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(storageKey, preference.name)) {
      throw StateError('Could not save appearance preference.');
    }
  }
}
