import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';

class FakePrivateTemplateRepository implements PrivateTemplateRepository {
  final List<TemplateCategory> categories = [];
  final List<PrivateTemplateSummary> templates = [];
  final Map<String, List<PrivateTemplateItem>> itemsByTemplate = {};
  Object? failure;
  int mutationCalls = 0;

  DateTime get _now => DateTime.utc(2026, 7, 21, 12, mutationCalls);

  @override
  Future<List<TemplateCategory>> listCategories() async {
    if (failure != null) throw failure!;
    return List.unmodifiable(categories);
  }

  @override
  Future<List<PrivateTemplateSummary>> listTemplates({
    String? search,
    String? categoryId,
    bool uncategorizedOnly = false,
    PrivateTemplateSort sort = PrivateTemplateSort.recent,
  }) async {
    if (failure != null) throw failure!;
    final query = search?.trim().toLowerCase();
    final result = templates.where((template) {
      if (categoryId != null && template.categoryId != categoryId) return false;
      if (uncategorizedOnly && template.categoryId != null) return false;
      if (query == null || query.isEmpty) return true;
      return template.name.toLowerCase().contains(query) ||
          (itemsByTemplate[template.id] ?? const [])
              .any((item) => item.name.toLowerCase().contains(query));
    }).toList();
    switch (sort) {
      case PrivateTemplateSort.recent:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case PrivateTemplateSort.alphabetic:
        result.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case PrivateTemplateSort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  @override
  Future<PrivateTemplateDetail> getTemplate(String templateId) async {
    if (failure != null) throw failure!;
    final summary = templates.firstWhere((entry) => entry.id == templateId);
    final items = itemsByTemplate[templateId] ?? const [];
    return PrivateTemplateDetail(
      summary: _withItemCount(summary, items.length),
      remainingCapacity: items.length >= privateTemplateItemCapacity
          ? 0
          : privateTemplateItemCapacity - items.length,
      items: items,
    );
  }

  @override
  Future<TemplateCategory> createCategory(
    String name, {
    required String requestId,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final category = TemplateCategory(
      id: 'category-$mutationCalls',
      name: name,
      version: 1,
      templateCount: 0,
      createdAt: _now,
      updatedAt: _now,
    );
    categories.add(category);
    return category;
  }

  @override
  Future<TemplateCategory> renameCategory(
    String categoryId,
    String name, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final index = categories.indexWhere((entry) => entry.id == categoryId);
    final current = categories[index];
    final result = TemplateCategory(
      id: current.id,
      name: name,
      version: current.version + 1,
      templateCount: current.templateCount,
      createdAt: current.createdAt,
      updatedAt: _now,
    );
    categories[index] = result;
    return result;
  }

  @override
  Future<void> deleteCategory(
    String categoryId, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    categories.removeWhere((entry) => entry.id == categoryId);
    for (var index = 0; index < templates.length; index += 1) {
      final template = templates[index];
      if (template.categoryId == categoryId) {
        templates[index] = _summary(
          id: template.id,
          name: template.name,
          version: template.version + 1,
          categoryId: null,
          itemCount: template.itemCount,
          createdAt: template.createdAt,
        );
      }
    }
  }

  @override
  Future<PrivateTemplateSummary> createTemplate(
    String name, {
    String? categoryId,
    required String requestId,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final result = _summary(
      id: 'template-$mutationCalls',
      name: name,
      categoryId: categoryId,
    );
    templates.add(result);
    itemsByTemplate[result.id] = [];
    return result;
  }

  @override
  Future<PrivateTemplateSummary> updateTemplate(
    String templateId,
    String name, {
    String? categoryId,
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final index = templates.indexWhere((entry) => entry.id == templateId);
    final current = templates[index];
    final result = _summary(
      id: current.id,
      name: name,
      categoryId: categoryId,
      version: current.version + 1,
      itemCount: current.itemCount,
      createdAt: current.createdAt,
    );
    templates[index] = result;
    return result;
  }

  @override
  Future<void> deleteTemplate(
    String templateId, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    templates.removeWhere((entry) => entry.id == templateId);
    itemsByTemplate.remove(templateId);
  }

  @override
  Future<PrivateTemplateItem> createItem(
    String templateId,
    String name, {
    ListQuantity quantity = ListQuantity.one,
    required String requestId,
    required int expectedTemplateVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final items = itemsByTemplate[templateId]!;
    final result = PrivateTemplateItem(
      id: 'template-item-$mutationCalls',
      name: name,
      quantity: quantity,
      position: items.length + 1,
      version: 1,
      createdAt: _now,
      updatedAt: _now,
    );
    items.add(result);
    _advanceTemplate(templateId, items.length);
    return result;
  }

  @override
  Future<PrivateTemplateItem> updateItem(
    String templateId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required int expectedTemplateVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final items = itemsByTemplate[templateId]!;
    final index = items.indexWhere((entry) => entry.id == itemId);
    final current = items[index];
    final result = PrivateTemplateItem(
      id: current.id,
      name: name,
      quantity: quantity,
      position: current.position,
      version: current.version + 1,
      createdAt: current.createdAt,
      updatedAt: _now,
    );
    items[index] = result;
    _advanceTemplate(templateId, items.length);
    return result;
  }

  @override
  Future<int> deleteItem(
    String templateId,
    String itemId, {
    required int expectedTemplateVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final items = itemsByTemplate[templateId]!;
    items.removeWhere((entry) => entry.id == itemId);
    _advanceTemplate(templateId, items.length);
    return expectedTemplateVersion + 1;
  }

  @override
  Future<int> reorderItems(
    String templateId,
    List<String> orderedItemIds, {
    required int expectedTemplateVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    final byId = {
      for (final item in itemsByTemplate[templateId]!) item.id: item
    };
    itemsByTemplate[templateId] = [
      for (var index = 0; index < orderedItemIds.length; index += 1)
        PrivateTemplateItem(
          id: byId[orderedItemIds[index]]!.id,
          name: byId[orderedItemIds[index]]!.name,
          quantity: byId[orderedItemIds[index]]!.quantity,
          position: index + 1,
          version: byId[orderedItemIds[index]]!.version,
          createdAt: byId[orderedItemIds[index]]!.createdAt,
          updatedAt: byId[orderedItemIds[index]]!.updatedAt,
        ),
    ];
    _advanceTemplate(templateId, orderedItemIds.length);
    return expectedTemplateVersion + 1;
  }

  @override
  Future<PrivateTemplateSummary> saveListAsTemplate(
    String listId,
    List<String> selectedItemIds,
    String name, {
    String? categoryId,
    required String requestId,
    required int expectedListVersion,
  }) async {
    final result = await createTemplate(
      name,
      categoryId: categoryId,
      requestId: requestId,
    );
    final withItems = _withItemCount(result, selectedItemIds.length);
    templates[templates.indexWhere((entry) => entry.id == result.id)] =
        withItems;
    return withItems;
  }

  @override
  Future<TemplateListCreationResult> createListFromTemplate(
    String templateId,
    List<String> selectedItemIds,
    String title, {
    required String listRequestId,
    required List<String> itemRequestIds,
    required int expectedTemplateVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    return TemplateListCreationResult(
      listId: 'list-from-template-$mutationCalls',
      title: title,
      version: 1,
      itemCount: selectedItemIds.length,
    );
  }

  @override
  Future<TemplateImportResult> importIntoList(
    String templateId,
    List<String> selectedItemIds,
    String listId, {
    required List<String> itemRequestIds,
    required int expectedTemplateVersion,
    required int expectedListVersion,
  }) async {
    mutationCalls += 1;
    if (failure != null) throw failure!;
    return TemplateImportResult(
      listVersion: expectedListVersion + 1,
      importedCount: selectedItemIds.length,
      remainingCapacity: 200 - selectedItemIds.length,
    );
  }

  PrivateTemplateSummary _summary({
    required String id,
    required String name,
    String? categoryId,
    int version = 1,
    int itemCount = 0,
    DateTime? createdAt,
  }) {
    String? categoryName;
    if (categoryId != null) {
      for (final category in categories) {
        if (category.id == categoryId) {
          categoryName = category.name;
          break;
        }
      }
    }
    return PrivateTemplateSummary(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      name: name,
      version: version,
      itemCount: itemCount,
      createdAt: createdAt ?? _now,
      updatedAt: _now,
    );
  }

  PrivateTemplateSummary _withItemCount(
    PrivateTemplateSummary current,
    int count,
  ) =>
      PrivateTemplateSummary(
        id: current.id,
        categoryId: current.categoryId,
        categoryName: current.categoryName,
        name: current.name,
        version: current.version,
        itemCount: count,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      );

  void _advanceTemplate(String templateId, int itemCount) {
    final index = templates.indexWhere((entry) => entry.id == templateId);
    final current = templates[index];
    templates[index] = PrivateTemplateSummary(
      id: current.id,
      categoryId: current.categoryId,
      categoryName: current.categoryName,
      name: current.name,
      version: current.version + 1,
      itemCount: itemCount,
      createdAt: current.createdAt,
      updatedAt: _now,
    );
  }
}
