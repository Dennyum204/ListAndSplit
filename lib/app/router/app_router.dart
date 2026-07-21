import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/app/screens/account_error_screen.dart';
import 'package:list_and_split/app/screens/authenticated_shell.dart';
import 'package:list_and_split/app/screens/configuration_screen.dart';
import 'package:list_and_split/app/screens/loading_screen.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/auth/presentation/forgot_password_screen.dart';
import 'package:list_and_split/features/auth/presentation/password_recovery_screen.dart';
import 'package:list_and_split/features/auth/presentation/sign_in_screen.dart';
import 'package:list_and_split/features/auth/presentation/sign_up_screen.dart';
import 'package:list_and_split/features/auth/presentation/verification_screen.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_screen.dart';
import 'package:list_and_split/features/community/presentation/community_screen.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_members_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_screen.dart';
import 'package:list_and_split/features/notifications/presentation/notification_centre_screen.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/profile/presentation/onboarding_screen.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_screen.dart';
import 'package:list_and_split/features/templates/presentation/templates_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_detail_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _listsNavigatorKey = GlobalKey<NavigatorState>();
final _templatesNavigatorKey = GlobalKey<NavigatorState>();
final _communityNavigatorKey = GlobalKey<NavigatorState>();
final _profileNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable();
  final configuration = ref.read(appConfigurationProvider);

  if (configuration.isConfigured) {
    ref.listen<AsyncValue<AuthSessionState>>(authSessionProvider,
        (previous, next) {
      if (next.hasValue) {
        final previousSession = previous?.valueOrNull;
        final currentSession = next.valueOrNull;
        final previousUser = previous?.valueOrNull?.user;
        final currentUser = currentSession?.user;
        final didSignOut = previousUser != null && currentUser == null;
        final beganPasswordRecovery =
            currentSession?.isPasswordRecovery == true &&
                (previousSession?.isPasswordRecovery != true ||
                    previousSession?.passwordRecoveryAttempt !=
                        currentSession?.passwordRecoveryAttempt);

        if (currentUser?.isEmailVerified == true || didSignOut) {
          ref.read(pendingVerificationEmailProvider.notifier).state = null;
        }
        if (didSignOut || beganPasswordRecovery) {
          ref.read(completedPasswordRecoveryAttemptProvider.notifier).state =
              null;
        }
      }
      refreshListenable.refresh();
    });
    ref.listen(ownProfileProvider, (_, __) => refreshListenable.refresh());
    ref.listen(
      pendingVerificationEmailProvider,
      (_, __) => refreshListenable.refresh(),
    );
    ref.listen(
      completedPasswordRecoveryAttemptProvider,
      (_, __) => refreshListenable.refresh(),
    );
  }

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.lists,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final decision = _routeDecision(ref);
      return decision.redirect(state.uri.path);
    },
    routes: [
      GoRoute(
        path: AppRoutes.configuration,
        builder: (context, state) => const ConfigurationScreen(),
      ),
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.verification,
        builder: (context, state) => const VerificationScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.passwordRecovery,
        builder: (context, state) => const PasswordRecoveryScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => Consumer(
          builder: (context, routeRef, child) {
            final actionsProvider =
                authActionsControllerProvider(AuthActionFlow.session);
            routeRef.watch(actionsProvider);
            return OnboardingScreen(
              onSignOut: () {
                return routeRef.read(actionsProvider.notifier).signOut();
              },
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.accountError,
        builder: (context, state) => const AccountErrorScreen(),
      ),
      GoRoute(
        path: AppRoutes.foundation,
        redirect: (_, __) => AppRoutes.lists,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AuthenticatedShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            navigatorKey: _listsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.lists,
                builder: (context, state) => const ActiveListsScreen(),
                routes: [
                  GoRoute(
                    path: ':listId',
                    builder: (context, state) => ActiveListDetailScreen(
                      listId: state.pathParameters['listId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'members',
                        builder: (context, state) => ActiveListMembersScreen(
                          listId: state.pathParameters['listId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _templatesNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.templates,
                builder: (context, state) => const TemplatesScreen(),
                routes: [
                  GoRoute(
                    path: ':templateId',
                    builder: (context, state) => PrivateTemplateDetailScreen(
                      templateId: state.pathParameters['templateId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _communityNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.community,
                builder: (context, state) => const CommunityScreen(),
                routes: [
                  GoRoute(
                    path: 'friendships',
                    builder: (context, state) =>
                        const FriendshipManagementScreen(),
                  ),
                  GoRoute(
                    path: 'blocked',
                    builder: (context, state) => const BlockedUsersScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationCentreScreen(),
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refreshListenable.dispose();
  });
  return router;
});

AppRouteDecision _routeDecision(Ref ref) {
  final configuration = ref.read(appConfigurationProvider);
  var isAuthReady = false;
  var isAuthFailed = false;
  AuthSessionState? session;
  var isProfileReady = false;
  var isProfileFailed = false;
  UserProfile? profile;

  if (configuration.isConfigured) {
    final auth = ref.read(authSessionProvider);
    isAuthReady = !auth.isLoading;
    isAuthFailed = auth.hasError;
    session = auth.valueOrNull;

    if (session?.user?.isEmailVerified == true) {
      final ownProfile = ref.read(ownProfileProvider);
      profile = ownProfile.valueOrNull;
      isProfileReady = !ownProfile.isLoading || profile != null;
      isProfileFailed = ownProfile.hasError && !ownProfile.hasValue;
    }
  }

  return AppRouteDecision(
    isConfigured: configuration.isConfigured,
    isAuthReady: isAuthReady,
    isAuthFailed: isAuthFailed,
    session: session,
    isProfileReady: isProfileReady,
    profile: profile,
    isProfileFailed: isProfileFailed,
    pendingVerificationEmail: ref.read(pendingVerificationEmailProvider),
    isPasswordRecoveryCompleted: session?.passwordRecoveryAttempt != 0 &&
        ref.read(completedPasswordRecoveryAttemptProvider) ==
            session?.passwordRecoveryAttempt,
  );
}

class _RouterRefreshListenable extends ChangeNotifier {
  var _isRefreshScheduled = false;
  var _isDisposed = false;

  void refresh() {
    if (_isRefreshScheduled || _isDisposed) return;
    _isRefreshScheduled = true;
    scheduleMicrotask(() {
      _isRefreshScheduled = false;
      if (!_isDisposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
