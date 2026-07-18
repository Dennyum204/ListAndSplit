import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/auth/data/password_recovery_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the non-secret marker survives a new storage adapter instance',
      () async {
    await SharedPreferencesPasswordRecoveryMarker().write(true);

    expect(
      await SharedPreferencesPasswordRecoveryMarker().read(),
      isTrue,
    );

    await SharedPreferencesPasswordRecoveryMarker().write(false);
    expect(
      await SharedPreferencesPasswordRecoveryMarker().read(),
      isFalse,
    );
  });

  test('cold start restores recovery and token refresh preserves the gate',
      () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesPasswordRecoveryMarker.storageKey: true,
    });
    final lifecycle = PasswordRecoveryLifecycle(
      SharedPreferencesPasswordRecoveryMarker(),
    );

    await lifecycle.handle(PasswordRecoverySessionEvent.initialSession);
    expect(lifecycle.isPending, isTrue);
    expect(lifecycle.attempt, 1);

    await lifecycle.handle(PasswordRecoverySessionEvent.tokenRefreshed);
    await lifecycle.handle(PasswordRecoverySessionEvent.userUpdated);
    expect(lifecycle.isPending, isTrue);
    expect(lifecycle.attempt, 1);

    await lifecycle.complete();
    expect(lifecycle.isPending, isFalse);
    expect(
      await SharedPreferencesPasswordRecoveryMarker().read(),
      isFalse,
    );
  });

  test('normal sign-in and sign-out clear a pending recovery marker', () async {
    final marker = SharedPreferencesPasswordRecoveryMarker();
    final lifecycle = PasswordRecoveryLifecycle(marker);

    await lifecycle.handle(PasswordRecoverySessionEvent.passwordRecovery);
    expect(lifecycle.isPending, isTrue);
    await lifecycle.handle(PasswordRecoverySessionEvent.signedIn);
    expect(lifecycle.isPending, isFalse);
    expect(lifecycle.attempt, 0);

    await lifecycle.handle(PasswordRecoverySessionEvent.passwordRecovery);
    await lifecycle.handle(PasswordRecoverySessionEvent.signedOut);
    expect(lifecycle.isPending, isFalse);
    expect(lifecycle.attempt, 0);
    expect(await marker.read(), isFalse);
  });
}
