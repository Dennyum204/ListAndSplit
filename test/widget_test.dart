import 'dart:async';

import 'package:flutter/material.dart';
import 'package:list_and_split/core/presentation/app_bottom_navigation_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/app/startup/startup_host.dart';
import 'package:list_and_split/app/router/app_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/settings/domain/theme_preference.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_controller.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';

import 'helpers/fakes.dart';
import 'helpers/fake_private_template_repository.dart';
import 'helpers/fake_public_template_moderation_repository.dart';
import 'helpers/fake_friend_public_template_feed_repository.dart';
import 'helpers/fake_theme_preference_repository.dart';
import 'helpers/fake_language_preference_repository.dart';
import 'package:list_and_split/features/settings/domain/language_preference.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import 'support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);

  for (final session in [
    const AuthSessionState.signedOut(),
    verifiedSession,
    recoverySession
  ]) {
    testWidgets(
        'welcome preserves restored auth routing ${session.isPasswordRecovery} ${session.user?.id}',
        (tester) async {
      final auth = FakeAuthRepository(session: session);
      addTearDown(auth.close);
      await _pumpConfiguredApp(tester,
          auth: auth,
          profile: FakeProfileRepository(
              profile: FakeProfileRepository.completeProfile),
          startup: true);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeApp), findsNothing);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ListAndSplitApp)));
      expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          session.isPasswordRecovery
              ? AppRoutes.passwordRecovery
              : session.user == null
                  ? AppRoutes.signIn
                  : AppRoutes.lists);
      expect(auth.signOutCalls, 0);
    });
  }

  testWidgets(
      'language selection preserves router, selected tab, drafts, sign-out and restart',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile =
        FakeProfileRepository(profile: FakeProfileRepository.completeProfile);
    final language = FakeLanguagePreferenceRepository();
    addTearDown(auth.close);
    await _pumpConfiguredApp(tester,
        auth: auth, profile: profile, language: language);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ListAndSplitApp)));
    final router = container.read(appRouterProvider);
    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('profileDisplayName'));
    await tester.enterText(field, 'Unsaved language draft');
    await tester.pumpAndSettle();
    final fieldElement = tester.element(field);
    final selector = find.byType(DropdownButton<LanguagePreference>);
    await Scrollable.ensureVisible(tester.element(selector), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider), same(router));
    expect(
        tester
            .widget<AppBottomNavigationBar>(find.byType(AppBottomNavigationBar))
            .selectedIndex,
        3);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('pt'));
    expect(tester.element(field), same(fieldElement));
    expect(tester.widget<TextField>(field).controller!.text,
        'Unsaved language draft');
    expect(profile.updateCalls, 0);
    expect(auth.signOutCalls, 0);
    await tester.tap(find.byKey(const Key('templatesDestination')));
    await tester.pumpAndSettle();
    expect(
        AppLocalizations.of(tester.element(find.byType(AppBottomNavigationBar)))
            .localeName,
        'pt');
    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,
        'Unsaved language draft');
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('pt'));
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpConfiguredApp(tester,
        auth: auth, profile: profile, language: language);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('pt'));
    expect(language.writes, [LanguagePreference.pt]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Profile theme selection preserves router, tab, draft and session',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile =
        FakeProfileRepository(profile: FakeProfileRepository.completeProfile);
    final appearance = FakeThemePreferenceRepository();
    addTearDown(auth.close);
    await _pumpConfiguredApp(tester,
        auth: auth, profile: profile, appearance: appearance);
    final appElement = tester.element(find.byType(ListAndSplitApp));
    final container = ProviderScope.containerOf(appElement);
    final router = container.read(appRouterProvider);
    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('profileDisplayName')), 'Unsaved display name');
    final darkChoice = find.byKey(const Key('themePreference-dark'));
    await tester.ensureVisible(darkChoice);
    await tester.pumpAndSettle();
    await tester.tap(darkChoice);
    await tester.pumpAndSettle();
    expect(container.read(appRouterProvider), same(router));
    expect(
        tester
            .widget<AppBottomNavigationBar>(find.byType(AppBottomNavigationBar))
            .selectedIndex,
        3);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('profileDisplayName')))
            .controller!
            .text,
        'Unsaved display name');
    expect(profile.updateCalls, 0);
    expect(auth.signOutCalls, 0);
    await tester.tap(find.byKey(const Key('templatesDestination')));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byType(AppBottomNavigationBar)))
            .brightness,
        Brightness.dark);
    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('profileDisplayName')))
            .controller!
            .text,
        'Unsaved display name');
    expect(tester.takeException(), isNull);

    // Recreate the app's provider scope to simulate a new process reading storage.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpConfiguredApp(tester,
        auth: auth, profile: profile, appearance: appearance);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expect(auth.signOutCalls, 0);
    expect(appearance.writes, [ThemePreference.dark]);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'full ${brightness.name} shell keeps readable selection and all four destinations',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final auth = FakeAuthRepository(session: verifiedSession);
      addTearDown(auth.close);
      await _pumpConfiguredApp(tester,
          auth: auth,
          profile: FakeProfileRepository(
              profile: FakeProfileRepository.completeProfile),
          lists: FakeActiveListRepository()
            ..activeLists = [
              ActiveListSummary(
                id: 'reference-list',
                title: 'Weekend shopping',
                status: ActiveListStatus.active,
                version: 1,
                itemCount: 7,
                completedItemCount: 3,
                participantCount: 3,
                archivedAt: null,
                createdAt: DateTime.utc(2026, 7, 20),
                updatedAt: DateTime.utc(2026, 7, 20),
              )
            ]);
      const destinations = ['lists', 'templates', 'community', 'profile'];
      for (var index = 0; index < destinations.length; index++) {
        final destination =
            find.byKey(Key('${destinations[index]}Destination'));
        if (index > 0) {
          await tester.tap(destination);
          await tester.pumpAndSettle();
        }
        expect(
            tester
                .widget<AppBottomNavigationBar>(
                    find.byType(AppBottomNavigationBar))
                .selectedIndex,
            index);
        final icon =
            find.descendant(of: destination, matching: find.byType(Icon)).first;
        expect(IconTheme.of(tester.element(icon)).color, AppPalette.navy);
        expect(tester.getSize(destination).height, greaterThanOrEqualTo(48));
        await captureUiPreview(
            tester, 'shell-${destinations[index]}-${brightness.name}');
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('shows an actionable screen when Supabase config is missing',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ListAndSplitApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Supabase to continue'), findsOneWidget);
    expect(find.byIcon(Icons.developer_mode_rounded), findsOneWidget);
  });

  testWidgets('calls out partially supplied configuration', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigurationProvider.overrideWithValue(
            const AppConfiguration.invalid(
              environment: AppEnvironment.dev,
              issue: AppConfigurationIssue.publishableKeyMissing,
              isPartiallyConfigured: true,
            ),
          ),
        ],
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Only one Supabase value is set'), findsOneWidget);
  });

  testWidgets('signed-out navigation supports sign-up and forgot password',
      (tester) async {
    final auth = FakeAuthRepository();
    final profile = FakeProfileRepository();
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('Sign in to your account'), findsOneWidget);
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgotPasswordEmail')),
      'nobody@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'If the address matches an account, a reset link is on its way.'),
      findsOneWidget,
    );
    expect(auth.resetCalls, 1);
    await auth.close();
  });

  testWidgets('sign-up enforces eight characters and preserves the password',
      (tester) async {
    final auth = FakeAuthRepository();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('signUpEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signUpPassword')),
      '1234567',
    );
    await tester.enterText(
      find.byKey(const Key('signUpPasswordConfirmation')),
      '1234567',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(auth.signUpCalls, 0);

    const exactPassword = ' MiXeD7 ';
    await tester.enterText(
      find.byKey(const Key('signUpPassword')),
      exactPassword,
    );
    await tester.enterText(
      find.byKey(const Key('signUpPasswordConfirmation')),
      exactPassword,
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(auth.signUpCalls, 1);
    expect(auth.lastPassword, exactPassword);
    expect(find.text('Verify your email'), findsOneWidget);
    await auth.close();
  });

  testWidgets('auth errors do not leak between signed-out screens',
      (tester) async {
    final auth = FakeAuthRepository()
      ..signInFailure = const AuthFailure(AuthFailureCode.generic);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.enterText(
      find.byKey(const Key('signInEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signInPassword')),
      'wrong-password',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sign you in'), findsOneWidget);

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.textContaining('sign you in'), findsNothing);
    await auth.close();
  });

  testWidgets('unverified session resends verification without discovery',
      (tester) async {
    final auth = FakeAuthRepository(session: unverifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('person@example.com'), findsOneWidget);
    expect(find.byKey(const Key('downloadAccountDataButton')), findsNothing);
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(auth.resendCalls, 1);
    expect(find.textContaining('a new message is on its way'), findsOneWidget);
    await auth.close();
  });

  testWidgets('password recovery updates before entering the app',
      (tester) async {
    final auth = FakeAuthRepository(session: recoverySession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    expect(find.text('Choose a new password'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('recoveryPassword')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const Key('recoveryPasswordConfirmation')),
      'new-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(auth.updatePasswordCalls, 1);
    expect(find.text('No active lists yet'), findsOneWidget);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();
    auth.emit(recoverySession);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await auth.close();
  });

  testWidgets('password recovery can be cancelled by signing out',
      (tester) async {
    final auth = FakeAuthRepository(session: recoverySession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    await tester.tap(find.text('Cancel and sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('Sign in to your account'), findsOneWidget);
    await auth.close();
  });

  testWidgets('onboarding canonicalizes profile then reaches Lists',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository();
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('Choose your profile'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('onboardingUsername')),
      ' Fernando_1 ',
    );
    await tester.enterText(
      find.byKey(const Key('onboardingDisplayName')),
      ' Fernando ',
    );
    await tester.tap(find.text('Finish profile'));
    await tester.pumpAndSettle();

    expect(profile.lastUsername, 'fernando_1');
    expect(profile.lastDisplayName, 'Fernando');
    expect(find.text('No active lists yet'), findsOneWidget);
    await auth.close();
  });

  testWidgets('onboarding offers sign-out and reports a sign-out failure',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession)
      ..operationFailure = StateError('offline');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your profile'), findsOneWidget);
    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);

    auth.operationFailure = null;
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 2);
    expect(find.text('Sign in to your account'), findsOneWidget);
    await auth.close();
  });

  testWidgets('verification email lifecycle handles null and external sign-out',
      (tester) async {
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.devConfigured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(pendingVerificationEmailProvider.notifier).state =
        'new@example.com';
    await tester.pumpAndSettle();
    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(
      container.read(pendingVerificationEmailProvider),
      'new@example.com',
    );
    expect(find.text('Verify your email'), findsOneWidget);

    auth.emit(unverifiedSession);
    await tester.pumpAndSettle();
    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(container.read(pendingVerificationEmailProvider), isNull);
    expect(find.text('Sign in to your account'), findsOneWidget);
    await auth.close();
  });

  testWidgets('a verified session clears a pending verification email',
      (tester) async {
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.devConfigured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(
            profile: FakeProfileRepository.completeProfile,
          ),
        ),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
        activeListRepositoryProvider.overrideWithValue(
          FakeActiveListRepository(),
        ),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          FakePublicTemplateModerationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(pendingVerificationEmailProvider.notifier).state =
        'old@example.com';
    await tester.pumpAndSettle();
    auth.emit(verifiedSession);
    await tester.pumpAndSettle();

    expect(container.read(pendingVerificationEmailProvider), isNull);
    expect(find.text('No active lists yet'), findsOneWidget);
    await auth.close();
  });

  testWidgets('token refresh preserves router, profile, and current location',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.devConfigured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        accountDataExportRepositoryProvider.overrideWithValue(
          FakeAccountDataExportRepository(),
        ),
        accountDataExportShareServiceProvider.overrideWithValue(
          FakeAccountDataExportShareService(),
        ),
        profileRepositoryProvider.overrideWithValue(profile),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
        activeListRepositoryProvider.overrideWithValue(
          FakeActiveListRepository(),
        ),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          FakePublicTemplateModerationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    expect(profile.fetchCalls, 1);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();

    expect(identical(container.read(appRouterProvider), router), isTrue);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.profile);
    expect(find.text('Your profile'), findsOneWidget);
    expect(profile.fetchCalls, 1);
    await auth.close();
  });

  testWidgets('shell replaces the foundation and profile username is read-only',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('No active lists yet'), findsOneWidget);
    expect(find.byKey(const Key('listsDestination')), findsOneWidget);
    expect(find.byKey(const Key('templatesDestination')), findsOneWidget);
    expect(find.byKey(const Key('communityDestination')), findsOneWidget);
    expect(find.byKey(const Key('profileDestination')), findsOneWidget);
    expect(find.textContaining('collaborative lists arrive'), findsNothing);

    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    final usernameField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('profileUsername')),
        matching: find.byType(EditableText),
      ),
    );
    expect(usernameField.readOnly, isTrue);
    expect(find.text('fernando_1'), findsOneWidget);
    expect(find.textContaining('permanent after onboarding'), findsWidgets);
    await auth.close();
  });

  testWidgets('moderation destination stays hidden without protected access',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      moderation: FakePublicTemplateModerationRepository()..hasAccess = false,
    );

    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('openModerationButton')), findsNothing);
    await auth.close();
  });

  testWidgets('protected self-check reveals the moderation destination',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      moderation: FakePublicTemplateModerationRepository()..hasAccess = true,
    );

    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openModerationButton')), findsOneWidget);

    final moderationButton = find.byKey(const Key('openModerationButton'));
    await tester.ensureVisible(moderationButton);
    await tester.tap(moderationButton);
    await tester.pumpAndSettle();
    expect(find.text('Moderation'), findsWidgets);
    expect(find.byKey(const Key('moderationQueueEmpty')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await auth.close();
  });

  testWidgets('four-tab shell preserves branch state and nested Android back',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    expect(find.byKey(const Key('listsDestination')), findsOneWidget);
    expect(find.byKey(const Key('templatesDestination')), findsOneWidget);
    expect(find.byKey(const Key('communityDestination')), findsOneWidget);
    expect(find.byKey(const Key('profileDestination')), findsOneWidget);

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'draft_query',
    );

    await tester.tap(find.byKey(const Key('templatesDestination')));
    await tester.pumpAndSettle();
    expect(find.text('No private templates yet'), findsOneWidget);
    expect(find.byKey(const Key('notificationBellButton')), findsWidgets);

    await _openCommunitySearch(tester);
    expect(find.text('draft_query'), findsOneWidget);
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Friendships'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communityUsername')), findsOneWidget);
    expect(find.text('draft_query'), findsOneWidget);
    await auth.close();
  });

  testWidgets('exact discovery validates, canonicalizes, and confirms block',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await _openCommunitySearch(tester);

    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'invalid username',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starting with a letter'), findsOneWidget);
    expect(community.searchCalls, 0);

    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      '  BETA_USER  ',
    );
    expect(community.searchCalls, 0);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(community.lastUsername, 'beta_user');
    expect(find.text('Beta User'), findsOneWidget);
    expect(find.text('@beta_user'), findsOneWidget);
    expect(find.textContaining('profile-2'), findsNothing);
    expect(find.text('Send request'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('blockSearchResultButton')),
    );
    await tester.tap(find.byKey(const Key('blockSearchResultButton')));
    await tester.pumpAndSettle();
    expect(find.text('Block @beta_user?'), findsOneWidget);
    expect(find.textContaining('won’t be notified'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.blockCalls, 0);

    await tester.ensureVisible(
      find.byKey(const Key('blockSearchResultButton')),
    );
    await tester.tap(find.byKey(const Key('blockSearchResultButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmBlockButton')));
    await tester.pumpAndSettle();

    expect(community.blockCalls, 1);
    expect(community.lastBlockedProfileId, 'profile-2');
    expect(find.byKey(const Key('communitySearchResult')), findsNothing);
    expect(find.textContaining('Profile blocked'), findsOneWidget);
    await auth.close();
  });

  testWidgets('exact discovery sends a caller-relative friend request',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryResult = const FriendshipSummary(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
        status: FriendshipStatus.canSend,
        version: null,
        stateChangedAt: null,
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('sendFriendRequestButton')),
    );
    await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
    await tester.pumpAndSettle();

    expect(friendships.mutationCalls, hasLength(1));
    expect(friendships.mutationCalls.single.operation, 'send');
    expect(friendships.mutationCalls.single.profileId, 'profile-2');
    expect(friendships.mutationCalls.single.expectedVersion, isNull);
    expect(find.text('Friend request sent.'), findsOneWidget);
    await auth.close();
  });

  testWidgets('friendship management groups actions and confirms removal',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository();
    final friendships = FakeFriendshipRepository()
      ..activeRelationships = [
        FriendshipSummary(
          id: 'friend-1',
          username: 'friend_user',
          displayName: 'Friend User',
          status: FriendshipStatus.friends,
          version: 4,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
        FriendshipSummary(
          id: 'incoming-1',
          username: 'incoming_user',
          displayName: 'Incoming User',
          status: FriendshipStatus.incomingPending,
          version: 2,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
        FriendshipSummary(
          id: 'sent-1',
          username: 'sent_user',
          displayName: 'Sent User',
          status: FriendshipStatus.outgoingPending,
          version: 3,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Incoming requests'), findsOneWidget);
    await tester.ensureVisible(find.text('Sent requests'));
    expect(find.text('Sent requests'), findsOneWidget);
    expect(find.text('Friend User'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('acceptFriend-incoming-1')));
    expect(find.byKey(const Key('acceptFriend-incoming-1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('cancelFriend-sent-1')));
    expect(find.byKey(const Key('cancelFriend-sent-1')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('removeFriend-friend-1')));
    await tester.tap(find.byKey(const Key('removeFriend-friend-1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove @friend_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(friendships.mutationCalls, isEmpty);

    await tester.tap(find.byKey(const Key('removeFriend-friend-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRemoveFriendButton')));
    await tester.pumpAndSettle();
    expect(friendships.mutationCalls.single.operation, 'end');
    expect(friendships.mutationCalls.single.expectedVersion, 4);
    expect(find.text('Friend removed.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('blockFriend-friend-1')));
    await tester.tap(find.byKey(const Key('blockFriend-friend-1')));
    await tester.pumpAndSettle();
    expect(find.text('Block @friend_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.blockCalls, 0);

    await tester.tap(find.byKey(const Key('blockFriend-friend-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirmFriendshipBlockButton')),
    );
    await tester.pumpAndSettle();
    expect(community.blockCalls, 1);
    expect(community.lastBlockedProfileId, 'friend-1');
    expect(find.textContaining('Profile blocked'), findsOneWidget);
    await auth.close();
  });

  testWidgets('friendship management shows loading, empty, and manual refresh',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final friendships = FakeFriendshipRepository()
      ..friendshipListCompleter = Completer<List<FriendshipSummary>>();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.bySemanticsLabel('Loading friendships'), findsOneWidget);

    friendships.friendshipListCompleter!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No active friendships or requests'), findsOneWidget);

    friendships
      ..friendshipListCompleter = null
      ..activeRelationships = [
        FriendshipSummary(
          id: 'friend-2',
          username: 'refresh_user',
          displayName: 'Refresh User',
          status: FriendshipStatus.friends,
          version: 2,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
      ];
    await tester.tap(find.byKey(const Key('refreshFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Refresh User'), findsOneWidget);
    expect(friendships.friendshipListCalls, 2);
    await auth.close();
  });

  testWidgets('friendship management load failure is retryable',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final friendships = FakeFriendshipRepository()
      ..listFailure = StateError('private backend details');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retryFriendshipsButton')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsWidgets);
    expect(find.textContaining('private backend'), findsNothing);

    friendships.listFailure = null;
    await tester.tap(find.byKey(const Key('retryFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('No active friendships or requests'), findsOneWidget);
    expect(friendships.friendshipListCalls, 2);
    await auth.close();
  });

  testWidgets('discovered unavailable relationship stays privacy-safe',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryResult = const FriendshipSummary(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
        status: FriendshipStatus.unavailable,
        version: null,
        stateChangedAt: null,
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('Friend requests aren’t available for this profile.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sendFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('cancelFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('acceptFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('declineFriendRequestButton')), findsNothing);
    expect(find.textContaining('declined'), findsNothing);
    expect(find.textContaining('ended'), findsNothing);
    expect(find.textContaining('reopen'), findsNothing);
    await auth.close();
  });

  testWidgets('summary unavailability clears the discovered profile card',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryFailure =
          const FriendshipFailure(FriendshipFailureCode.unavailable);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('No matching profile was found or is available.'),
      findsOneWidget,
    );
    expect(find.text('Beta User'), findsNothing);
    expect(find.byKey(const Key('sendFriendRequestButton')), findsNothing);
    await auth.close();
  });

  testWidgets('missing exact discovery uses the generic unavailable result',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'missing_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('No matching profile was found or is available.'),
      findsOneWidget,
    );
    expect(find.textContaining('blocked by'), findsNothing);
    await auth.close();
  });

  testWidgets('blocked users are private and unblock requires confirmation',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..blockedProfiles = const [
        BlockedProfile(
          id: 'profile-2',
          username: 'beta_user',
          displayName: 'Beta User',
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await _openCommunitySearch(tester);
    await tester.tap(find.byKey(const Key('manageBlockedUsersButton')));
    await tester.pumpAndSettle();

    expect(find.text('Blocked users'), findsOneWidget);
    expect(find.text('Beta User'), findsOneWidget);
    expect(find.text('@beta_user'), findsOneWidget);
    expect(
        find.textContaining('Incoming blocks are never shown'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unblockProfile-profile-2')));
    await tester.pumpAndSettle();
    expect(find.text('Unblock @beta_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.unblockCalls, 0);

    await tester.tap(find.byKey(const Key('unblockProfile-profile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmUnblockButton')));
    await tester.pumpAndSettle();

    expect(community.unblockCalls, 1);
    expect(find.text('No blocked users'), findsOneWidget);
    expect(find.textContaining('No relationship was restored'), findsOneWidget);
    await auth.close();
  });

  testWidgets('blocked-user load failures can be retried safely',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..listFailure = StateError('database details');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await _openCommunitySearch(tester);
    await tester.tap(find.byKey(const Key('manageBlockedUsersButton')));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong. Please try again.'), findsWidgets);

    community.listFailure = null;
    await tester.tap(find.byKey(const Key('retryBlockedUsersButton')));
    await tester.pumpAndSettle();
    expect(find.text('No blocked users'), findsOneWidget);
    expect(community.listCalls, 2);
    await auth.close();
  });

  testWidgets('community search state clears across session changes',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await _openCommunitySearch(tester);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communitySearchResult')), findsOneWidget);

    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your account'), findsOneWidget);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();
    await _openCommunitySearch(tester);
    expect(find.byKey(const Key('communitySearchResult')), findsNothing);
    await auth.close();
  });

  testWidgets('list cache is isolated when the authenticated identity changes',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final lists = FakeActiveListRepository()
      ..activeLists = [
        ActiveListSummary(
          id: 'account-a-list',
          title: 'Account A private list',
          status: ActiveListStatus.active,
          version: 1,
          itemCount: 0,
          completedItemCount: 0,
          createdAt: DateTime.utc(2026, 7, 20, 8),
          updatedAt: DateTime.utc(2026, 7, 20, 8),
          archivedAt: null,
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      lists: lists,
    );
    expect(find.text('Account A private list'), findsOneWidget);

    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    lists.activeLists = [
      ActiveListSummary(
        id: 'account-b-list',
        title: 'Account B private list',
        status: ActiveListStatus.active,
        version: 1,
        itemCount: 0,
        completedItemCount: 0,
        createdAt: DateTime.utc(2026, 7, 20, 9),
        updatedAt: DateTime.utc(2026, 7, 20, 9),
        archivedAt: null,
      ),
    ];
    auth.emit(verifiedSession);
    await tester.pumpAndSettle();

    expect(find.text('Account A private list'), findsNothing);
    expect(find.text('Account B private list'), findsOneWidget);
    await auth.close();
  });

  testWidgets('sign-out returns the user to sign-in', (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    await tester.tap(find.byKey(const Key('profileDestination')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('Sign in to your account'), findsOneWidget);
    await auth.close();
  });

  testWidgets('notification badge opens the centre and displayed rows are read',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final notifications = FakeNotificationRepository()
      ..unreadCount = 3
      ..notifications = [
        InAppNotification(
          id: 'notification-1',
          type: InAppNotificationType.friendRequest,
          createdAt: DateTime.utc(2026, 7, 19, 8),
          isRead: false,
          actorProfileId: 'profile-2',
          actorUsername: 'beta_user',
          actorDisplayName: 'Beta User',
          actionStatus: NotificationActionStatus.actionable,
          expectedRelationshipVersion: 7,
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      notifications: notifications,
    );

    expect(find.text('3'), findsOneWidget);
    expect(
      find.bySemanticsLabel('3 unread notifications'),
      findsOneWidget,
    );

    notifications.unreadCount = 0;
    await tester.tap(find.byKey(const Key('notificationBellButton')));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Beta User sent you a friend request'), findsOneWidget);
    expect(notifications.markCalls, [
      ['notification-1'],
    ]);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
    await auth.close();
  });

  testWidgets('stale notification action reconciles without manual refresh',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final actionable = InAppNotification(
      id: 'notification-1',
      type: InAppNotificationType.friendRequest,
      createdAt: DateTime.utc(2026, 7, 19, 8),
      isRead: false,
      actorProfileId: 'profile-2',
      actorUsername: 'beta_user',
      actorDisplayName: 'Beta User',
      actionStatus: NotificationActionStatus.actionable,
      expectedRelationshipVersion: 7,
    );
    final notifications = FakeNotificationRepository()
      ..unreadCount = 1
      ..queuedPages.addAll([
        [actionable],
        [
          InAppNotification(
            id: actionable.id,
            type: actionable.type,
            createdAt: actionable.createdAt,
            isRead: true,
            actorProfileId: actionable.actorProfileId,
            actorUsername: actionable.actorUsername,
            actorDisplayName: actionable.actorDisplayName,
            actionStatus: NotificationActionStatus.unavailable,
            expectedRelationshipVersion: null,
          ),
        ],
      ]);
    final friendships = FakeFriendshipRepository()
      ..mutationFailure =
          const FriendshipFailure(FriendshipFailureCode.unavailable);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      friendships: friendships,
      notifications: notifications,
    );

    expect(
      find.bySemanticsLabel('1 unread notification'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('notificationBellButton')));
    await tester.pumpAndSettle();
    notifications.unreadCount = 0;

    await tester.tap(
      find.byKey(const Key('acceptNotification-notification-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This relationship changed elsewhere. The latest state is shown.',
      ),
      findsOneWidget,
    );
    expect(find.text('This request is no longer available.'), findsOneWidget);
    expect(
      find.byKey(const Key('acceptNotification-notification-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('declineNotification-notification-1')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(notifications.listCalls, hasLength(2));
    expect(friendships.mutationCalls, hasLength(1));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('1 unread notification'),
      findsNothing,
    );
    await auth.close();
  });
}

Future<void> _pumpConfiguredApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeProfileRepository profile,
  FakeCommunityRepository? community,
  FakeFriendshipRepository? friendships,
  FakeNotificationRepository? notifications,
  FakeActiveListRepository? lists,
  FakePublicTemplateModerationRepository? moderation,
  ThemePreferenceRepository? appearance,
  LanguagePreferenceRepository? language,
  bool startup = false,
}) async {
  final defaultFriendships = FakeFriendshipRepository()
    ..summaryResult = const FriendshipSummary(
      id: 'profile-2',
      username: 'beta_user',
      displayName: 'Beta User',
      status: FriendshipStatus.canSend,
      version: null,
      stateChangedAt: null,
    );
  await tester.pumpWidget(
    uiPreviewBoundary(ProviderScope(
      overrides: [
        languagePreferenceRepositoryProvider
            .overrideWithValue(language ?? FakeLanguagePreferenceRepository()),
        themePreferenceRepositoryProvider.overrideWithValue(
          appearance ?? FakeThemePreferenceRepository(),
        ),
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.devConfigured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        accountDataExportRepositoryProvider.overrideWithValue(
          FakeAccountDataExportRepository(),
        ),
        accountDataExportShareServiceProvider.overrideWithValue(
          FakeAccountDataExportShareService(),
        ),
        profileRepositoryProvider.overrideWithValue(profile),
        communityRepositoryProvider.overrideWithValue(
          community ?? FakeCommunityRepository(),
        ),
        friendshipRepositoryProvider.overrideWithValue(
          friendships ?? defaultFriendships,
        ),
        notificationRepositoryProvider.overrideWithValue(
          notifications ?? FakeNotificationRepository(),
        ),
        activeListRepositoryProvider.overrideWithValue(
          lists ?? FakeActiveListRepository(),
        ),
        privateTemplateRepositoryProvider.overrideWithValue(
          FakePrivateTemplateRepository(),
        ),
        friendPublicTemplateFeedRepositoryProvider.overrideWithValue(
          FakeFriendPublicTemplateFeedRepository(),
        ),
        publicTemplateModerationRepositoryProvider.overrideWithValue(
          moderation ?? FakePublicTemplateModerationRepository(),
        ),
      ],
      child: startup
          ? StartupHost(initialize: () async => const ListAndSplitApp())
          : const ListAndSplitApp(),
    )),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCommunitySearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('communityDestination')));
  await tester.pumpAndSettle();
  final friendsAction = find.byKey(const Key('openCommunityFriendsButton'));
  if (friendsAction.evaluate().isNotEmpty) {
    await tester.tap(friendsAction);
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const Key('communityUsername')), findsOneWidget);
}
