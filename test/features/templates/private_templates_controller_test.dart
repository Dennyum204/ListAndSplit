import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_templates_controller.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  test('blank templates with duplicate names remain independent', () async {
    final repository = FakePrivateTemplateRepository();
    var request = 0;
    final controller = PrivateTemplatesController(
      repository,
      hasAuthenticatedUser: true,
      requestIdGenerator: () => 'request-${request += 1}',
    );

    await controller.load();
    expect(await controller.createTemplate('Weekly'), isTrue);
    expect(await controller.createTemplate('Weekly'), isTrue);

    expect(repository.templates, hasLength(2));
    expect(
        repository.templates.map((entry) => entry.name), ['Weekly', 'Weekly']);
    expect(repository.itemsByTemplate.values.every((items) => items.isEmpty),
        isTrue);
    controller.dispose();
  });

  test('independent mounted controllers reconcile the same-account projection',
      () async {
    final repository = FakePrivateTemplateRepository();
    final first = PrivateTemplatesController(
      repository,
      hasAuthenticatedUser: true,
    );
    final second = PrivateTemplatesController(
      repository,
      hasAuthenticatedUser: true,
    );
    await Future.wait([first.load(), second.load()]);

    await first.createTemplate('Device A');
    expect(first.state.templates.asData?.value, hasLength(1));
    expect(second.state.templates.asData?.value, isEmpty);

    await second.reconcile();
    expect(second.state.templates.asData?.value.single.name, 'Device A');
    first.dispose();
    second.dispose();
  });

  test('preview uses authoritative destination count and blocks overflow',
      () async {
    final templates = FakePrivateTemplateRepository();
    final summary = await templates.createTemplate(
      'Full shop',
      requestId: 'template-request',
    );
    await templates.createItem(
      summary.id,
      'Coffee',
      requestId: 'item-one',
      expectedTemplateVersion: 1,
    );
    await templates.createItem(
      summary.id,
      'Milk',
      requestId: 'item-two',
      expectedTemplateVersion: 2,
    );
    final lists = FakeActiveListRepository();
    lists.activeLists = [_listSummary(itemCount: 199)];
    lists.itemsByList['list-1'] = List.generate(
      199,
      (index) => _listItem('list-item-$index', 'Item $index', index + 1),
    );
    final controller = PrivateTemplateDetailController(
      templates,
      lists,
      summary.id,
      invalidateTemplates: () {},
      invalidateLists: () {},
      invalidateListDetail: (_) {},
    );
    await controller.load();
    expect(await controller.prepareImport('list-1'), isTrue);

    expect(controller.state.destination?.remainingCapacity, 1);
    expect(
      await controller.importSelected(
        controller.state.detail.asData!.value.items.map((item) => item.id),
      ),
      isFalse,
    );
    expect(controller.state.message, PrivateTemplatesMessage.capacity);
    controller.dispose();
  });

  test('stale capacity rejection refreshes source and destination', () async {
    final templates = FakePrivateTemplateRepository();
    final summary = await templates.createTemplate(
      'Shop',
      requestId: 'template-request',
    );
    await templates.createItem(
      summary.id,
      'Coffee',
      requestId: 'item-one',
      expectedTemplateVersion: 1,
    );
    final lists = FakeActiveListRepository();
    lists.activeLists = [_listSummary(itemCount: 199)];
    lists.itemsByList['list-1'] = List.generate(
      199,
      (index) => _listItem('item-$index', 'Item $index', index + 1),
    );
    final controller = PrivateTemplateDetailController(
      templates,
      lists,
      summary.id,
      invalidateTemplates: () {},
      invalidateLists: () {},
      invalidateListDetail: (_) {},
    );
    await controller.load();
    await controller.prepareImport('list-1');
    templates.failure = const PrivateTemplateFailure(
      PrivateTemplateFailureCode.capacity,
    );

    final succeeded = await controller.importSelected(
      [controller.state.detail.asData!.value.items.single.id],
    );

    expect(succeeded, isFalse);
    expect(controller.state.message, PrivateTemplatesMessage.capacity);
    expect(controller.state.destination?.remainingCapacity, 1);
    controller.dispose();
  });
}

ActiveListSummary _listSummary({required int itemCount}) => ActiveListSummary(
      id: 'list-1',
      title: 'Destination',
      status: ActiveListStatus.active,
      version: 7,
      itemCount: itemCount,
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
