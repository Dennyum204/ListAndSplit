import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';

enum PrivateTemplateFailureCode {
  invalid,
  unavailable,
  stale,
  retryConflict,
  archived,
  capacity,
  transport,
  generic,
}

class PrivateTemplateFailure implements Exception {
  const PrivateTemplateFailure(this.code);

  final PrivateTemplateFailureCode code;
}

abstract interface class PrivateTemplateRepository {
  Future<List<TemplateCategory>> listCategories();
  Future<List<PrivateTemplateSummary>> listTemplates({
    String? search,
    String? categoryId,
    bool uncategorizedOnly = false,
    PrivateTemplateSort sort = PrivateTemplateSort.recent,
  });
  Future<PrivateTemplateDetail> getTemplate(String templateId);

  Future<TemplateCategory> createCategory(
    String name, {
    required String requestId,
  });
  Future<TemplateCategory> renameCategory(
    String categoryId,
    String name, {
    required int expectedVersion,
  });
  Future<void> deleteCategory(
    String categoryId, {
    required int expectedVersion,
  });

  Future<PrivateTemplateSummary> createTemplate(
    String name, {
    String? categoryId,
    required String requestId,
  });
  Future<PrivateTemplateSummary> updateTemplate(
    String templateId,
    String name, {
    String? categoryId,
    required int expectedVersion,
  });
  Future<void> deleteTemplate(
    String templateId, {
    required int expectedVersion,
  });
  Future<PrivateTemplateItem> createItem(
    String templateId,
    String name, {
    ListQuantity quantity = ListQuantity.one,
    required String requestId,
    required int expectedTemplateVersion,
  });
  Future<PrivateTemplateItem> updateItem(
    String templateId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required int expectedTemplateVersion,
    required int expectedItemVersion,
  });
  Future<int> deleteItem(
    String templateId,
    String itemId, {
    required int expectedTemplateVersion,
    required int expectedItemVersion,
  });
  Future<int> reorderItems(
    String templateId,
    List<String> orderedItemIds, {
    required int expectedTemplateVersion,
  });

  Future<PrivateTemplateSummary> saveListAsTemplate(
    String listId,
    List<String> selectedItemIds,
    String name, {
    String? categoryId,
    required String requestId,
    required int expectedListVersion,
  });
  Future<TemplateListCreationResult> createListFromTemplate(
    String templateId,
    List<String> selectedItemIds,
    String title, {
    required String listRequestId,
    required List<String> itemRequestIds,
    required int expectedTemplateVersion,
  });
  Future<TemplateImportResult> importIntoList(
    String templateId,
    List<String> selectedItemIds,
    String listId, {
    required List<String> itemRequestIds,
    required int expectedTemplateVersion,
    required int expectedListVersion,
  });
}
