import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/config/supabase_config.dart';

void main() {
  test('Supabase initialization is optional without dart-defines', () async {
    expect(SupabaseConfig.isConfigured, isFalse);

    await initializeSupabaseIfConfigured();
  });

  test('Supabase initialization injects only the bounded Realtime transport',
      () {
    final source =
        File('lib/core/config/supabase_config.dart').readAsStringSync();

    expect(source, contains('RealtimeClientOptions('));
    expect(
      source,
      contains('transport: const BoundedRealtimeWebSocketTransport().connect'),
    );
    expect(source, isNot(contains('.setAuth(')));
  });
}
