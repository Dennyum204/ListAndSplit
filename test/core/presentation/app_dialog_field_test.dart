import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../support/ui_preview_capture.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('pt')]) {
    for (final dark in [false, true]) {
      testWidgets(
          'plain dropdown caption keeps validation and semantics ${locale.languageCode} dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final form = GlobalKey<FormState>();
        try {
          await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Form(
              key: form,
              child: Builder(builder: (context) {
                final strings = AppLocalizations.of(context);
                return AppDialogField(
                    label: strings.templatesSortLabel,
                    child: DropdownButtonFormField<String>(
                      isDense: false,
                      key: const Key('captionDropdown'),
                      isExpanded: true,
                      decoration: const InputDecoration(),
                      validator: (value) => value == null
                          ? strings.listInvalidInputMessage
                          : null,
                      onChanged: (_) {},
                      items: [
                        DropdownMenuItem(
                            value: 'recent',
                            child: Text(strings.templatesSortRecent))
                      ],
                    ));
              }),
            ))),
          ));
          await tester.pumpAndSettle();
          final wrapper = find.byType(AppDialogField);
          final label = tester.widget<AppDialogField>(wrapper).label;
          final field = find.byKey(const Key('captionDropdown'));
          final caption =
              find.descendant(of: wrapper, matching: find.text(label));
          expect(tester.getRect(caption).bottom,
              lessThan(tester.getRect(field).top));
          expect(tester.widget<Text>(caption).style!.backgroundColor, isNull);
          expect(form.currentState!.validate(), isFalse);
          await tester.pumpAndSettle();
          final strings = AppLocalizations.of(tester.element(wrapper));
          expect(find.text(strings.listInvalidInputMessage), findsOneWidget);
          await tester.tap(find.byType(DropdownButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(strings.templatesSortRecent).last);
          await tester.pumpAndSettle();
          expect(form.currentState!.validate(), isTrue);
          await tester.pumpAndSettle();
          expect(find.text(strings.listInvalidInputMessage), findsNothing);
          expect(tester.getSemantics(find.byType(DropdownButton<String>)).label,
              contains(label));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  for (final language in ['en', 'pt']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '$language ${mode.name} $scale dialog labels remain outside filled inputs',
            (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await prepareUiPreviewFonts();
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: uiPreviewBoundary(child!),
              ),
              home: Builder(builder: (context) {
                final strings = AppLocalizations.of(context);
                return Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          titlePadding: EdgeInsets.zero,
                          title: AppDialogTitle(
                              strings.templatesCreateCategoryButton),
                          content: SingleChildScrollView(
                            child: AppDialogField(
                              label: strings.templatesCategoryNameLabel,
                              child: TextFormField(
                                key: const Key('dialogField'),
                                style: AppPalette.inputTextStyle(context),
                                initialValue: 'Weekend',
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: (value) => value!.isEmpty
                                    ? strings.templatesCategoryNameLabel
                                    : null,
                                decoration: const InputDecoration(),
                              ),
                            ),
                          ),
                          actions: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(strings.cancelButton),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                );
              }),
            ));
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            final wrapper = find.byType(AppDialogField);
            final label = tester.widget<AppDialogField>(wrapper).label;
            final caption = find.descendant(
                of: find
                    .descendant(
                        of: wrapper, matching: find.byType(ExcludeSemantics))
                    .first,
                matching: find.text(label));
            final field = find.byKey(const Key('dialogField'));
            for (final text in ['Weekend', '', 'Trips']) {
              await tester.enterText(field, text);
              await tester.pumpAndSettle();
              expect(tester.getRect(caption).bottom,
                  lessThan(tester.getRect(field).top));
              final style = tester.widget<Text>(caption).style!;
              expect(style.backgroundColor, isNull);
              expect(style.background, isNull);
              final decorator = tester.widget<InputDecorator>(find.descendant(
                  of: field, matching: find.byType(InputDecorator)));
              expect(decorator.decoration.label, isNull);
              expect(decorator.decoration.labelText, isNull);
              expect(decorator.decoration.fillColor, AppPalette.inputCream);
              final semanticsNode = tester.getSemantics(find.byType(TextField));
              expect(semanticsNode.label, contains(label));
              expect(semanticsNode.value, text);
              expect(tester.takeException(), isNull);
            }
            await captureUiPreview(
                tester, 'dialog-$language-${mode.name}-${scale.toInt()}x');
            final cancel = find.byType(OutlinedButton);
            expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
