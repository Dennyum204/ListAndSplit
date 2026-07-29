import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppEnvironment {
  dev(
    value: 'dev',
    androidFlavor: 'dev',
    androidApplicationId: 'com.ferbatech.listandsplit.dev',
    authCallbackUri: 'com.ferbatech.listandsplit.dev://auth-callback',
  ),
  prod(
    value: 'prod',
    androidFlavor: 'prod',
    androidApplicationId: 'com.ferbatech.listandsplit',
    authCallbackUri: 'com.ferbatech.listandsplit://auth-callback',
  );

  const AppEnvironment({
    required this.value,
    required this.androidFlavor,
    required this.androidApplicationId,
    required this.authCallbackUri,
  });

  final String value;
  final String androidFlavor;
  final String androidApplicationId;
  final String authCallbackUri;

  static AppEnvironment? tryParse(String value) {
    for (final environment in values) {
      if (environment.value == value) return environment;
    }
    return null;
  }
}

class NativeAppIdentity {
  const NativeAppIdentity.android({
    required this.flavor,
    required this.applicationId,
  }) : isAndroid = true;

  const NativeAppIdentity.nonAndroid()
      : isAndroid = false,
        flavor = null,
        applicationId = null;

  final bool isAndroid;
  final String? flavor;
  final String? applicationId;
}

abstract interface class NativeAppIdentityReader {
  Future<NativeAppIdentity> read();
}

class PlatformNativeAppIdentityReader implements NativeAppIdentityReader {
  const PlatformNativeAppIdentityReader();

  static const _channel = MethodChannel(
    'com.ferbatech.listandsplit/app_identity',
  );

  @override
  Future<NativeAppIdentity> read() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const NativeAppIdentity.nonAndroid();
    }

    try {
      final identity =
          await _channel.invokeMapMethod<String, String>('getAppIdentity');
      if (identity == null ||
          identity['platform'] != 'android' ||
          identity['flavor'] == null ||
          identity['applicationId'] == null) {
        throw const NativeAppIdentityException();
      }
      return NativeAppIdentity.android(
        flavor: identity['flavor']!,
        applicationId: identity['applicationId']!,
      );
    } catch (_) {
      throw const NativeAppIdentityException();
    }
  }
}

class NativeAppIdentityException implements Exception {
  const NativeAppIdentityException();

  @override
  String toString() => 'Native application identity is unavailable.';
}
