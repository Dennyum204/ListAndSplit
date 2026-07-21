import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';

void main() {
  group('TemplateSelection', () {
    test('requires one selected item and permits the exact remaining capacity',
        () {
      final ids = List.generate(200, (index) => 'item-$index');
      var selection = TemplateSelection.all(ids, remainingCapacity: 200);

      expect(selection.selectedCount, 200);
      expect(selection.canConfirm, isTrue);

      for (final id in ids) {
        selection = selection.toggled(id);
      }
      expect(selection.selectedCount, 0);
      expect(selection.canConfirm, isFalse);
    });

    test('disables confirmation when selection exceeds remaining capacity', () {
      final selection = TemplateSelection.all(
        const ['one', 'two'],
        remainingCapacity: 1,
      );

      expect(selection.selectedCount, 2);
      expect(selection.canConfirm, isFalse);
      expect(selection.toggled('two').canConfirm, isTrue);
    });

    test('legacy over-capacity sources remain selectable without truncation',
        () {
      final ids = List.generate(201, (index) => 'item-$index');
      final selection = TemplateSelection.all(ids, remainingCapacity: 200);

      expect(selection.availableItemIds, hasLength(201));
      expect(selection.selectedItemIds, hasLength(201));
      expect(selection.canConfirm, isFalse);
      expect(selection.toggled('item-200').canConfirm, isTrue);
    });
  });

  test('possible duplicate names ignore case and repeated whitespace', () {
    final duplicates = duplicateTemplateItemIds(
      [
        _item('one', '  Green   Apples '),
        _item('two', 'Milk'),
        _item('three', 'Milk'),
      ],
      const ['green apples', ' bread ', 'MILK'],
    );

    expect(duplicates, {'one', 'two', 'three'});
  });
}

PrivateTemplateItem _item(String id, String name) => PrivateTemplateItem(
      id: id,
      name: name,
      quantity: ListQuantity.one,
      position: 1,
      version: 1,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    );
