import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/settings/domain/theme_preference.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_controller.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_selector.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_theme_preference_repository.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('pt')]) {
    for (final preference in [ThemePreference.light, ThemePreference.dark]) {
      testWidgets(
          'localized theme choices fit 200-percent narrow ${locale.languageCode} ${preference.name}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await _pump(
              tester, FakeThemePreferenceRepository()..preference = preference,
              locale: locale, textScale: 2);
          expect(
              find.text(
                  locale.languageCode == 'en' ? 'Appearance' : 'Aparência'),
              findsOneWidget);
          for (final choice in ThemePreference.values) {
            final chip = find.byKey(Key('themePreference-${choice.name}'));
            await tester.ensureVisible(chip);
            await tester.pumpAndSettle();
            expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
            expect(
                tester.widget<ChoiceChip>(chip).selected, choice == preference);
            expect(tester.getSemantics(chip).label, isNotEmpty);
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
      'changes theme immediately and system follows platform brightness',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final repository = FakeThemePreferenceRepository();
    await _pump(tester, repository);
    expect(_brightness(tester), Brightness.light);
    await _select(tester, ThemePreference.dark);
    expect(_brightness(tester), Brightness.dark);
    await _select(tester, ThemePreference.light);
    expect(_brightness(tester), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.light);
    await _select(tester, ThemePreference.system);
    expect(_brightness(tester), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.light);
    expect(repository.writes, [
      ThemePreference.dark,
      ThemePreference.light,
      ThemePreference.system,
    ]);
  });

  testWidgets(
      'failed save shows one recoverable error and no dialog or snackbar',
      (tester) async {
    final repository = FakeThemePreferenceRepository()..failWrite = true;
    await _pump(tester, repository);
    await _select(tester, ThemePreference.dark);
    expect(find.textContaining("We couldn't save your theme"), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('themePreference-system')))
            .selected,
        isTrue);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    repository.failWrite = false;
    await _select(tester, ThemePreference.dark);
    expect(find.textContaining("We couldn't save your theme"), findsNothing);
    expect(_brightness(tester), Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'repeated taps are guarded and widget disposal during save is safe',
      (tester) async {
    final repository = FakeThemePreferenceRepository()
      ..writeGate = Completer<void>();
    await _pump(tester, repository);
    final chip = find.byKey(const Key('themePreference-dark'));
    await tester.tap(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(repository.writes, [ThemePreference.dark]);
    expect(tester.widget<ChoiceChip>(chip).onSelected, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repository.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(ThemePreferenceSelector))).brightness;

Future<void> _select(WidgetTester tester, ThemePreference preference) async {
  await tester.tap(find.byKey(Key('themePreference-${preference.name}')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
    WidgetTester tester, FakeThemePreferenceRepository repository,
    {Locale locale = const Locale('en'), double textScale = 1}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      themePreferenceRepositoryProvider.overrideWithValue(repository)
    ],
    child: Consumer(builder: (context, ref, child) {
      return MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ref.watch(themePreferenceControllerProvider).themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: SingleChildScrollView(child: ThemePreferenceSelector()),
          ),
        ),
      );
    }),
  ));
  await tester.pumpAndSettle();
}
