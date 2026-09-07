import 'dart:async';

import 'package:list_and_split/features/settings/domain/theme_preference.dart';

class FakeThemePreferenceRepository implements ThemePreferenceRepository {
  ThemePreference preference = ThemePreference.system;
  final writes = <ThemePreference>[];
  Completer<ThemePreference>? readGate;
  Completer<void>? writeGate;
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<ThemePreference> read() async {
    if (failRead) throw StateError('storage unavailable');
    return readGate == null ? preference : await readGate!.future;
  }

  @override
  Future<void> write(ThemePreference value) async {
    writes.add(value);
    await writeGate?.future;
    if (failWrite) throw StateError('storage unavailable');
    preference = value;
  }
}
