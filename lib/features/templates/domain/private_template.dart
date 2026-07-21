import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';

const shoppingListItemCapacity = activeListItemCapacity;
const privateTemplateItemCapacity = 200;
const privateTemplateCapacity = 100;
const templateCategoryCapacity = 25;

enum PrivateTemplateSort {
  recent('recent'),
  alphabetic('alpha'),
  newest('newest');

  const PrivateTemplateSort(this.wireValue);

  final String wireValue;
}

class TemplateCategory {
  const TemplateCategory({
    required this.id,
    required this.name,
    required this.version,
    required this.templateCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int version;
  final int templateCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PrivateTemplateSummary {
  const PrivateTemplateSummary({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.version,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? categoryId;
  final String? categoryName;
  final String name;
  final int version;
  final int itemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PrivateTemplateItem {
  const PrivateTemplateItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.position,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final ListQuantity quantity;
  final int position;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PrivateTemplateDetail {
  PrivateTemplateDetail({
    required this.summary,
    required this.remainingCapacity,
    required List<PrivateTemplateItem> items,
  }) : items = List.unmodifiable(items);

  final PrivateTemplateSummary summary;
  final int remainingCapacity;
  final List<PrivateTemplateItem> items;
}

class TemplateSelection {
  TemplateSelection({
    required Iterable<String> availableItemIds,
    required Iterable<String> selectedItemIds,
    required this.remainingCapacity,
  })  : availableItemIds = Set.unmodifiable(availableItemIds),
        selectedItemIds = Set.unmodifiable(selectedItemIds) {
    if (!this.availableItemIds.containsAll(this.selectedItemIds) ||
        remainingCapacity < 0) {
      throw const FormatException('invalid template selection');
    }
  }

  factory TemplateSelection.all(
    Iterable<String> itemIds, {
    int remainingCapacity = privateTemplateItemCapacity,
  }) {
    final ids = itemIds.toSet();
    return TemplateSelection(
      availableItemIds: ids,
      selectedItemIds: ids,
      remainingCapacity: remainingCapacity,
    );
  }

  final Set<String> availableItemIds;
  final Set<String> selectedItemIds;
  final int remainingCapacity;

  int get selectedCount => selectedItemIds.length;
  bool get canConfirm =>
      selectedCount > 0 &&
      selectedCount <= privateTemplateItemCapacity &&
      selectedCount <= remainingCapacity;

  TemplateSelection toggled(String itemId) {
    if (!availableItemIds.contains(itemId)) return this;
    final next = selectedItemIds.toSet();
    next.contains(itemId) ? next.remove(itemId) : next.add(itemId);
    return TemplateSelection(
      availableItemIds: availableItemIds,
      selectedItemIds: next,
      remainingCapacity: remainingCapacity,
    );
  }
}

String normalizedTemplateItemName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

Set<String> duplicateTemplateItemIds(
  Iterable<PrivateTemplateItem> templateItems,
  Iterable<String> destinationItemNames,
) {
  final normalizedDestination =
      destinationItemNames.map(normalizedTemplateItemName).toSet();
  return templateItems
      .where(
        (item) => normalizedDestination.contains(
          normalizedTemplateItemName(item.name),
        ),
      )
      .map((item) => item.id)
      .toSet();
}

class TemplateImportResult {
  const TemplateImportResult({
    required this.listVersion,
    required this.importedCount,
    required this.remainingCapacity,
  });

  final int listVersion;
  final int importedCount;
  final int remainingCapacity;
}

class TemplateListCreationResult {
  const TemplateListCreationResult({
    required this.listId,
    required this.title,
    required this.version,
    required this.itemCount,
  });

  final String listId;
  final String title;
  final int version;
  final int itemCount;
}
