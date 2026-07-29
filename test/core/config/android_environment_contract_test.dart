import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gradle declares explicit isolated Dev and Production flavors', () {
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(gradle, contains('flavorDimensions "environment"'));
    expect(gradle, contains('applicationId "com.ferbatech.listandsplit"'));
    expect(gradle, contains('applicationIdSuffix ".dev"'));
    expect(
        gradle, contains('resValue "string", "app_name", "List & Split Dev"'));
    expect(gradle, contains('resValue "string", "app_name", "List & Split"'));
    expect(
      gradle,
      contains('authRedirectScheme: "com.ferbatech.listandsplit.dev"'),
    );
    expect(
      gradle,
      contains('authRedirectScheme: "com.ferbatech.listandsplit"'),
    );
    expect(
      gradle,
      contains('unflavored Android builds are disabled'),
    );
  });

  test('Android manifest binds label and callback to flavor resources', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:label="@string/app_name"'));
    expect(manifest, contains(r'android:scheme="${authRedirectScheme}"'));
    expect(manifest, contains('android:host="auth-callback"'));
  });

  test('Android exposes non-caller-controlled flavor and package identity', () {
    final activity = File(
      'android/app/src/main/kotlin/com/ferbatech/listandsplit/MainActivity.kt',
    ).readAsStringSync();

    expect(
      activity,
      contains('"com.ferbatech.listandsplit/app_identity"'),
    );
    expect(activity, contains('"flavor" to BuildConfig.FLAVOR'));
    expect(
      activity,
      contains('"applicationId" to applicationContext.packageName'),
    );
  });
}
