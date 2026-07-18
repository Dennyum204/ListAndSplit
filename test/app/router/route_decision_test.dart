import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';

import '../../helpers/fakes.dart';

void main() {
  AppRouteDecision decision({
    bool configured = true,
    bool authReady = true,
    bool authFailed = false,
    AuthSessionState? session = verifiedSession,
    bool profileReady = true,
    UserProfile? profile,
    bool profileFailed = false,
    String? pendingEmail,
    bool recoveryCompleted = false,
  }) {
    return AppRouteDecision(
      isConfigured: configured,
      isAuthReady: authReady,
      isAuthFailed: authFailed,
      session: session,
      isProfileReady: profileReady,
      profile: profile ?? FakeProfileRepository.completeProfile,
      isProfileFailed: profileFailed,
      pendingVerificationEmail: pendingEmail,
      isPasswordRecoveryCompleted: recoveryCompleted,
    );
  }

  test('missing configuration has highest priority', () {
    expect(
      decision(configured: false).redirect(AppRoutes.foundation),
      AppRoutes.configuration,
    );
  });

  test('waits for initial auth and profile state', () {
    expect(
      decision(authReady: false).redirect(AppRoutes.foundation),
      AppRoutes.loading,
    );
    expect(
      decision(profileReady: false).redirect(AppRoutes.foundation),
      AppRoutes.loading,
    );
  });

  test('auth failures use the recoverable account screen', () {
    expect(
      decision(authFailed: true).redirect(AppRoutes.foundation),
      AppRoutes.accountError,
    );
  });

  test('signed-out users can use only signed-out routes', () {
    final signedOut = decision(
      session: const AuthSessionState.signedOut(),
    );
    expect(signedOut.redirect(AppRoutes.signIn), isNull);
    expect(signedOut.redirect(AppRoutes.signUp), isNull);
    expect(signedOut.redirect(AppRoutes.forgotPassword), isNull);
    expect(signedOut.redirect(AppRoutes.foundation), AppRoutes.signIn);
  });

  test('pending and authenticated unverified users must verify', () {
    expect(
      decision(
        session: const AuthSessionState.signedOut(),
        pendingEmail: 'person@example.com',
      ).redirect(AppRoutes.signIn),
      AppRoutes.verification,
    );
    expect(
      decision(session: unverifiedSession).redirect(AppRoutes.foundation),
      AppRoutes.verification,
    );
  });

  test('recovery takes priority after verified authentication', () {
    expect(
      decision(session: recoverySession).redirect(AppRoutes.foundation),
      AppRoutes.passwordRecovery,
    );
    expect(
      decision(
        session: recoverySession,
        recoveryCompleted: true,
      ).redirect(AppRoutes.foundation),
      isNull,
    );
  });

  test('incomplete profile must finish onboarding', () {
    expect(
      decision(profile: FakeProfileRepository.incompleteProfile)
          .redirect(AppRoutes.foundation),
      AppRoutes.onboarding,
    );
  });

  test('profile load failures use a recoverable screen', () {
    expect(
      decision(profileFailed: true).redirect(AppRoutes.foundation),
      AppRoutes.accountError,
    );
  });

  test('completed profile may use foundation and profile routes', () {
    final complete = decision();
    expect(complete.redirect(AppRoutes.foundation), isNull);
    expect(complete.redirect(AppRoutes.profile), isNull);
    expect(complete.redirect(AppRoutes.signIn), AppRoutes.foundation);
  });
}
