import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/config/supabase_config.dart';

void main() {
  test('Supabase initialization is optional without dart-defines', () async {
    expect(SupabaseConfig.isConfigured, isFalse);

    await initializeSupabaseIfConfigured();
  });
}
