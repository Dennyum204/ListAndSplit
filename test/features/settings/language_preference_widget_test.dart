import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/settings/domain/language_preference.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_selector.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import '../../helpers/fake_language_preference_repository.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);
  for (final locale in ['en', 'pt']) {
    for (final dark in [false, true]) {
      testWidgets(
          'language dropdown captions and selection fit 200% $locale dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await _pump(
              tester,
              FakeLanguagePreferenceRepository()
                ..preference = LanguagePreference.values.byName(locale),
              dark: dark,
              scale: 2);
          final field = find.byKey(const Key('languagePreference'));
          final caption =
              find.ancestor(of: field, matching: find.byType(AppDialogField));
          expect(caption, findsOneWidget);
          expect(
              tester
                  .widget<DropdownButtonFormField<LanguagePreference>>(field)
                  .decoration
                  .labelText,
              isNull);
          expect(tester.getSize(field).height, greaterThanOrEqualTo(48));
          final selectedText =
              find.text(locale == 'en' ? 'English' : 'Português');
          final paragraph = tester.renderObject<RenderParagraph>(selectedText);
          final naturalText = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
          )..layout(maxWidth: paragraph.size.width);
          try {
            expect(paragraph.size.height,
                greaterThanOrEqualTo(naturalText.height));
          } finally {
            naturalText.dispose();
          }
          await captureUiPreview(
              tester, 'language-$locale-${dark ? 'dark' : 'light'}-large');
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester
              .tap(find.text(locale == 'en' ? 'Português' : 'English').last);
          await tester.pumpAndSettle();
          expect(_locale(tester), locale == 'en' ? 'pt' : 'en');
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
      'System follows device changes and unsupported locales fall back to English',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('pt', 'PT')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _pump(tester, FakeLanguagePreferenceRepository());
    expect(_locale(tester), 'pt');
    tester.platformDispatcher.localesTestValue = [const Locale('de')];
    await tester.pumpAndSettle();
    expect(_locale(tester), 'en');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(LanguagePreferenceSelector)));
    await container
        .read(languagePreferenceControllerProvider.notifier)
        .select(LanguagePreference.pt);
    await tester.pumpAndSettle();
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    await tester.pumpAndSettle();
    expect(_locale(tester), 'pt');
    await container
        .read(languagePreferenceControllerProvider.notifier)
        .select(LanguagePreference.system);
    await tester.pumpAndSettle();
    expect(_locale(tester), 'en');
  });

  testWidgets('failed language write restores saved selection and allows retry',
      (tester) async {
    final repository = FakeLanguagePreferenceRepository()..failWrite = true;
    await _pump(tester, repository);
    final field = find.byKey(const Key('languagePreference'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't save your language"), findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<LanguagePreference>>(field)
            .initialValue,
        LanguagePreference.system);
    repository.failWrite = false;
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português').last);
    await tester.pumpAndSettle();
    expect(_locale(tester), 'pt');
    expect(repository.preference, LanguagePreference.pt);
  });
}

String _locale(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(LanguagePreferenceSelector)))
        .localeName;

Future<void> _pump(
    WidgetTester tester, FakeLanguagePreferenceRepository repository,
    {bool dark = false, double scale = 1}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      languagePreferenceRepositoryProvider.overrideWithValue(repository)
    ],
    child: Consumer(
        builder: (context, ref, _) => MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              locale: ref.watch(languagePreferenceControllerProvider).locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: uiPreviewBoundary(child!)),
              home: const Scaffold(
                  body: SingleChildScrollView(
                      child: LanguagePreferenceSelector())),
            )),
  ));
  await tester.pumpAndSettle();
}
