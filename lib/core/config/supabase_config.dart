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

class AppConfiguration {
  const AppConfiguration({
    required this.isConfigured,
    required this.isPartiallyConfigured,
  });

  const AppConfiguration.configured()
      : isConfigured = true,
        isPartiallyConfigured = false;

  const AppConfiguration.missing()
      : isConfigured = false,
        isPartiallyConfigured = false;

  final bool isConfigured;
  final bool isPartiallyConfigured;

  factory AppConfiguration.fromEnvironment() => AppConfiguration(
        isConfigured: SupabaseConfig.isConfigured,
        isPartiallyConfigured: SupabaseConfig.isPartiallyConfigured,
      );
}

Future<void> initializeSupabaseIfConfigured() async {
  if (!SupabaseConfig.isConfigured) {
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
