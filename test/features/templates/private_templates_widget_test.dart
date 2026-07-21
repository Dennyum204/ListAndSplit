import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/presentation/private_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/templates_screen.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
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
