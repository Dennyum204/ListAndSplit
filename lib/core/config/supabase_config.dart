import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static bool get isPartiallyConfigured =>
      url.isNotEmpty != publishableKey.isNotEmpty;
}

Future<void> initializeSupabaseIfConfigured() async {
  if (SupabaseConfig.isPartiallyConfigured) {
    throw StateError(
      'Set both SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY, or neither.',
    );
  }

  if (!SupabaseConfig.isConfigured) {
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
