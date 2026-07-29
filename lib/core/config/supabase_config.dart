import 'package:supabase_flutter/supabase_flutter.dart';

import '../realtime/bounded_realtime_websocket_transport.dart';
import 'app_environment.dart';

export 'app_environment.dart';

abstract final class SupabaseConfig {
  static const environment = String.fromEnvironment('APP_ENV');
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
}

enum AppConfigurationIssue {
  notLoaded,
  environmentMissing,
  environmentInvalid,
  nativeIdentityUnavailable,
  nativeFlavorMismatch,
  nativeApplicationIdMismatch,
  supabaseUrlMissing,
  publishableKeyMissing,
  supabaseUrlMalformed,
  devProjectMismatch,
  productionDevProjectRejected,
  productionUnavailable,
}

class AppConfiguration {
  const AppConfiguration._({
    required this.environment,
    required this.issue,
    required this.isPartiallyConfigured,
    String? authCallbackUri,
    String? supabaseUrl,
    String? publishableKey,
  })  : _supabaseUrl = supabaseUrl,
        _publishableKey = publishableKey,
        _authCallbackUri = authCallbackUri;

  const AppConfiguration.notLoaded()
      : this._(
          environment: null,
          issue: AppConfigurationIssue.notLoaded,
          isPartiallyConfigured: false,
        );

  const AppConfiguration.devConfigured()
      : this._(
          environment: AppEnvironment.dev,
          issue: null,
          isPartiallyConfigured: false,
          authCallbackUri: 'com.ferbatech.listandsplit.dev://auth-callback',
          supabaseUrl: 'https://configured.example',
          publishableKey: 'configured',
        );

  const AppConfiguration.invalid({
    required AppEnvironment? environment,
    required AppConfigurationIssue issue,
    bool isPartiallyConfigured = false,
  }) : this._(
          environment: environment,
          issue: issue,
          isPartiallyConfigured: isPartiallyConfigured,
        );

  const AppConfiguration._valid({
    required AppEnvironment environment,
    required String authCallbackUri,
    required String supabaseUrl,
    required String publishableKey,
  }) : this._(
          environment: environment,
          issue: null,
          isPartiallyConfigured: false,
          authCallbackUri: authCallbackUri,
          supabaseUrl: supabaseUrl,
          publishableKey: publishableKey,
        );

  static const devProjectHost = 'lzwsgxziqxpxwyalkfuy.supabase.co';

  final AppEnvironment? environment;
  final AppConfigurationIssue? issue;
  final bool isPartiallyConfigured;
  final String? _authCallbackUri;
  final String? _supabaseUrl;
  final String? _publishableKey;

  bool get isConfigured => issue == null;

  String? get authCallbackUri => _authCallbackUri;

  factory AppConfiguration.resolve({
    required String environmentValue,
    required String supabaseUrl,
    required String publishableKey,
    required NativeAppIdentity nativeIdentity,
  }) {
    if (environmentValue.isEmpty) {
      return const AppConfiguration.invalid(
        environment: null,
        issue: AppConfigurationIssue.environmentMissing,
      );
    }

    final environment = AppEnvironment.tryParse(environmentValue);
    if (environment == null) {
      return const AppConfiguration.invalid(
        environment: null,
        issue: AppConfigurationIssue.environmentInvalid,
      );
    }

    if (nativeIdentity.isAndroid) {
      if (nativeIdentity.flavor != environment.androidFlavor) {
        return AppConfiguration.invalid(
          environment: environment,
          issue: AppConfigurationIssue.nativeFlavorMismatch,
        );
      }
      if (nativeIdentity.applicationId != environment.androidApplicationId) {
        return AppConfiguration.invalid(
          environment: environment,
          issue: AppConfigurationIssue.nativeApplicationIdMismatch,
        );
      }
    }

    if (supabaseUrl.isEmpty) {
      return AppConfiguration.invalid(
        environment: environment,
        issue: AppConfigurationIssue.supabaseUrlMissing,
        isPartiallyConfigured: publishableKey.isNotEmpty,
      );
    }
    if (publishableKey.isEmpty) {
      return AppConfiguration.invalid(
        environment: environment,
        issue: AppConfigurationIssue.publishableKeyMissing,
        isPartiallyConfigured: true,
      );
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (!_isValidSupabaseUrl(uri)) {
      return AppConfiguration.invalid(
        environment: environment,
        issue: AppConfigurationIssue.supabaseUrlMalformed,
      );
    }

    if (environment == AppEnvironment.dev) {
      if (uri!.host != devProjectHost) {
        return AppConfiguration.invalid(
          environment: environment,
          issue: AppConfigurationIssue.devProjectMismatch,
        );
      }
      return AppConfiguration._valid(
        environment: environment,
        authCallbackUri: nativeIdentity.isAndroid
            ? environment.authCallbackUri
            : AppEnvironment.prod.authCallbackUri,
        supabaseUrl: supabaseUrl,
        publishableKey: publishableKey,
      );
    }

    if (uri!.host == devProjectHost) {
      return AppConfiguration.invalid(
        environment: environment,
        issue: AppConfigurationIssue.productionDevProjectRejected,
      );
    }

    return AppConfiguration.invalid(
      environment: environment,
      issue: AppConfigurationIssue.productionUnavailable,
    );
  }

  static bool _isValidSupabaseUrl(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

Future<AppConfiguration> loadAppConfiguration({
  NativeAppIdentityReader identityReader =
      const PlatformNativeAppIdentityReader(),
}) async {
  NativeAppIdentity nativeIdentity;
  try {
    nativeIdentity = await identityReader.read();
  } on NativeAppIdentityException {
    return const AppConfiguration.invalid(
      environment: null,
      issue: AppConfigurationIssue.nativeIdentityUnavailable,
    );
  }

  return AppConfiguration.resolve(
    environmentValue: SupabaseConfig.environment,
    supabaseUrl: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    nativeIdentity: nativeIdentity,
  );
}

Future<void> initializeSupabase(AppConfiguration configuration) async {
  if (!configuration.isConfigured) return;

  await Supabase.initialize(
    url: configuration._supabaseUrl!,
    publishableKey: configuration._publishableKey!,
    realtimeClientOptions: RealtimeClientOptions(
      transport: const BoundedRealtimeWebSocketTransport().connect,
    ),
  );
}
