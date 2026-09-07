import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/templates_screen.dart';
import 'package:list_and_split/features/templates/presentation/template_selection_dialog.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);
  for (final dark in [false, true]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
          'category dialog has a clean external label '
          '${dark ? 'dark' : 'light'} at ${textScale * 100} percent',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakePrivateTemplateRepository();
        await _pump(
          tester,
          repository: repository,
          lists: FakeActiveListRepository(),
          child: const TemplatesScreen(),
          dark: dark,
          textScale: textScale,
        );
        await tester.tap(
          find.byKey(const Key('manageTemplateCategoriesButton')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Create category'));
        await tester.pumpAndSettle();

        final field = find.byKey(const Key('categoryNameField'));
        final label = find.descendant(
          of: find.byType(AppDialogField),
          matching: find.text('Category name'),
        );
        expect(label, findsOneWidget);
        expect(tester.widget<TextField>(field).decoration?.labelText, isNull);
        expect(tester.widget<TextField>(field).decoration?.label, isNull);
        expect(tester.widget<Text>(label).style?.backgroundColor, isNull);
        expect(tester.getBottomLeft(label).dy,
            lessThan(tester.getTopLeft(field).dy));

        final cancel = find.byKey(const Key('cancelCategoryNameButton'));
        final confirm = find.byKey(const Key('confirmCategoryNameButton'));
        expect(tester.widget(cancel), isA<OutlinedButton>());
        expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);

        await tester.enterText(field, 'Weekend');
        await tester.pumpAndSettle();
        expect(label, findsOneWidget);
        expect(tester.getBottomLeft(label).dy,
            lessThan(tester.getTopLeft(field).dy));
        await captureUiPreview(tester,
            'category-clean-label-${dark ? 'dark' : 'light'}-${(textScale * 100).round()}');
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(repository.categories, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final dark in [false, true]) {
    testWidgets('reference catalog at normal text ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakePrivateTemplateRepository();
      final category =
          await repository.createCategory('Recipes', requestId: 'category');
      for (final name in [
        'Pizza with olives',
        'Beef with rice',
        'Cheesecake'
      ]) {
        await repository.createTemplate(name,
            requestId: name, categoryId: category.id);
      }
      await _pump(tester,
          repository: repository,
          lists: FakeActiveListRepository(),
          child: const TemplatesScreen(),
          dark: dark);
      expect(find.byIcon(Icons.description_outlined), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await captureUiPreview(
          tester, 'templates-catalog-en-${dark ? 'dark' : 'light'}-100');
    });
  }

  for (final locale in [const Locale('en'), const Locale('pt')]) {
    for (final dark in [false, true]) {
      testWidgets(
          'reference selection keeps capacity guards at 200 percent '
          '${locale.languageCode} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakePrivateTemplateRepository();
        final template =
            await repository.createTemplate('Weekend', requestId: 'template');
        for (final name in ['Sunscreen', 'Towels']) {
          await repository.createItem(template.id, name,
              requestId: name, expectedTemplateVersion: 1);
        }
        await _pump(tester,
            repository: repository,
            lists: FakeActiveListRepository(),
            locale: locale,
            dark: dark,
            textScale: 2, child: Builder(builder: (context) {
          final strings = AppLocalizations.of(context);
          return Scaffold(
            body: FilledButton(
              key: const Key('openSelection'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => TemplateSelectionDialog(
                  title: strings.templatesImportTitle,
                  items: repository.itemsByTemplate[template.id]!,
                  remainingCapacity: 1,
                  confirmLabel: strings.templatesConfirmImportButton,
                ),
              ),
              child: Text(strings.templatesImportListButton),
            ),
          );
        }));
        await tester.tap(find.byKey(const Key('openSelection')));
        await tester.pumpAndSettle();
        final confirm = find.byKey(const Key('confirmTemplateSelectionButton'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(tester.takeException(), isNull);
        await captureUiPreview(tester,
            'template-selection-${locale.languageCode}-${dark ? 'dark' : 'light'}-200');
        await tester.ensureVisible(find.byType(CheckboxListTile).first);
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        final strings = AppLocalizations.of(tester.element(confirm));
        await tester
            .ensureVisible(find.text(strings.templatesClearSelectionButton));
        await tester.tap(find.text(strings.templatesClearSelectionButton));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'reference catalog and category dialog remain usable at 200 percent '
          '${locale.languageCode} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakePrivateTemplateRepository();
        final category =
            await repository.createCategory('Recipes', requestId: 'category');
        await repository.createTemplate('Weekend preparation',
            requestId: 'template', categoryId: category.id);
        await _pump(tester,
            repository: repository,
            lists: FakeActiveListRepository(),
            child: const TemplatesScreen(),
            locale: locale,
            dark: dark,
            textScale: 2);

        expect(find.text('Weekend preparation'), findsOneWidget);
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureUiPreview(tester,
            'templates-catalog-${locale.languageCode}-${dark ? 'dark' : 'light'}-200');
        await tester
            .tap(find.byKey(const Key('manageTemplateCategoriesButton')));
        await tester.pumpAndSettle();
        final categoryTile = find.widgetWithText(ListTile, 'Recipes');
        expect(categoryTile, findsOneWidget);
        await tester.tap(categoryTile);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('categoryNameField')), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(tester.takeException(), isNull);
        await captureUiPreview(tester,
            'templates-category-${locale.languageCode}-${dark ? 'dark' : 'light'}-200');
        await tester.tap(find.byKey(const Key('cancelCategoryNameButton')));
        await tester.pumpAndSettle();
        expect(repository.categories.single.name, 'Recipes');
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'blank reference detail keeps guarded item management at 200 percent '
          '${locale.languageCode} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakePrivateTemplateRepository();
        final template = await repository.createTemplate('Beach Trip',
            requestId: 'template');
        await _pump(tester,
            repository: repository,
            lists: FakeActiveListRepository(),
            child: PrivateTemplateDetailScreen(templateId: template.id),
            locale: locale,
            dark: dark,
            textScale: 2);
        final addButton = find.byKey(const Key('addTemplateItemButton'));
        expect(tester.getSize(addButton).height, greaterThanOrEqualTo(48));
        await tester.tap(addButton);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const Key('templateItemNameField')), 'Sunscreen');
        final strings = AppLocalizations.of(
            tester.element(find.byKey(const Key('templateItemNameField'))));
        await tester.tap(find.widgetWithText(FilledButton, strings.saveButton));
        await tester.pumpAndSettle();
        expect(find.text('Sunscreen'), findsOneWidget);
        expect(
            repository.itemsByTemplate[template.id]!.single.name, 'Sunscreen');
        expect(tester.takeException(), isNull);
        await captureUiPreview(tester,
            'template-detail-${locale.languageCode}-${dark ? 'dark' : 'light'}-200');
      });
    }
  }

  testWidgets('owned private template exposes the Send action', (tester) async {
    final repository = FakePrivateTemplateRepository();
    final template = await repository.createTemplate(
      'Packing',
      requestId: 'template',
    );
    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: PrivateTemplateDetailScreen(templateId: template.id),
    );

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Send to a friend'), findsOneWidget);
    final sendAction = find.ancestor(
      of: find.text('Send to a friend'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(sendAction).onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'templates screen exposes empty category, search and sort controls',
      (tester) async {
    final repository = FakePrivateTemplateRepository();
    await repository.createCategory('Empty category', requestId: 'category');

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    expect(find.text('No private templates yet'), findsOneWidget);
    expect(find.text('Empty category'), findsOneWidget);
    expect(find.byKey(const Key('templateSearchField')), findsOneWidget);
    expect(find.byKey(const Key('templateSortField')), findsOneWidget);
    expect(find.byKey(const Key('createTemplateButton')), findsOneWidget);
  });

  testWidgets('create category closes without disposing a mounted controller',
      (tester) async {
    final repository = FakePrivateTemplateRepository();

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'Groceries',
    );
    await tester.tap(find.byKey(const Key('confirmCategoryNameButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.categories.single.name, 'Groceries');
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(find.text('Template categories'), findsOneWidget);
    expect(find.text('Groceries'), findsWidgets);
  });

  testWidgets('create category cancellation unmounts cleanly', (tester) async {
    final repository = FakePrivateTemplateRepository();

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'Cancelled category',
    );
    await tester.tap(find.byKey(const Key('cancelCategoryNameButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.categories, isEmpty);
    expect(repository.mutationCalls, 0);
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(find.text('Template categories'), findsOneWidget);
  });

  testWidgets('normalized duplicate rejection closes without framework errors',
      (tester) async {
    final repository = _DuplicateRejectingCategoryRepository();
    await repository.createCategory('Groceries', requestId: 'existing');

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      '  GROCERIES  ',
    );
    await tester.tap(find.byKey(const Key('confirmCategoryNameButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.submittedName, 'GROCERIES');
    expect(repository.categories.single.name, 'Groceries');
    expect(repository.mutationCalls, 2);
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(
      find.text('Check the name, quantity, and selected items.'),
      findsOneWidget,
    );
  });

  testWidgets('rapid category confirmation submits and closes exactly once',
      (tester) async {
    final repository = _DelayedCategoryRepository();

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'One submission',
    );
    final confirm = find.byKey(const Key('confirmCategoryNameButton'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();

    expect(repository.createCategoryCalls, 1);
    repository.release.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.createCategoryCalls, 1);
    expect(repository.categories.single.name, 'One submission');
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(find.text('Template categories'), findsOneWidget);
  });

  testWidgets('rename category success and cancellation unmount cleanly',
      (tester) async {
    final repository = FakePrivateTemplateRepository();
    await repository.createCategory('Original', requestId: 'existing');

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rename category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'Renamed',
    );
    await tester.tap(find.byKey(const Key('confirmCategoryNameButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.categories.single.name, 'Renamed');
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(find.text('Template categories'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'Cancelled rename',
    );
    await tester.tap(find.byKey(const Key('cancelCategoryNameButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.categories.single.name, 'Renamed');
    expect(repository.mutationCalls, 2);
    expect(find.byKey(const Key('categoryNameField')), findsNothing);
    expect(find.text('Template categories'), findsOneWidget);
  });

  testWidgets('category dialog route disposal releases its controller safely',
      (tester) async {
    final repository = FakePrivateTemplateRepository();

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      child: const TemplatesScreen(),
    );

    await tester.tap(
      find.byKey(const Key('manageTemplateCategoriesButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categoryNameField')),
      'Abandoned category',
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.categories, isEmpty);
    expect(repository.mutationCalls, 0);
  });

  testWidgets(
      'owner publication is explicit, disclosed and visible beyond color',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakePrivateTemplateRepository();
    final template = await repository.createTemplate(
      'Weekend kit',
      requestId: 'template',
    );

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      dark: true,
      textScale: 2,
      child: PrivateTemplateDetailScreen(templateId: template.id),
    );

    expect(find.text('Private'), findsOneWidget);
    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish template'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Any signed-in, nonblocked person who reaches your profile',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Saved copies become independent'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('confirmTemplatePublicationButton')),
    );
    await tester.pumpAndSettle();

    expect(repository.templates.single.isPublic, isTrue);
    expect(repository.templates.single.publishedAt, isNotNull);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Template published.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit template'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('publicTemplateEditNotice')), findsOneWidget);
    expect(
      find.textContaining('Saved changes remain visible'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make private'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Existing saved copies'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('confirmTemplatePublicationButton')),
    );
    await tester.pumpAndSettle();

    expect(repository.templates.single.isPublic, isFalse);
    expect(repository.templates.single.publishedAt, isNull);
    expect(find.text('Private'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'moderated owner source remains editable while publication is unavailable',
      (tester) async {
    final repository = FakePrivateTemplateRepository();
    repository.templates.add(
      PrivateTemplateSummary(
        id: 'moderated-template',
        categoryId: null,
        categoryName: null,
        name: 'Moderated source',
        version: 8,
        itemCount: 0,
        createdAt: DateTime.utc(2026, 7, 26, 7),
        updatedAt: DateTime.utc(2026, 7, 26, 8),
        isModerated: true,
      ),
    );
    repository.itemsByTemplate['moderated-template'] = [];

    await _pump(
      tester,
      repository: repository,
      lists: FakeActiveListRepository(),
      dark: true,
      textScale: 2,
      child: const PrivateTemplateDetailScreen(
        templateId: 'moderated-template',
      ),
    );

    expect(find.text('Removed by moderation'), findsOneWidget);
    expect(find.byIcon(Icons.gavel_rounded), findsOneWidget);
    expect(find.byKey(const Key('addTemplateItemButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Edit template'), findsOneWidget);
    expect(find.text('Delete template'), findsOneWidget);
    expect(find.text('Publish template'), findsOneWidget);

    await tester.tap(find.text('Publish template'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('confirmTemplatePublicationButton')),
      findsNothing,
    );
    expect(repository.mutationCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection preview disables zero and overflow confirmations',
      (tester) async {
    final repository = FakePrivateTemplateRepository();
    final template = await repository.createTemplate(
      'Weekly shop',
      requestId: 'template',
    );
    await repository.createItem(
      template.id,
      'Coffee',
      requestId: 'coffee',
      expectedTemplateVersion: 1,
    );
    await repository.createItem(
      template.id,
      'Milk',
      requestId: 'milk',
      expectedTemplateVersion: 2,
    );
    final lists = FakeActiveListRepository();
    lists.activeLists = [_listSummary()];
    lists.itemsByList['list-1'] = List.generate(
      199,
      (index) => _listItem(
        'item-$index',
        index == 0 ? '  COFFEE ' : 'Existing $index',
        index + 1,
      ),
    );

    await _pump(
      tester,
      repository: repository,
      lists: lists,
      child: PrivateTemplateDetailScreen(templateId: template.id),
    );

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new list'));
    await tester.pumpAndSettle();
    var confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirmTemplateSelectionButton')),
    );
    expect(confirm.onPressed, isNotNull);

    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirmTemplateSelectionButton')),
    );
    expect(confirm.onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import into existing list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();

    expect(find.text('1 item space remaining'), findsOneWidget);
    expect(find.textContaining('Possible duplicate'), findsOneWidget);
    expect(find.textContaining('exceeds the authoritative'), findsOneWidget);
    confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirmTemplateSelectionButton')),
    );
    expect(confirm.onPressed, isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakePrivateTemplateRepository repository,
  required FakeActiveListRepository lists,
  required Widget child,
  bool dark = false,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        privateTemplateRepositoryProvider.overrideWithValue(repository),
        activeListRepositoryProvider.overrideWithValue(lists),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        locale: locale,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, materialChild) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: uiPreviewBoundary(materialChild!),
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ActiveListSummary _listSummary() => ActiveListSummary(
      id: 'list-1',
      title: 'Destination',
      status: ActiveListStatus.active,
      version: 7,
      itemCount: 199,
      completedItemCount: 0,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
      archivedAt: null,
    );

ActiveListItem _listItem(String id, String name, int position) =>
    ActiveListItem(
      id: id,
      name: name,
      quantity: ListQuantity.one,
      unit: null,
      position: position,
      version: 1,
      completedAt: null,
      completedBy: null,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    );

class _DuplicateRejectingCategoryRepository
    extends FakePrivateTemplateRepository {
  String? submittedName;

  @override
  Future<TemplateCategory> createCategory(
    String name, {
    required String requestId,
  }) {
    submittedName = name;
    final normalized =
        name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final duplicate = categories.any(
      (category) =>
          category.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase() ==
          normalized,
    );
    if (duplicate) {
      mutationCalls += 1;
      throw const PrivateTemplateFailure(PrivateTemplateFailureCode.invalid);
    }
    return super.createCategory(name, requestId: requestId);
  }
}

class _DelayedCategoryRepository extends FakePrivateTemplateRepository {
  final Completer<void> release = Completer<void>();
  int createCategoryCalls = 0;

  @override
  Future<TemplateCategory> createCategory(
    String name, {
    required String requestId,
  }) async {
    createCategoryCalls += 1;
    await release.future;
    return super.createCategory(name, requestId: requestId);
  }
}
