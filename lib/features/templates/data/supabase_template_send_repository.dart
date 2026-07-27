import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/template_send.dart';
import 'package:list_and_split/features/templates/domain/template_send_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef TemplateSendRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseTemplateSendRepository implements TemplateSendRepository {
  SupabaseTemplateSendRepository(
    SupabaseClient client, {
    TemplateSendRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final TemplateSendRpc _rpc;

  @override
  Future<List<TemplateSendProfile>> listEligibleRecipients(
    String templateId, {
    int pageSize = 20,
    TemplateSendRecipientCursor? cursor,
  }) async {
    try {
      final profiles = _rows(
        await _rpc(
          'list_eligible_template_send_recipients',
          params: {
            'target_template_id': templateId,
            'page_size': pageSize,
            'after_username': cursor?.username,
            'after_profile_id': cursor?.profileId,
          },
        ),
      ).map(_eligibleProfile).toList(growable: false);
      if (profiles.length > pageSize) {
        throw const FormatException('oversized recipient page');
      }
      _validateRecipientOrder(profiles, cursor);
      return profiles;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TemplateSendMutationResult> sendTemplate(
    String templateId,
    String recipientProfileId, {
    required int expectedTemplateVersion,
    required String requestId,
  }) async {
    try {
      final row = _singleRow(
        await _rpc(
          'send_template_to_friend',
          params: {
            'source_template_id': templateId,
            'recipient_profile_id': recipientProfileId,
            'expected_template_version': expectedTemplateVersion,
            'request_id': requestId,
          },
        ),
      );
      _expectExactKeys(row, _sendResultKeys);
      final result = _mutation(
        row,
        snapshotName: _snapshotName(row['snapshot_name']),
        itemCount: _boundedCount(row['snapshot_item_count'], 0, 200),
        createdAt: _dateTime(row['created_at']),
      );
      if (result.state == TemplateSendState.accepted) {
        throw const FormatException('invalid send result state');
      }
      return result;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ReceivedTemplateSendSummary>> listReceived({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    try {
      final summaries = _rows(
        await _rpc(
          'list_received_template_sends',
          params: {
            'state_filter': filter.wireValue,
            'page_size': pageSize,
            'before_state_changed_at': cursor?.stateChangedAt.toIso8601String(),
            'before_template_send_id': cursor?.templateSendId,
          },
        ),
      ).map(_receivedSummary).toList(growable: false);
      _validateSummaryPage(
        summaries.map(
          (summary) => (
            id: summary.id,
            state: summary.state,
            changedAt: summary.stateChangedAt,
          ),
        ),
        filter,
        pageSize,
        cursor,
      );
      return summaries;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<SentTemplateSendSummary>> listSent({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  }) async {
    try {
      final summaries = _rows(
        await _rpc(
          'list_sent_template_sends',
          params: {
            'state_filter': filter.wireValue,
            'page_size': pageSize,
            'before_state_changed_at': cursor?.stateChangedAt.toIso8601String(),
            'before_template_send_id': cursor?.templateSendId,
          },
        ),
      ).map(_sentSummary).toList(growable: false);
      _validateSummaryPage(
        summaries.map(
          (summary) => (
            id: summary.id,
            state: summary.state,
            changedAt: summary.stateChangedAt,
          ),
        ),
        filter,
        pageSize,
        cursor,
      );
      return summaries;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ReceivedTemplateSendDetail> getReceived(
    String templateSendId,
  ) async {
    try {
      final document = _object(
        await _rpc(
          'get_received_template_send',
          params: {'target_template_send_id': templateSendId},
        ),
      );
      _expectExactKeys(document, _detailKeys);
      final sender = _profile(_requiredObject(document, 'sender'));
      final items =
          _objects(document, 'items').map(_item).toList(growable: false);
      _validateItems(items);
      final summary = ReceivedTemplateSendSummary(
        id: _uuid(document['template_send_id']),
        sender: sender,
        snapshotName: _snapshotName(document['snapshot_name']),
        itemCount: _boundedCount(document['snapshot_item_count'], 0, 200),
        state: TemplateSendState.parse(_string(document['state'])),
        version: _positiveInt(document['version']),
        createdAt: _dateTime(document['created_at']),
        stateChangedAt: _dateTime(document['state_changed_at']),
      );
      if (summary.id != templateSendId) {
        throw const FormatException('unexpected template send');
      }
      final acceptedTemplateId = document['accepted_template_id'] == null
          ? null
          : _uuid(document['accepted_template_id']);
      if (acceptedTemplateId != null &&
          summary.state != TemplateSendState.accepted) {
        throw const FormatException('invalid accepted template identity');
      }
      return ReceivedTemplateSendDetail(
        summary: summary,
        acceptedTemplateId: acceptedTemplateId,
        items: items,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TemplateSendMutationResult> accept(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) async {
    try {
      final row = _singleRow(
        await _rpc(
          'accept_template_send',
          params: {
            'target_template_send_id': templateSendId,
            'expected_template_send_version': expectedVersion,
            'request_id': requestId,
          },
        ),
      );
      _expectExactKeys(row, _acceptResultKeys);
      final result = _mutation(
        row,
        acceptedTemplateId: _nullableUuid(row['accepted_template_id']),
      );
      if (result.id != templateSendId ||
          result.state != TemplateSendState.accepted ||
          result.acceptedTemplateId == null) {
        throw const FormatException('invalid acceptance result');
      }
      return result;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TemplateSendMutationResult> decline(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) =>
      _terminalMutation(
        functionName: 'decline_template_send',
        desiredState: TemplateSendState.declined,
        templateSendId: templateSendId,
        expectedVersion: expectedVersion,
        requestId: requestId,
      );

  @override
  Future<TemplateSendMutationResult> revoke(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  }) =>
      _terminalMutation(
        functionName: 'revoke_template_send',
        desiredState: TemplateSendState.revoked,
        templateSendId: templateSendId,
        expectedVersion: expectedVersion,
        requestId: requestId,
      );

  Future<TemplateSendMutationResult> _terminalMutation({
    required String functionName,
    required TemplateSendState desiredState,
    required String templateSendId,
    required int expectedVersion,
    required String requestId,
  }) async {
    try {
      final row = _singleRow(
        await _rpc(
          functionName,
          params: {
            'target_template_send_id': templateSendId,
            'expected_template_send_version': expectedVersion,
            'request_id': requestId,
          },
        ),
      );
      _expectExactKeys(row, _terminalResultKeys);
      final result = _mutation(row);
      if (result.id != templateSendId || result.state != desiredState) {
        throw const FormatException('invalid terminal result');
      }
      return result;
    } catch (error) {
      throw _failure(error);
    }
  }

  static const _eligibleProfileKeys = {
    'profile_id',
    'username',
    'display_name',
  };
  static const _receivedKeys = {
    'template_send_id',
    'sender_profile_id',
    'sender_username',
    'sender_display_name',
    'snapshot_name',
    'snapshot_item_count',
    'state',
    'version',
    'created_at',
    'state_changed_at',
  };
  static const _sentKeys = {
    'template_send_id',
    'recipient_profile_id',
    'recipient_username',
    'recipient_display_name',
    'snapshot_name',
    'snapshot_item_count',
    'state',
    'version',
    'created_at',
    'state_changed_at',
  };
  static const _sendResultKeys = {
    'template_send_id',
    'state',
    'version',
    'snapshot_name',
    'snapshot_item_count',
    'created_at',
    'state_changed_at',
  };
  static const _terminalResultKeys = {
    'template_send_id',
    'state',
    'version',
    'state_changed_at',
  };
  static const _acceptResultKeys = {
    ..._terminalResultKeys,
    'accepted_template_id',
  };
  static const _profileKeys = {
    'profile_id',
    'username',
    'display_name',
  };
  static const _itemKeys = {
    'name',
    'quantity_thousandths',
    'position',
  };
  static const _detailKeys = {
    'template_send_id',
    'sender',
    'snapshot_name',
    'snapshot_item_count',
    'state',
    'version',
    'accepted_template_id',
    'created_at',
    'state_changed_at',
    'items',
  };

  static TemplateSendProfile _eligibleProfile(Map<String, dynamic> row) {
    _expectExactKeys(row, _eligibleProfileKeys);
    return _profile(row);
  }

  static TemplateSendProfile _profile(Map<String, dynamic> row) {
    _expectExactKeys(row, _profileKeys);
    final username = _trimmedString(row['username']);
    final displayName = _trimmedString(row['display_name']);
    if (!_usernamePattern.hasMatch(username) || displayName.runes.length > 50) {
      throw const FormatException('invalid template send profile');
    }
    return TemplateSendProfile(
      id: _uuid(row['profile_id']),
      username: username,
      displayName: displayName,
    );
  }

  static ReceivedTemplateSendSummary _receivedSummary(
    Map<String, dynamic> row,
  ) {
    _expectExactKeys(row, _receivedKeys);
    return ReceivedTemplateSendSummary(
      id: _uuid(row['template_send_id']),
      sender: TemplateSendProfile(
        id: _uuid(row['sender_profile_id']),
        username: _profileUsername(row['sender_username']),
        displayName: _displayName(row['sender_display_name']),
      ),
      snapshotName: _snapshotName(row['snapshot_name']),
      itemCount: _boundedCount(row['snapshot_item_count'], 0, 200),
      state: TemplateSendState.parse(_string(row['state'])),
      version: _positiveInt(row['version']),
      createdAt: _dateTime(row['created_at']),
      stateChangedAt: _dateTime(row['state_changed_at']),
    );
  }

  static SentTemplateSendSummary _sentSummary(Map<String, dynamic> row) {
    _expectExactKeys(row, _sentKeys);
    return SentTemplateSendSummary(
      id: _uuid(row['template_send_id']),
      recipient: TemplateSendProfile(
        id: _uuid(row['recipient_profile_id']),
        username: _profileUsername(row['recipient_username']),
        displayName: _displayName(row['recipient_display_name']),
      ),
      snapshotName: _snapshotName(row['snapshot_name']),
      itemCount: _boundedCount(row['snapshot_item_count'], 0, 200),
      state: TemplateSendState.parse(_string(row['state'])),
      version: _positiveInt(row['version']),
      createdAt: _dateTime(row['created_at']),
      stateChangedAt: _dateTime(row['state_changed_at']),
    );
  }

  static TemplateSendSnapshotItem _item(Map<String, dynamic> row) {
    _expectExactKeys(row, _itemKeys);
    return TemplateSendSnapshotItem(
      name: _boundedItemName(row['name']),
      quantity: ListQuantity.fromThousandths(
        _positiveInt(row['quantity_thousandths']),
      ),
      position: _boundedCount(row['position'], 1, 200),
    );
  }

  static TemplateSendMutationResult _mutation(
    Map<String, dynamic> row, {
    String? acceptedTemplateId,
    String? snapshotName,
    int? itemCount,
    DateTime? createdAt,
  }) {
    return TemplateSendMutationResult(
      id: _uuid(row['template_send_id']),
      state: TemplateSendState.parse(_string(row['state'])),
      version: _positiveInt(row['version']),
      stateChangedAt: _dateTime(row['state_changed_at']),
      acceptedTemplateId: acceptedTemplateId,
      snapshotName: snapshotName,
      itemCount: itemCount,
      createdAt: createdAt,
    );
  }

  static void _validateRecipientOrder(
    List<TemplateSendProfile> profiles,
    TemplateSendRecipientCursor? cursor,
  ) {
    String? previousUsername = cursor?.username.toLowerCase();
    String? previousId = cursor?.profileId;
    final ids = <String>{};
    for (final profile in profiles) {
      if (!ids.add(profile.id)) {
        throw const FormatException('duplicate eligible recipient');
      }
      final username = profile.username.toLowerCase();
      if (previousUsername != null &&
          (username.compareTo(previousUsername) < 0 ||
              (username == previousUsername &&
                  profile.id.compareTo(previousId!) <= 0))) {
        throw const FormatException('invalid recipient page order');
      }
      previousUsername = username;
      previousId = profile.id;
    }
  }

  static void _validateSummaryPage(
    Iterable<
            ({
              String id,
              TemplateSendState state,
              DateTime changedAt,
            })>
        summaries,
    TemplateSendHistoryFilter filter,
    int pageSize,
    TemplateSendCursor? cursor,
  ) {
    final entries = summaries.toList(growable: false);
    if (entries.length > pageSize) {
      throw const FormatException('oversized template send page');
    }
    DateTime? previousTime = cursor?.stateChangedAt;
    String? previousId = cursor?.templateSendId;
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.id) ||
          (filter == TemplateSendHistoryFilter.pending) !=
              (entry.state == TemplateSendState.pending)) {
        throw const FormatException('invalid template send page');
      }
      if (previousTime != null &&
          (entry.changedAt.isAfter(previousTime) ||
              (entry.changedAt == previousTime &&
                  entry.id.compareTo(previousId!) >= 0))) {
        throw const FormatException('invalid template send page order');
      }
      previousTime = entry.changedAt;
      previousId = entry.id;
    }
  }

  static void _validateItems(List<TemplateSendSnapshotItem> items) {
    var previousPosition = 0;
    for (final item in items) {
      if (item.position <= previousPosition) {
        throw const FormatException('invalid snapshot item order');
      }
      previousPosition = item.position;
    }
  }

  static TemplateSendFailure _failure(Object error) {
    if (error is TemplateSendFailure) return error;
    if (error is PostgrestException) {
      return TemplateSendFailure(
        switch (error.code) {
          '22023' => TemplateSendFailureCode.invalid,
          'P0002' || '42501' => TemplateSendFailureCode.unavailable,
          '40001' => TemplateSendFailureCode.stale,
          '23505' => TemplateSendFailureCode.retryConflict,
          '54000' => TemplateSendFailureCode.capacity,
          '55000' => TemplateSendFailureCode.noLongerPending,
          _ => TemplateSendFailureCode.generic,
        },
      );
    }
    if (error is FormatException) {
      return const TemplateSendFailure(TemplateSendFailureCode.generic);
    }
    return const TemplateSendFailure(TemplateSendFailureCode.transport);
  }

  static List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) throw const FormatException('expected rows');
    return response.map(_object).toList(growable: false);
  }

  static Map<String, dynamic> _singleRow(Object? response) {
    final rows = _rows(response);
    if (rows.length != 1) throw const FormatException('expected one row');
    return rows.single;
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

  static String? _nullableUuid(Object? value) =>
      value == null ? null : _uuid(value);

  static String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid string');
    }
    return value;
  }

  static String _trimmedString(Object? value) {
    final result = _string(value);
    if (result.trim() != result) {
      throw const FormatException('invalid trimmed string');
    }
    return result;
  }

  static String _profileUsername(Object? value) {
    final result = _trimmedString(value);
    if (!_usernamePattern.hasMatch(result)) {
      throw const FormatException('invalid username');
    }
    return result;
  }

  static String _displayName(Object? value) {
    final result = _trimmedString(value);
    if (result.runes.length > 50) {
      throw const FormatException('invalid display name');
    }
    return result;
  }

  static String _snapshotName(Object? value) => _trimmedString(value);

  static String _boundedItemName(Object? value) {
    final result = _trimmedString(value);
    if (result.runes.length > 120) {
      throw const FormatException('invalid item name');
    }
    return result;
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('invalid positive integer');
    }
    return value;
  }

  static int _boundedCount(Object? value, int minimum, int maximum) {
    if (value is! int || value < minimum || value > maximum) {
      throw const FormatException('invalid bounded integer');
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
