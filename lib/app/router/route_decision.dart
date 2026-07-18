import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';

abstract final class AppRoutes {
  static const configuration = '/configuration';
  static const loading = '/loading';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const verification = '/verify-email';
  static const forgotPassword = '/forgot-password';
  static const passwordRecovery = '/password-recovery';
  static const onboarding = '/onboarding';
  static const accountError = '/account-error';
  static const foundation = '/';
  static const profile = '/profile';
}

class AppRouteDecision {
  const AppRouteDecision({
    required this.isConfigured,
    required this.isAuthReady,
    required this.isAuthFailed,
    required this.session,
    required this.isProfileReady,
    required this.profile,
    required this.isProfileFailed,
    required this.pendingVerificationEmail,
    required this.isPasswordRecoveryCompleted,
  });

  final bool isConfigured;
  final bool isAuthReady;
  final bool isAuthFailed;
  final AuthSessionState? session;
  final bool isProfileReady;
  final UserProfile? profile;
  final bool isProfileFailed;
  final String? pendingVerificationEmail;
  final bool isPasswordRecoveryCompleted;

  String? redirect(String currentPath) {
    if (!isConfigured) {
      return _unlessCurrent(currentPath, AppRoutes.configuration);
    }

    if (!isAuthReady) return _unlessCurrent(currentPath, AppRoutes.loading);

    if (isAuthFailed) {
      return _unlessCurrent(currentPath, AppRoutes.accountError);
    }

    final user = session?.user;
    if (user == null) {
      if (pendingVerificationEmail != null) {
        return _unlessCurrent(currentPath, AppRoutes.verification);
      }
      if (_isSignedOutRoute(currentPath)) return null;
      return AppRoutes.signIn;
    }

    if (!user.isEmailVerified) {
      return _unlessCurrent(currentPath, AppRoutes.verification);
    }

    if (session!.isPasswordRecovery && !isPasswordRecoveryCompleted) {
      return _unlessCurrent(currentPath, AppRoutes.passwordRecovery);
    }

    if (!isProfileReady) {
      return _unlessCurrent(currentPath, AppRoutes.loading);
    }

    if (isProfileFailed) {
      return _unlessCurrent(currentPath, AppRoutes.accountError);
    }

    if (profile?.isOnboardingComplete != true) {
      return _unlessCurrent(currentPath, AppRoutes.onboarding);
    }

    if (currentPath == AppRoutes.foundation ||
        currentPath == AppRoutes.profile) {
      return null;
    }
    return AppRoutes.foundation;
  }

  static bool _isSignedOutRoute(String path) =>
      path == AppRoutes.signIn ||
      path == AppRoutes.signUp ||
      path == AppRoutes.forgotPassword;

  static String? _unlessCurrent(String current, String target) =>
      current == target ? null : target;
}
