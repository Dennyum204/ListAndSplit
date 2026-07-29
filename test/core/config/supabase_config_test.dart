import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/config/supabase_config.dart';

void main() {
  const devUrl = 'https://${AppConfiguration.devProjectHost}';
  const key = 'test-publishable-key';
  const devIdentity = NativeAppIdentity.android(
    flavor: 'dev',
    applicationId: 'com.ferbatech.listandsplit.dev',
  );
  const prodIdentity = NativeAppIdentity.android(
    flavor: 'prod',
    applicationId: 'com.ferbatech.listandsplit',
  );

  AppConfiguration resolve({
    String environment = 'dev',
    String url = devUrl,
    String publishableKey = key,
    NativeAppIdentity identity = devIdentity,
  }) =>
      AppConfiguration.resolve(
        environmentValue: environment,
        supabaseUrl: url,
        publishableKey: publishableKey,
        nativeIdentity: identity,
      );

  test('accepts the exact Dev environment and native identity', () {
    final configuration = resolve();

    expect(configuration.isConfigured, isTrue);
    expect(configuration.issue, isNull);
    expect(configuration.environment, AppEnvironment.dev);
    expect(
      configuration.authCallbackUri,
      'com.ferbatech.listandsplit.dev://auth-callback',
    );
  });

  test('rejects a missing environment', () {
    expect(
      resolve(environment: '').issue,
      AppConfigurationIssue.environmentMissing,
    );
  });

  test('rejects an invalid environment', () {
    expect(
      resolve(environment: 'staging').issue,
      AppConfigurationIssue.environmentInvalid,
    );
  });

  test('rejects a missing Supabase URL', () {
    expect(
      resolve(url: '').issue,
      AppConfigurationIssue.supabaseUrlMissing,
    );
  });

  test('rejects a missing publishable key', () {
    final configuration = resolve(publishableKey: '');

    expect(
      configuration.issue,
      AppConfigurationIssue.publishableKeyMissing,
    );
    expect(configuration.isPartiallyConfigured, isTrue);
  });

  test('rejects malformed or non-HTTPS Supabase URLs', () {
    for (final url in [
      'not-a-url',
      'http://${AppConfiguration.devProjectHost}',
      '$devUrl/unexpected',
      '$devUrl?unexpected=true',
    ]) {
      expect(
        resolve(url: url).issue,
        AppConfigurationIssue.supabaseUrlMalformed,
        reason: url,
      );
    }
  });

  test('rejects a Dev Dart environment in the Production flavor', () {
    expect(
      resolve(identity: prodIdentity).issue,
      AppConfigurationIssue.nativeFlavorMismatch,
    );
  });

  test('rejects a Production Dart environment in the Dev flavor', () {
    expect(
      resolve(environment: 'prod').issue,
      AppConfigurationIssue.nativeFlavorMismatch,
    );
  });

  test('rejects an unexpected application ID even with a matching flavor', () {
    expect(
      resolve(
        identity: const NativeAppIdentity.android(
          flavor: 'dev',
          applicationId: 'com.example.crossed',
        ),
      ).issue,
      AppConfigurationIssue.nativeApplicationIdMismatch,
    );
  });

  test('rejects a different project in the Dev flavor', () {
    expect(
      resolve(url: 'https://different-project.supabase.co').issue,
      AppConfigurationIssue.devProjectMismatch,
    );
  });

  test('rejects the Dev project in the Production flavor', () {
    expect(
      resolve(
        environment: 'prod',
        identity: prodIdentity,
      ).issue,
      AppConfigurationIssue.productionDevProjectRejected,
    );
  });

  test('keeps Production unavailable without an approved project contract', () {
    expect(
      resolve(
        environment: 'prod',
        url: 'https://future-production.supabase.co',
        identity: prodIdentity,
      ).issue,
      AppConfigurationIssue.productionUnavailable,
    );
  });

  test('selects distinct callbacks while preserving the callback host', () {
    expect(
      AppEnvironment.dev.authCallbackUri,
      'com.ferbatech.listandsplit.dev://auth-callback',
    );
    expect(
      AppEnvironment.prod.authCallbackUri,
      'com.ferbatech.listandsplit://auth-callback',
    );
  });

  test('keeps the current unsuffixed callback outside Android', () {
    final configuration = resolve(
      identity: const NativeAppIdentity.nonAndroid(),
    );

    expect(configuration.isConfigured, isTrue);
    expect(
      configuration.authCallbackUri,
      'com.ferbatech.listandsplit://auth-callback',
    );
  });

  test('configuration failures do not retain supplied values', () {
    const sensitiveUrl = 'https://unexpected-project.supabase.co';
    const sensitiveKey = 'do-not-report-this-value';
    final configuration = resolve(
      url: sensitiveUrl,
      publishableKey: sensitiveKey,
    );

    expect(configuration.toString(), isNot(contains(sensitiveUrl)));
    expect(configuration.toString(), isNot(contains(sensitiveKey)));
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
