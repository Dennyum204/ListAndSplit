import 'dart:async';

import 'package:list_and_split/features/settings/domain/language_preference.dart';

class FakeLanguagePreferenceRepository implements LanguagePreferenceRepository {
  LanguagePreference preference = LanguagePreference.system;
  final writes = <LanguagePreference>[];
  Completer<LanguagePreference>? readGate;
  Completer<void>? writeGate;
  bool failRead = false;
  bool failWrite = false;
  bool failAfterWrite = false;

  @override
  Future<LanguagePreference> read() async {
    if (failRead) throw StateError('storage unavailable');
    return readGate == null ? preference : await readGate!.future;
  }

  @override
  Future<void> write(LanguagePreference value) async {
    writes.add(value);
    await writeGate?.future;
    if (failWrite) throw StateError('storage unavailable');
    preference = value;
    if (failAfterWrite) throw StateError('write acknowledgement unavailable');
  }
}
