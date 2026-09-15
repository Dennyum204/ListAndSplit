import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/auth/presentation/auth_actions_controller.dart';
import 'package:list_and_split/features/auth/presentation/sign_in_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);
  for (final locale in ['en', 'pt']) {
    for (final dark in [false, true]) {
      testWidgets(
          'Login placeholders, named filled fields and validation $locale dark=$dark',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final auth = FakeAuthRepository();
        addTearDown(auth.close);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              authActionsControllerProvider(AuthActionFlow.signIn).overrideWith(
                  (ref) => AuthActionsController(auth,
                      onVerificationPending: (_) {},
                      onRecoveryCompleted: () {},
                      onSignedOut: () {})),
            ],
            child: uiPreviewBoundary(MaterialApp(
              locale: Locale(locale),
              theme: dark ? AppTheme.dark : AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const SignInScreen(),
            ))));
        await tester.pumpAndSettle();
        final email = find.byKey(const Key('signInEmail'));
        final password = find.byKey(const Key('signInPassword'));
        final l10n = AppLocalizations.of(tester.element(email));
        expect(tester.widget<TextField>(email).decoration!.labelText, isNull);
        expect(
            tester.widget<TextField>(password).decoration!.labelText, isNull);
        expect(find.text(l10n.emailLabel), findsOneWidget);
        expect(find.text(l10n.passwordLabel), findsOneWidget);
        expect(tester.widget<TextField>(email).keyboardType,
            TextInputType.emailAddress);
        expect(tester.widget<TextField>(email).autofillHints,
            [AutofillHints.email]);
        expect(tester.widget<TextField>(password).autofillHints,
            [AutofillHints.password]);
        await captureUiPreview(
            tester, 'login-$locale-${dark ? 'dark' : 'light'}');
        await tester.enterText(email, 'owner@example.test');
        await tester.enterText(password, 'Local-only-password');
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(l10n.emailLabel), findsWidgets);
        expect(find.bySemanticsLabel(RegExp(l10n.passwordLabel)), findsWidgets);
        expect(tester.widget<TextField>(password).obscureText, isTrue);
        await tester.tap(find.byKey(const Key('signInPasswordVisibility')));
        await tester.pump();
        expect(tester.widget<TextField>(password).obscureText, isFalse);
        expect(find.byTooltip(l10n.hidePasswordButton), findsOneWidget);
        await tester.enterText(email, 'invalid');
        await tester.enterText(password, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
            tester.widget<TextField>(email).decoration!.errorText, isNotNull);
        expect(tester.widget<TextField>(password).decoration!.errorText,
            isNotNull);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
