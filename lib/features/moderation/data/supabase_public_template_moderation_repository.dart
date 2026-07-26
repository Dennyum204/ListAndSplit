import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/moderation/domain/public_template_moderation_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PublicTemplateModerationRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabasePublicTemplateModerationRepository
    implements PublicTemplateModerationRepository {
  SupabasePublicTemplateModerationRepository(
    SupabaseClient client, {
    PublicTemplateModerationRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final PublicTemplateModerationRpc _rpc;

  @override
  Future<bool> isModerator() async {
    try {
      final response = await _rpc('is_public_template_moderator');
      if (response is! bool) throw const FormatException('expected bool');
      return response;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ModerationQueuePage> listQueue(
    ModerationQueueFilter filter, {
    int pageSize = 20,
    ModerationQueueCursor? cursor,
  }) async {
    try {
      final document = _object(
        await _rpc(
          'list_public_template_moderation_queue',
          params: {
            'queue_filter': filter.wireValue,
            'requested_page_size': pageSize,
            'cursor_at': cursor?.at.toIso8601String(),
            'cursor_group_id': cursor?.groupId,
          },
        ),
      );
      _expectExactKeys(document, _queuePageKeys);
      if (document['filter'] != filter.wireValue) {
        throw const FormatException('unexpected moderation filter');
      }
      final cases =
          _objects(document, 'cases').map(_queueCase).toList(growable: false);
      if (cases.length > pageSize) {
        throw const FormatException('oversized moderation page');
      }
      final nextCursor = document['next_cursor'] == null
          ? null
          : _cursor(_object(document['next_cursor']));
      return ModerationQueuePage(
        filter: filter,
        cases: cases,
        nextCursor: nextCursor,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PublicTemplateModerationCase> getCase(String groupId) async {
    try {
      final document = _object(
        await _rpc(
          'get_public_template_moderation_case',
          params: {'target_group_id': groupId},
        ),
      );
      _expectExactKeys(document, _caseKeys);
      final group = _object(document['group']);
      _expectExactKeys(group, _caseGroupKeys);
      final snapshot = _snapshot(_object(document['reported_snapshot']));
      final reports =
          _objects(document, 'reports').map(_report).toList(growable: false);
      final current = document['current_template'] == null
          ? null
          : _currentTemplate(_object(document['current_template']));
      final restriction = document['restriction'] == null
          ? null
          : _restriction(_object(document['restriction']));
      final parsedGroupId = _uuid(group['group_id']);
      if (parsedGroupId != groupId || reports.isEmpty) {
        throw const FormatException('invalid moderation case');
      }
      return PublicTemplateModerationCase(
        summary: ModerationQueueCase(
          groupId: parsedGroupId,
          templateId: _uuid(group['template_id']),
          templateName: snapshot.name,
          reportedRevision: _positiveInt(group['reported_revision']),
          reportCount: reports.length,
          status: _status(group['status']),
          version: _positiveInt(group['version']),
          firstReportedAt: _dateTime(group['first_reported_at']),
          closedAt: _nullableDateTime(group['closed_at']),
          sourceChanged: _bool(group['source_changed']),
          sourceUnpublished: _bool(group['source_unpublished']),
          sourceDeleted: _bool(group['source_deleted']),
          sourceModerated: _bool(group['source_moderated']),
          isRestricted: restriction?.active ?? false,
          restrictionVersion:
              restriction?.active == true ? restriction!.version : null,
        ),
        reportedSnapshot: snapshot,
        reports: reports,
        currentTemplate: current,
        restriction: restriction,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ModerationActionResult> dismiss(
    String groupId, {
    required int expectedGroupVersion,
    required String privateNote,
    required String requestId,
  }) =>
      _moderateGroup(
        groupId,
        action: PublicTemplateModerationAction.dismiss,
        expectedGroupVersion: expectedGroupVersion,
        privateNote: privateNote,
        requestId: requestId,
      );

  @override
  Future<ModerationActionResult> takeDown(
    String groupId, {
    required int expectedGroupVersion,
    required int expectedTemplateVersion,
    required PublicTemplateReportReason ownerReason,
    required String privateNote,
    required String requestId,
  }) =>
      _moderateGroup(
        groupId,
        action: PublicTemplateModerationAction.takeDown,
        expectedGroupVersion: expectedGroupVersion,
        expectedTemplateVersion: expectedTemplateVersion,
        ownerReason: ownerReason,
        privateNote: privateNote,
        requestId: requestId,
      );

  @override
  Future<ModerationActionResult> restore(
    String templateId, {
    required int expectedRestrictionVersion,
    required int expectedTemplateVersion,
    required String privateNote,
    required String requestId,
  }) async {
    try {
      return _actionResult(
        _object(
          await _rpc(
            'restore_public_template_moderation',
            params: {
              'target_template_id': templateId,
              'expected_restriction_version': expectedRestrictionVersion,
              'expected_template_version': expectedTemplateVersion,
              'private_note': privateNote,
              'request_id': requestId,
            },
          ),
        ),
        PublicTemplateModerationAction.restore,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  Future<ModerationActionResult> _moderateGroup(
    String groupId, {
    required PublicTemplateModerationAction action,
    required int expectedGroupVersion,
    int? expectedTemplateVersion,
    PublicTemplateReportReason? ownerReason,
    required String privateNote,
    required String requestId,
  }) async {
    try {
      return _actionResult(
        _object(
          await _rpc(
            'moderate_public_template_report_group',
            params: {
              'target_group_id': groupId,
              'moderation_action': action.wireValue,
              'expected_group_version': expectedGroupVersion,
              'expected_template_version': expectedTemplateVersion,
              'owner_reason_code': ownerReason?.wireValue,
              'private_note': privateNote,
              'request_id': requestId,
            },
          ),
        ),
        action,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  static ModerationQueueCase _queueCase(Map<String, dynamic> row) {
    _expectExactKeys(row, _queueCaseKeys);
    final isRestricted = _bool(row['is_restricted']);
    final restrictionVersion = _nullablePositiveInt(row['restriction_version']);
    if (isRestricted != (restrictionVersion != null)) {
      throw const FormatException('invalid restriction projection');
    }
    return ModerationQueueCase(
      groupId: _uuid(row['group_id']),
      templateId: _uuid(row['template_id']),
      templateName: _boundedText(row['template_name'], 1, 120),
      reportedRevision: _positiveInt(row['reported_revision']),
      reportCount: _positiveInt(row['report_count']),
      status: _status(row['status']),
      version: _positiveInt(row['version']),
      firstReportedAt: _dateTime(row['first_reported_at']),
      closedAt: _nullableDateTime(row['closed_at']),
      sourceChanged: _bool(row['source_changed']),
      sourceUnpublished: _bool(row['source_unpublished']),
      sourceDeleted: _bool(row['source_deleted']),
      sourceModerated: _bool(row['source_moderated']),
      isRestricted: isRestricted,
      restrictionVersion: restrictionVersion,
    );
  }

  static ModerationQueueCursor _cursor(Map<String, dynamic> row) {
    _expectExactKeys(row, _cursorKeys);
    return ModerationQueueCursor(
      at: _dateTime(row['at']),
      groupId: _uuid(row['group_id']),
    );
  }

  static ModerationTemplateSnapshot _snapshot(Map<String, dynamic> row) {
    _expectExactKeys(row, _snapshotKeys);
    return ModerationTemplateSnapshot(
      name: _boundedText(row['name'], 1, 120),
      items: _objects(row, 'items')
          .indexed
          .map(
            (entry) => _snapshotItem(entry.$2, entry.$1 + 1),
          )
          .toList(growable: false),
    );
  }

  static ModerationSnapshotItem _snapshotItem(
    Map<String, dynamic> row,
    int position,
  ) {
    _expectExactKeys(row, _snapshotItemKeys);
    return ModerationSnapshotItem(
      name: _boundedText(row['name'], 1, 120),
      quantity: ListQuantity.fromThousandths(
        _positiveInt(row['quantity_thousandths']),
      ),
      position: position,
    );
  }

  static ModerationReport _report(Map<String, dynamic> row) {
    _expectExactKeys(row, _reportKeys);
    return ModerationReport(
      id: _uuid(row['report_id']),
      reason: _reason(row['reason_code']),
      explanation: _nullableBoundedText(row['explanation'], 500),
      createdAt: _dateTime(row['created_at']),
      reporter:
          row['reporter'] == null ? null : _reporter(_object(row['reporter'])),
    );
  }

  static ModerationReporterProfile _reporter(Map<String, dynamic> row) {
    _expectExactKeys(row, _reporterKeys);
    return ModerationReporterProfile(
      id: _uuid(row['profile_id']),
      username: _boundedText(row['username'], 3, 24),
      displayName: _boundedText(row['display_name'], 1, 50),
    );
  }

  static ModerationCurrentTemplate _currentTemplate(
    Map<String, dynamic> row,
  ) {
    _expectExactKeys(row, _currentKeys);
    return ModerationCurrentTemplate(
      id: _uuid(row['template_id']),
      name: _boundedText(row['name'], 1, 120),
      version: _positiveInt(row['version']),
      isPublic: _bool(row['is_public']),
      items: _objects(row, 'items')
          .indexed
          .map((entry) => _snapshotItem(entry.$2, entry.$1 + 1))
          .toList(growable: false),
    );
  }

  static ModerationRestriction _restriction(Map<String, dynamic> row) {
    _expectExactKeys(row, _restrictionKeys);
    return ModerationRestriction(
      active: _bool(row['active']),
      version: _positiveInt(row['version']),
      reason: _reason(row['reason_code']),
      imposedAt: _dateTime(row['imposed_at']),
      restoredAt: _nullableDateTime(row['restored_at']),
      sourceDeletedAt: _nullableDateTime(row['source_deleted_at']),
    );
  }

  static ModerationActionResult _actionResult(
    Map<String, dynamic> row,
    PublicTemplateModerationAction expectedAction,
  ) {
    _expectExactKeys(row, _actionKeys);
    final action = _action(row['action']);
    if (action != expectedAction) {
      throw const FormatException('unexpected moderation action');
    }
    return ModerationActionResult(
      eventId: _uuid(row['event_id']),
      action: action,
      groupId: row['group_id'] == null ? null : _uuid(row['group_id']),
      groupVersion: _nullablePositiveInt(row['group_version']),
      restrictionVersion: _nullablePositiveInt(row['restriction_version']),
      templateVersion: _nullablePositiveInt(row['template_version']),
      createdAt: _dateTime(row['created_at']),
    );
  }

  static PublicTemplateModerationFailure _failure(Object error) {
    if (error is PublicTemplateModerationFailure) return error;
    if (error is PostgrestException) {
      return PublicTemplateModerationFailure(
        switch (error.code) {
          '22023' => PublicTemplateModerationFailureCode.invalid,
          'P0002' => PublicTemplateModerationFailureCode.unavailable,
          '40001' => PublicTemplateModerationFailureCode.stale,
          '23505' => PublicTemplateModerationFailureCode.retryConflict,
          '42501' => PublicTemplateModerationFailureCode.revoked,
          _ => PublicTemplateModerationFailureCode.generic,
        },
      );
    }
    if (error is FormatException) {
      return const PublicTemplateModerationFailure(
        PublicTemplateModerationFailureCode.generic,
      );
    }
    return const PublicTemplateModerationFailure(
      PublicTemplateModerationFailureCode.transport,
    );
  }

  static const _queuePageKeys = {'filter', 'cases', 'next_cursor'};
  static const _queueCaseKeys = {
    'group_id',
    'template_id',
    'template_name',
    'reported_revision',
    'report_count',
    'status',
    'version',
    'first_reported_at',
    'closed_at',
    'source_changed',
    'source_unpublished',
    'source_deleted',
    'source_moderated',
    'is_restricted',
    'restriction_version',
  };
  static const _cursorKeys = {'at', 'group_id'};
  static const _caseKeys = {
    'group',
    'reported_snapshot',
    'reports',
    'current_template',
    'restriction',
  };
  static const _caseGroupKeys = {
    'group_id',
    'template_id',
    'reported_revision',
    'status',
    'version',
    'first_reported_at',
    'closed_at',
    'source_changed',
    'source_unpublished',
    'source_deleted',
    'source_moderated',
  };
  static const _snapshotKeys = {'name', 'items'};
  static const _snapshotItemKeys = {'name', 'quantity_thousandths'};
  static const _reportKeys = {
    'report_id',
    'reason_code',
    'explanation',
    'created_at',
    'reporter',
  };
  static const _reporterKeys = {
    'profile_id',
    'username',
    'display_name',
  };
  static const _currentKeys = {
    'template_id',
    'name',
    'version',
    'is_public',
    'items',
  };
  static const _restrictionKeys = {
    'active',
    'version',
    'reason_code',
    'imposed_at',
    'restored_at',
    'source_deleted_at',
  };
  static const _actionKeys = {
    'event_id',
    'action',
    'group_id',
    'group_version',
    'restriction_version',
    'template_version',
    'created_at',
  };

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const FormatException('expected object');
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _objects(
    Map<String, dynamic> object,
    String key,
  ) {
    final value = object[key];
    if (value is! List) throw const FormatException('expected list');
    return value.map(_object).toList(growable: false);
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

  static String _uuid(Object? value) {
    final result = _boundedText(value, 36, 36);
    if (!_uuidPattern.hasMatch(result)) {
      throw const FormatException('invalid UUID');
    }
    return result;
  }

  static String _boundedText(Object? value, int minimum, int maximum) {
    if (value is! String ||
        value.trim() != value ||
        value.runes.length < minimum ||
        value.runes.length > maximum) {
      throw const FormatException('invalid text');
    }
    return value;
  }

  static String? _nullableBoundedText(Object? value, int maximum) =>
      value == null ? null : _boundedText(value, 1, maximum);

  static int _positiveInt(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('invalid positive integer');
    }
    return value;
  }

  static int? _nullablePositiveInt(Object? value) =>
      value == null ? null : _positiveInt(value);

  static bool _bool(Object? value) {
    if (value is! bool) throw const FormatException('invalid bool');
    return value;
  }

  static DateTime _dateTime(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('invalid UTC timestamp');
    }
    return parsed;
  }

  static DateTime? _nullableDateTime(Object? value) =>
      value == null ? null : _dateTime(value);

  static String _status(Object? value) {
    final status = _boundedText(value, 4, 15);
    if (!const {
      'open',
      'dismissed',
      'taken_down',
      'content_deleted',
    }.contains(status)) {
      throw const FormatException('invalid status');
    }
    return status;
  }

  static PublicTemplateReportReason _reason(Object? value) {
    final wireValue = _boundedText(value, 3, 40);
    return PublicTemplateReportReason.values.firstWhere(
      (reason) => reason.wireValue == wireValue,
      orElse: () => throw const FormatException('invalid reason'),
    );
  }

  static PublicTemplateModerationAction _action(Object? value) {
    final wireValue = _boundedText(value, 7, 9);
    return PublicTemplateModerationAction.values.firstWhere(
      (action) => action.wireValue == wireValue,
      orElse: () => throw const FormatException('invalid action'),
    );
  }
}
