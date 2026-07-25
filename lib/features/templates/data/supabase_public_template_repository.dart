import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PublicTemplateRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabasePublicTemplateRepository implements PublicTemplateRepository {
  SupabasePublicTemplateRepository(
    SupabaseClient client, {
    PublicTemplateRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final PublicTemplateRpc _rpc;

  @override
  Future<PublicTemplatePage> listProfileTemplates(
    String profileId, {
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  }) async {
    try {
      final response = await _rpc(
        'list_public_profile_templates',
        params: {
          'target_profile_id': profileId,
          'requested_page_size': pageSize,
          'cursor_published_at': cursor?.publishedAt.toIso8601String(),
          'cursor_template_id': cursor?.templateId,
        },
      );
      if (response == null) {
        throw const PublicTemplateFailure(
          PublicTemplateFailureCode.unavailable,
        );
      }
      final document = _object(response);
      _expectExactKeys(document, _pageKeys);
      final profile = _profile(_requiredObject(document, 'profile'));
      if (profile.id != profileId) {
        throw const FormatException('unexpected public profile');
      }
      final templates =
          _objects(document, 'templates').map(_summary).toList(growable: false);
      if (templates.length > pageSize) {
        throw const FormatException('oversized public template page');
      }
      _validatePageOrder(templates, cursor);
      final nextCursor = document['next_cursor'] == null
          ? null
          : _cursor(_requiredObject(document, 'next_cursor'));
      if (nextCursor != null &&
          (templates.isEmpty ||
              nextCursor.templateId != templates.last.id ||
              nextCursor.publishedAt != templates.last.publishedAt)) {
        throw const FormatException('invalid public template cursor');
      }
      return PublicTemplatePage(
        profile: profile,
        templates: templates,
        nextCursor: nextCursor,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PublicTemplateDetail> getTemplate(
    String profileId,
    String templateId,
  ) async {
    try {
      final response = await _rpc(
        'get_public_template',
        params: {
          'target_profile_id': profileId,
          'target_template_id': templateId,
        },
      );
      if (response == null) {
        throw const PublicTemplateFailure(
          PublicTemplateFailureCode.unavailable,
        );
      }
      final document = _object(response);
      _expectExactKeys(document, _detailKeys);
      final profile = _profile(_requiredObject(document, 'profile'));
      final template = _requiredObject(document, 'template');
      _expectExactKeys(template, _detailTemplateKeys);
      final items =
          _objects(template, 'items').map(_item).toList(growable: false);
      _validateItemOrder(items);
      final summary = _summary(template);
      if (profile.id != profileId || summary.id != templateId) {
        throw const FormatException('unexpected public template');
      }
      return PublicTemplateDetail(
        profile: profile,
        summary: summary,
        items: items,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PublicTemplateCopyResult> copyTemplate(
    String templateId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    try {
      final row = _singleRow(
        await _rpc(
          'copy_public_template',
          params: {
            'source_template_id': templateId,
            'expected_source_version': expectedVersion,
            'request_id': requestId,
          },
        ),
      );
      _expectExactKeys(row, _copyKeys);
      if (row['category_id'] != null ||
          row['category_name'] != null ||
          row['is_public'] != false ||
          row['published_at'] != null) {
        throw const FormatException('invalid copied template state');
      }
      return PublicTemplateCopyResult(
        template: PrivateTemplateSummary(
          id: _uuid(row['template_id']),
          categoryId: null,
          categoryName: null,
          name: _boundedName(row['name']),
          version: _positiveInt(row['version']),
          itemCount: _boundedCount(row['item_count'], 0, 200),
          createdAt: _dateTime(row['created_at']),
          updatedAt: _dateTime(row['updated_at']),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  static const _pageKeys = {'profile', 'templates', 'next_cursor'};
  static const _profileKeys = {'profile_id', 'username', 'display_name'};
  static const _summaryKeys = {
    'template_id',
    'name',
    'version',
    'item_count',
    'published_at',
  };
  static const _detailKeys = {'profile', 'template'};
  static const _detailTemplateKeys = {..._summaryKeys, 'items'};
  static const _cursorKeys = {'published_at', 'template_id'};
  static const _itemKeys = {
    'name',
    'quantity_thousandths',
    'position',
  };
  static const _copyKeys = {
    'template_id',
    'category_id',
    'category_name',
    'name',
    'version',
    'item_count',
    'is_public',
    'published_at',
    'created_at',
    'updated_at',
  };

  static PublicTemplateProfile _profile(Map<String, dynamic> row) {
    _expectExactKeys(row, _profileKeys);
    final username = _trimmedString(row['username']);
    final displayName = _trimmedString(row['display_name']);
    if (!_usernamePattern.hasMatch(username) || displayName.runes.length > 50) {
      throw const FormatException('invalid public profile');
    }
    return PublicTemplateProfile(
      id: _uuid(row['profile_id']),
      username: username,
      displayName: displayName,
    );
  }

  static PublicTemplateSummary _summary(Map<String, dynamic> row) {
    final allowedKeys =
        row.containsKey('items') ? _detailTemplateKeys : _summaryKeys;
    _expectExactKeys(row, allowedKeys);
    return PublicTemplateSummary(
      id: _uuid(row['template_id']),
      name: _boundedName(row['name']),
      version: _positiveInt(row['version']),
      itemCount: _boundedCount(row['item_count'], 0, 200),
      publishedAt: _dateTime(row['published_at']),
    );
  }

  static PublicTemplateCursor _cursor(Map<String, dynamic> row) {
    _expectExactKeys(row, _cursorKeys);
    return PublicTemplateCursor(
      publishedAt: _dateTime(row['published_at']),
      templateId: _uuid(row['template_id']),
    );
  }

  static PublicTemplateItem _item(Map<String, dynamic> row) {
    _expectExactKeys(row, _itemKeys);
    return PublicTemplateItem(
      name: _boundedName(row['name']),
      quantity: ListQuantity.fromThousandths(
        _positiveInt(row['quantity_thousandths']),
      ),
      position: _positiveInt(row['position']),
    );
  }

  static void _validatePageOrder(
    List<PublicTemplateSummary> templates,
    PublicTemplateCursor? cursor,
  ) {
    final ids = <String>{};
    PublicTemplateSummary? previous;
    for (final template in templates) {
      if (!ids.add(template.id)) {
        throw const FormatException('duplicate public template');
      }
      final prior = previous;
      if (prior != null &&
          (template.publishedAt.isAfter(prior.publishedAt) ||
              (template.publishedAt == prior.publishedAt &&
                  template.id.compareTo(prior.id) >= 0))) {
        throw const FormatException('invalid public template order');
      }
      if (cursor != null &&
          (template.publishedAt.isAfter(cursor.publishedAt) ||
              (template.publishedAt == cursor.publishedAt &&
                  template.id.compareTo(cursor.templateId) >= 0))) {
        throw const FormatException('invalid cursor page');
      }
      previous = template;
    }
  }

  static void _validateItemOrder(List<PublicTemplateItem> items) {
    var previousPosition = 0;
    for (final item in items) {
      if (item.position <= previousPosition) {
        throw const FormatException('invalid public item order');
      }
      previousPosition = item.position;
    }
  }

  static PublicTemplateFailure _failure(Object error) {
    if (error is PublicTemplateFailure) return error;
    if (error is PostgrestException) {
      return PublicTemplateFailure(
        switch (error.code) {
          '22023' => PublicTemplateFailureCode.invalid,
          'P0002' || '42501' => PublicTemplateFailureCode.unavailable,
          '40001' => PublicTemplateFailureCode.stale,
          '23505' => PublicTemplateFailureCode.retryConflict,
          '54000' => PublicTemplateFailureCode.capacity,
          _ => PublicTemplateFailureCode.generic,
        },
      );
    }
    if (error is FormatException) {
      return const PublicTemplateFailure(PublicTemplateFailureCode.generic);
    }
    return const PublicTemplateFailure(PublicTemplateFailureCode.transport);
  }

  static Map<String, dynamic> _object(Object? response) {
    if (response is! Map) throw const FormatException('expected object');
    return Map<String, dynamic>.from(response);
  }

  static Map<String, dynamic> _requiredObject(
    Map<String, dynamic> object,
    String key,
  ) =>
      _object(object[key]);

  static List<Map<String, dynamic>> _objects(
    Map<String, dynamic> object,
    String key,
  ) {
    final values = object[key];
    if (values is! List) throw const FormatException('expected object list');
    return values.map(_object).toList(growable: false);
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    if (response is! List || response.length != 1) {
      throw const FormatException('expected one row');
    }
    return _object(response.single);
  }

  static void _expectExactKeys(
    Map<String, dynamic> object,
    Set<String> expected,
  ) {
    if (object.length != expected.length ||
        !object.keys.toSet().containsAll(expected)) {
      throw const FormatException('unexpected response shape');
    }
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

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

  static String _boundedName(Object? value) {
    final result = _trimmedString(value);
    if (result.runes.isEmpty || result.runes.length > 120) {
      throw const FormatException('invalid name');
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

  static int _boundedCount(Object? value, int minimum, int maximum) {
    final count = _nonNegativeInt(value);
    if (count < minimum || count > maximum) {
      throw const FormatException('invalid count');
    }
    return count;
  }

  static DateTime _dateTime(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('invalid UTC timestamp');
    }
    return parsed;
  }
}
