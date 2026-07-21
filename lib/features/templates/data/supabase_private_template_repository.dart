import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PrivateTemplateRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabasePrivateTemplateRepository implements PrivateTemplateRepository {
  SupabasePrivateTemplateRepository(
    SupabaseClient client, {
    PrivateTemplateRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final PrivateTemplateRpc _rpc;

  @override
  Future<List<TemplateCategory>> listCategories() async {
    try {
      return _rows(await _rpc('list_template_categories'))
          .map(_category)
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<PrivateTemplateSummary>> listTemplates({
    String? search,
    String? categoryId,
    bool uncategorizedOnly = false,
    PrivateTemplateSort sort = PrivateTemplateSort.recent,
  }) async {
    try {
      return _rows(
        await _rpc(
          'list_private_templates',
          params: {
            'search_query': search,
            'category_filter': categoryId,
            'uncategorized_only': uncategorizedOnly,
            'sort_mode': sort.wireValue,
          },
        ),
      ).map(_summary).toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PrivateTemplateDetail> getTemplate(String templateId) async {
    try {
      final results = await Future.wait<Object?>([
        _rpc('get_private_template', params: {
          'target_template_id': templateId,
        }),
        _rpc('list_private_template_items', params: {
          'target_template_id': templateId,
        }),
      ]);
      final summaryRows = _rows(results[0]);
      if (summaryRows.isEmpty) {
        throw const PrivateTemplateFailure(
          PrivateTemplateFailureCode.unavailable,
        );
      }
      if (summaryRows.length != 1) {
        throw const FormatException('expected one template row');
      }
      final summaryRow = summaryRows.single;
      final items = _rows(results[1]).map(_item).toList(growable: false);
      final summary = _summary(summaryRow);
      if (summary.itemCount != items.length) {
        throw const FormatException('inconsistent template item count');
      }
      return PrivateTemplateDetail(
        summary: summary,
        remainingCapacity: _nonNegativeInt(summaryRow['remaining_capacity']),
        items: items,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TemplateCategory> createCategory(
    String name, {
    required String requestId,
  }) =>
      _categoryMutation('create_template_category', {
        'new_name': name,
        'creation_request_id': requestId,
      });

  @override
  Future<TemplateCategory> renameCategory(
    String categoryId,
    String name, {
    required int expectedVersion,
  }) =>
      _categoryMutation('rename_template_category', {
        'target_category_id': categoryId,
        'new_name': name,
        'expected_category_version': expectedVersion,
      });

  @override
  Future<void> deleteCategory(
    String categoryId, {
    required int expectedVersion,
  }) async {
    try {
      final deleted = await _rpc('delete_template_category', params: {
        'target_category_id': categoryId,
        'expected_category_version': expectedVersion,
      });
      if (deleted is! bool || !deleted) {
        throw const PrivateTemplateFailure(
          PrivateTemplateFailureCode.unavailable,
        );
      }
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PrivateTemplateSummary> createTemplate(
    String name, {
    String? categoryId,
    required String requestId,
  }) =>
      _templateMutation('create_private_template', {
        'new_name': name,
        'target_category_id': categoryId,
        'creation_request_id': requestId,
      });

  @override
  Future<PrivateTemplateSummary> updateTemplate(
    String templateId,
    String name, {
    String? categoryId,
    required int expectedVersion,
  }) =>
      _templateMutation('update_private_template', {
        'target_template_id': templateId,
        'new_name': name,
        'target_category_id': categoryId,
        'expected_template_version': expectedVersion,
      });

  @override
  Future<void> deleteTemplate(
    String templateId, {
    required int expectedVersion,
  }) async {
    try {
      final deleted = await _rpc('delete_private_template', params: {
        'target_template_id': templateId,
        'expected_template_version': expectedVersion,
      });
      if (deleted is! bool || !deleted) {
        throw const PrivateTemplateFailure(
          PrivateTemplateFailureCode.unavailable,
        );
      }
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PrivateTemplateItem> createItem(
    String templateId,
    String name, {
    ListQuantity quantity = ListQuantity.one,
    required String requestId,
    required int expectedTemplateVersion,
  }) async {
    try {
      return _item(
          _singleRow(await _rpc('create_private_template_item', params: {
        'target_template_id': templateId,
        'new_name': name,
        'creation_request_id': requestId,
        'expected_template_version': expectedTemplateVersion,
        'new_quantity_thousandths': quantity.thousandths,
      })));
    } catch (error) {
      throw _failure(error);
    }
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
    try {
      return _item(
          _singleRow(await _rpc('update_private_template_item', params: {
        'target_template_id': templateId,
        'target_item_id': itemId,
        'new_name': name,
        'new_quantity_thousandths': quantity.thousandths,
        'expected_template_version': expectedTemplateVersion,
        'expected_item_version': expectedItemVersion,
      })));
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> deleteItem(
    String templateId,
    String itemId, {
    required int expectedTemplateVersion,
    required int expectedItemVersion,
  }) async {
    try {
      return _positiveInt(await _rpc('delete_private_template_item', params: {
        'target_template_id': templateId,
        'target_item_id': itemId,
        'expected_template_version': expectedTemplateVersion,
        'expected_item_version': expectedItemVersion,
      }));
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> reorderItems(
    String templateId,
    List<String> orderedItemIds, {
    required int expectedTemplateVersion,
  }) async {
    try {
      return _positiveInt(await _rpc('reorder_private_template_items', params: {
        'target_template_id': templateId,
        'ordered_item_ids': orderedItemIds,
        'expected_template_version': expectedTemplateVersion,
      }));
    } catch (error) {
      throw _failure(error);
    }
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
    try {
      return _summary(
          _singleRow(await _rpc('save_active_list_as_template', params: {
        'source_list_id': listId,
        'selected_item_ids': selectedItemIds,
        'new_template_name': name,
        'target_category_id': categoryId,
        'creation_request_id': requestId,
        'expected_list_version': expectedListVersion,
      })));
    } catch (error) {
      throw _failure(error);
    }
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
    try {
      final row = _singleRow(
        await _rpc('create_active_list_from_template', params: {
          'source_template_id': templateId,
          'selected_item_ids': selectedItemIds,
          'new_list_title': title,
          'list_creation_request_id': listRequestId,
          'item_creation_request_ids': itemRequestIds,
          'expected_template_version': expectedTemplateVersion,
        }),
      );
      return TemplateListCreationResult(
        listId: _uuid(row['list_id']),
        title: _trimmedString(row['title']),
        version: _positiveInt(row['version']),
        itemCount: _positiveInt(row['item_count']),
      );
    } catch (error) {
      throw _failure(error);
    }
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
    try {
      final row =
          _singleRow(await _rpc('import_private_template_items', params: {
        'source_template_id': templateId,
        'selected_item_ids': selectedItemIds,
        'target_list_id': listId,
        'item_creation_request_ids': itemRequestIds,
        'expected_template_version': expectedTemplateVersion,
        'expected_list_version': expectedListVersion,
      }));
      return TemplateImportResult(
        listVersion: _positiveInt(row['list_version']),
        importedCount: _positiveInt(row['imported_count']),
        remainingCapacity: _nonNegativeInt(row['remaining_capacity']),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  Future<TemplateCategory> _categoryMutation(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    try {
      return _category(_singleRow(await _rpc(functionName, params: params)));
    } catch (error) {
      throw _failure(error);
    }
  }

  Future<PrivateTemplateSummary> _templateMutation(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    try {
      return _summary(_singleRow(await _rpc(functionName, params: params)));
    } catch (error) {
      throw _failure(error);
    }
  }

  static TemplateCategory _category(Map<String, dynamic> row) =>
      TemplateCategory(
        id: _uuid(row['category_id']),
        name: _string(row['name']),
        version: _positiveInt(row['version']),
        templateCount: row['template_count'] == null
            ? 0
            : _nonNegativeInt(row['template_count']),
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
      );

  static PrivateTemplateSummary _summary(Map<String, dynamic> row) =>
      PrivateTemplateSummary(
        id: _uuid(row['template_id']),
        categoryId:
            row['category_id'] == null ? null : _uuid(row['category_id']),
        categoryName:
            row['category_name'] == null ? null : _string(row['category_name']),
        name: _trimmedString(row['name']),
        version: _positiveInt(row['version']),
        itemCount:
            row['item_count'] == null ? 0 : _nonNegativeInt(row['item_count']),
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
      );

  static PrivateTemplateItem _item(Map<String, dynamic> row) =>
      PrivateTemplateItem(
        id: _uuid(row['item_id']),
        name: _boundedString(row['name'], 1, 120),
        quantity: ListQuantity.fromThousandths(
          _positiveInt(row['quantity_thousandths']),
        ),
        position: _positiveInt(row['position']),
        version: _positiveInt(row['version']),
        createdAt: _dateTime(row['created_at']),
        updatedAt: _dateTime(row['updated_at']),
      );

  static List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) throw const FormatException('expected rows');
    return response.map((row) {
      if (row is! Map) throw const FormatException('expected row');
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    final rows = _rows(response);
    if (rows.length != 1) throw const FormatException('expected one row');
    return rows.single;
  }

  static PrivateTemplateFailure _failure(Object error) {
    if (error is PrivateTemplateFailure) return error;
    if (error is PostgrestException) {
      return PrivateTemplateFailure(
        switch (error.code) {
          '22023' => PrivateTemplateFailureCode.invalid,
          'P0002' || '42501' => PrivateTemplateFailureCode.unavailable,
          '40001' => PrivateTemplateFailureCode.stale,
          '23505' => PrivateTemplateFailureCode.retryConflict,
          '55000' => PrivateTemplateFailureCode.archived,
          '54000' => PrivateTemplateFailureCode.capacity,
          _ => PrivateTemplateFailureCode.generic,
        },
      );
    }
    return const PrivateTemplateFailure(PrivateTemplateFailureCode.transport);
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _uuid(Object? value) {
    final result = _string(value);
    if (!_uuidPattern.hasMatch(result)) {
      throw const FormatException('invalid UUID');
    }
    return result;
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid string');
    }
    return value;
  }

  static String _trimmedString(Object? value) {
    final result = _string(value);
    if (result.trim() != result) throw const FormatException('invalid string');
    return result;
  }

  static String _boundedString(Object? value, int min, int max) {
    final result = _trimmedString(value);
    if (result.length < min || result.length > max) {
      throw const FormatException('invalid bounded string');
    }
    return result;
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('invalid positive integer');
    }
    return value;
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('invalid non-negative integer');
    }
    return value;
  }

  static DateTime _dateTime(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('invalid UTC timestamp');
    }
    return parsed;
  }
}
