import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/auth/presentation/sign_in_screen.dart';
import 'package:list_and_split/features/auth/presentation/sign_up_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    test('${mode.name} reference palette preserves readable text contrast', () {
      final theme = mode == ThemeMode.light ? AppTheme.light : AppTheme.dark;
      expect(theme.scaffoldBackgroundColor,
          mode == ThemeMode.light ? AppPalette.cream : AppPalette.dark);
      expect(theme.inputDecorationTheme.fillColor, AppPalette.inputCream);
      final floatingLabel = theme.inputDecorationTheme.floatingLabelStyle!;
      expect(_contrast(floatingLabel.color!, floatingLabel.backgroundColor!),
          greaterThan(4.5));
      expect(
          _contrast(AppPalette.navy, AppPalette.inputCream), greaterThan(4.5));
      expect(_contrast(AppPalette.navy, AppPalette.orange), greaterThan(4.5));
      expect(
          _contrast(theme.colorScheme.onSurface, theme.scaffoldBackgroundColor),
          greaterThan(4.5));
      expect(_contrast(theme.colorScheme.onSurface, theme.cardTheme.color!),
          greaterThan(4.5));
      expect(
          _contrast(AppPalette.lightText, theme.appBarTheme.backgroundColor!),
          greaterThan(4.5));
    });

    testWidgets('sign-in ${mode.name} reference layout at normal text',
        (tester) async {
      final auth = FakeAuthRepository();
      addTearDown(auth.close);
      await _pump(tester,
          auth: auth,
          mode: mode,
          language: 'en',
          scale: 1,
          child: const SignInScreen());
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48));
      await captureUiPreview(tester, 'sign-in-en-${mode.name}-100');
      expect(tester.takeException(), isNull);
    });

    for (final language in ['en', 'pt']) {
      for (final signUp in [false, true]) {
        testWidgets(
            '${signUp ? 'register' : 'login'} $language ${mode.name} '
            '200% preserves fields, scroll access and validation',
            (tester) async {
          final auth = FakeAuthRepository();
          addTearDown(auth.close);
          await _pump(tester,
              auth: auth,
              mode: mode,
              language: language,
              scale: 2,
              child: signUp ? const SignUpScreen() : const SignInScreen());
          final fields = tester.widgetList<TextField>(find.byType(TextField));
          expect(fields.length, signUp ? 3 : 2);
          for (final field in fields) {
            expect(field.style?.color, AppPalette.navy);
          }
          final submit = find.byType(FilledButton);
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(auth.signInCalls + auth.signUpCalls, 0);
          expect(
              tester
                  .widgetList<TextField>(find.byType(TextField))
                  .where((field) => field.decoration?.errorText != null)
                  .length,
              greaterThanOrEqualTo(2));
          await captureUiPreview(tester,
              '${signUp ? 'register' : 'login'}-$language-${mode.name}-200');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required ThemeMode mode,
  required String language,
  required double scale,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(uiPreviewBoundary(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  )));
  await tester.pumpAndSettle();
}
