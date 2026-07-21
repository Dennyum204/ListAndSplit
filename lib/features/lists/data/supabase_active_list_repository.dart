import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ActiveListRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseActiveListRepository implements ActiveListRepository {
  SupabaseActiveListRepository(
    SupabaseClient client, {
    ActiveListRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final ActiveListRpc _rpc;

  @override
  Future<ActiveListPage> listLists({
    required ActiveListStatus status,
    required int limit,
    ActiveListCursor? before,
  }) async {
    try {
      final rows = _rows(
        await _rpc(
          'list_active_lists',
          params: {
            'requested_status': status.wireValue,
            'page_size': limit,
            'before_sort_at': before?.sortAt.toUtc().toIso8601String(),
            'before_list_id': before?.id,
          },
        ),
      );
      return ActiveListPage(
        lists: rows.map(_summaryWithCounts).toList(growable: false),
        hasMore: rows.length == limit,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListSummary> getList(String listId) async {
    try {
      return _summaryWithCounts(
        _singleRow(
          await _rpc(
            'get_active_list',
            params: {'target_list_id': listId},
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ActiveListItem>> listItems(String listId) async {
    try {
      return _rows(
        await _rpc(
          'list_active_list_items',
          params: {'target_list_id': listId},
        ),
      ).map(_item).toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ActiveListParticipant>> listParticipants(String listId) async {
    try {
      return _rows(await _rpc('list_active_list_participants', params: {
        'target_list_id': listId,
      }))
          .map(_participant)
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ActiveListAccessProfile>> listPendingInvitations(
    String listId,
  ) async {
    try {
      return _rows(await _rpc('list_pending_active_list_invitations', params: {
        'target_list_id': listId,
      }))
          .map(_accessProfile)
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<ActiveListAccessProfile>> listEligibleInvitees(
    String listId,
  ) async {
    try {
      return _rows(await _rpc('list_eligible_active_list_invitees', params: {
        'target_list_id': listId,
      }))
          .map(_accessProfile)
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListInvitation> getInvitation(String listId) async {
    try {
      final json = _singleRow(await _rpc('get_active_list_invitation', params: {
        'target_list_id': listId,
      }));
      return ActiveListInvitation(
        listId: _uuid(json['list_id']),
        listTitle: _boundedString(json['list_title'], 1, 80),
        listStatus: ActiveListStatus.fromWire(_string(json['list_status'])),
        owner: ActiveListParticipant(
          profileId: _uuid(json['owner_profile_id']),
          username: _string(json['owner_username']),
          displayName: _string(json['owner_display_name']),
          isOwner: true,
        ),
        accessVersion: _positiveInt(json['access_version']),
        createdAt: _dateTime(json['created_at']),
        stateChangedAt: _dateTime(json['state_changed_at']),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListSummary> createList(
    String title, {
    required String requestId,
  }) async {
    try {
      return _summaryWithoutCounts(
        _singleRow(
          await _rpc(
            'create_active_list',
            params: {
              'new_title': title,
              'creation_request_id': requestId,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) =>
      _listMutation(
        'rename_active_list',
        {
          'target_list_id': listId,
          'new_title': title,
          'expected_list_version': expectedVersion,
        },
      );

  @override
  Future<ActiveListSummary> setArchived(
    String listId, {
    required bool archived,
    required int expectedVersion,
  }) =>
      _listMutation(
        'set_active_list_archived',
        {
          'target_list_id': listId,
          'should_archive': archived,
          'expected_list_version': expectedVersion,
        },
      );

  @override
  Future<void> deleteList(
    String listId, {
    required int expectedVersion,
  }) async {
    try {
      await _rpc(
        'delete_active_list',
        params: {
          'target_list_id': listId,
          'expected_list_version': expectedVersion,
        },
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListItem> createItem(
    String listId,
    String name, {
    required int expectedListVersion,
    ListQuantity quantity = ListQuantity.one,
    ListUnit? unit,
    required String requestId,
  }) async {
    try {
      return _item(
        _singleRow(
          await _rpc(
            'create_active_list_item',
            params: {
              'target_list_id': listId,
              'new_name': name,
              'creation_request_id': requestId,
              'expected_list_version': expectedListVersion,
              'new_quantity_thousandths': quantity.thousandths,
              'new_unit_code': unit?.code,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    try {
      return _item(
        _singleRow(
          await _rpc(
            'update_active_list_item',
            params: {
              'target_list_id': listId,
              'target_item_id': itemId,
              'new_name': name,
              'new_quantity_thousandths': quantity.thousandths,
              'new_unit_code': unit?.code,
              'expected_list_version': expectedListVersion,
              'expected_item_version': expectedItemVersion,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListItem> setItemCompleted(
    String listId,
    String itemId, {
    required bool completed,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    try {
      return _item(
        _singleRow(
          await _rpc(
            'set_active_list_item_completed',
            params: {
              'target_list_id': listId,
              'target_item_id': itemId,
              'should_complete': completed,
              'expected_list_version': expectedListVersion,
              'expected_item_version': expectedItemVersion,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> deleteItem(
    String listId,
    String itemId, {
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    try {
      return _positiveInt(
        await _rpc(
          'delete_active_list_item',
          params: {
            'target_list_id': listId,
            'target_item_id': itemId,
            'expected_list_version': expectedListVersion,
            'expected_item_version': expectedItemVersion,
          },
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> reorderItems(
    String listId,
    List<String> orderedItemIds, {
    required int expectedListVersion,
  }) async {
    try {
      return _positiveInt(
        await _rpc(
          'reorder_active_list_items',
          params: {
            'target_list_id': listId,
            'ordered_item_ids': orderedItemIds,
            'expected_list_version': expectedListVersion,
          },
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) async {
    try {
      final row = _singleRow(await _rpc('invite_active_list_member', params: {
        'target_list_id': listId,
        'target_profile_id': profileId,
        'expected_access_version': expectedAccessVersion,
      }));
      return _positiveInt(row['access_version']);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> cancelInvitation(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) =>
      _accessMutation(
        'cancel_active_list_invitation',
        listId,
        expectedAccessVersion,
        profileId: profileId,
      );

  @override
  Future<int> acceptInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) =>
      _accessMutation(
        'accept_active_list_invitation',
        listId,
        expectedAccessVersion,
      );

  @override
  Future<int> declineInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) =>
      _accessMutation(
        'decline_active_list_invitation',
        listId,
        expectedAccessVersion,
      );

  @override
  Future<int> removeMember(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) =>
      _accessMutation(
        'remove_active_list_member',
        listId,
        expectedAccessVersion,
        profileId: profileId,
      );

  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) async {
    try {
      final row = _singleRow(
        await _rpc(
          'transfer_active_list_ownership',
          params: {
            'target_list_id': listId,
            'target_profile_id': profileId,
            'expected_list_version': expectedListVersion,
            'expected_target_access_version': expectedAccessVersion,
          },
        ),
      );
      final result = ActiveListOwnershipTransferResult(
        listId: _uuid(row['list_id']),
        previousOwnerProfileId: _uuid(row['previous_owner_profile_id']),
        ownerProfileId: _uuid(row['owner_profile_id']),
        listVersion: _positiveInt(row['list_version']),
        previousOwnerAccessVersion:
            _positiveInt(row['previous_owner_access_version']),
        ownerAccessVersion: _positiveInt(row['owner_access_version']),
        transferredAt: _dateTime(row['transferred_at']),
      );
      if (result.listId != listId ||
          result.ownerProfileId != profileId ||
          result.previousOwnerProfileId == result.ownerProfileId ||
          result.listVersion != expectedListVersion + 1 ||
          result.ownerAccessVersion != expectedAccessVersion + 1) {
        throw const FormatException('invalid ownership transfer projection');
      }
      return result;
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<int> leaveList(
    String listId, {
    required int expectedAccessVersion,
  }) =>
      _accessMutation(
        'leave_active_list',
        listId,
        expectedAccessVersion,
      );

  Future<int> _accessMutation(
    String functionName,
    String listId,
    int expectedAccessVersion, {
    String? profileId,
  }) async {
    try {
      return _positiveInt(await _rpc(functionName, params: {
        'target_list_id': listId,
        if (profileId != null) 'target_profile_id': profileId,
        'expected_access_version': expectedAccessVersion,
      }));
    } catch (error) {
      throw _failure(error);
    }
  }

  Future<ActiveListSummary> _listMutation(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    try {
      return _summaryWithoutCounts(
        _singleRow(await _rpc(functionName, params: params)),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  static ActiveListSummary _summaryWithCounts(Map<String, dynamic> json) =>
      _summary(
        json,
        itemCount: _nonNegativeInt(json['item_count']),
        completedItemCount: _nonNegativeInt(json['completed_item_count']),
      );

  static ActiveListSummary _summaryWithoutCounts(Map<String, dynamic> json) =>
      _summary(json, itemCount: 0, completedItemCount: 0);

  static ActiveListSummary _summary(
    Map<String, dynamic> json, {
    required int itemCount,
    required int completedItemCount,
  }) {
    final status = ActiveListStatus.fromWire(_string(json['status']));
    final archivedAt = _nullableDateTime(json['archived_at']);
    if ((status == ActiveListStatus.archived) != (archivedAt != null) ||
        completedItemCount > itemCount) {
      throw const FormatException('invalid list projection');
    }
    final isOwner = json['is_owner'] as bool? ?? true;
    final ownerProfileId = json['owner_profile_id'] == null
        ? null
        : _uuid(json['owner_profile_id']);
    final ownerUsername = json['owner_username'] as String?;
    final ownerDisplayName = json['owner_display_name'] as String?;
    final callerAccessVersion = json['caller_access_version'] == null
        ? null
        : _positiveInt(json['caller_access_version']);
    if (!isOwner &&
        (ownerProfileId == null ||
            ownerUsername == null ||
            ownerDisplayName == null ||
            callerAccessVersion == null)) {
      throw const FormatException('invalid shared list projection');
    }
    return ActiveListSummary(
      id: _uuid(json['list_id']),
      title: _boundedString(json['title'], 1, 80),
      status: status,
      version: _positiveInt(json['version']),
      itemCount: itemCount,
      completedItemCount: completedItemCount,
      createdAt: _dateTime(json['created_at']),
      updatedAt: _dateTime(json['updated_at']),
      archivedAt: archivedAt,
      isOwner: isOwner,
      ownerProfileId: ownerProfileId,
      ownerUsername: ownerUsername,
      ownerDisplayName: ownerDisplayName,
      callerAccessVersion: callerAccessVersion,
    );
  }

  static ActiveListParticipant _participant(Map<String, dynamic> json) {
    final isOwner = json['is_owner'] as bool;
    final accessVersion = json['access_version'] == null
        ? null
        : _positiveInt(json['access_version']);
    if (isOwner != (accessVersion == null)) {
      throw const FormatException('invalid participant projection');
    }
    return ActiveListParticipant(
      profileId: _uuid(json['profile_id']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      isOwner: isOwner,
      accessVersion: accessVersion,
    );
  }

  static ActiveListAccessProfile _accessProfile(Map<String, dynamic> json) =>
      ActiveListAccessProfile(
        profileId: _uuid(json['profile_id']),
        username: _string(json['username']),
        displayName: _string(json['display_name']),
        accessVersion: json['access_version'] == null
            ? json['current_access_version'] == null
                ? null
                : _positiveInt(json['current_access_version'])
            : _positiveInt(json['access_version']),
        createdAt: _nullableDateTime(json['created_at']),
        stateChangedAt: _nullableDateTime(json['state_changed_at']),
      );

  static ActiveListItem _item(Map<String, dynamic> json) {
    final completedAt = _nullableDateTime(json['completed_at']);
    final completedBy =
        json['completed_by'] == null ? null : _uuid(json['completed_by']);
    if (completedAt == null && completedBy != null) {
      throw const FormatException('invalid completion projection');
    }
    return ActiveListItem(
      id: _uuid(json['item_id']),
      name: _boundedString(json['name'], 1, 120),
      quantity: ListQuantity.fromThousandths(
        _positiveInt(json['quantity_thousandths']),
      ),
      unit: ListUnit.fromCode(json['unit_code'] as String?),
      position: _positiveInt(json['position']),
      version: _positiveInt(json['version']),
      completedAt: completedAt,
      completedBy: completedBy,
      createdAt: _dateTime(json['created_at']),
      updatedAt: _dateTime(json['updated_at']),
    );
  }

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

  static ActiveListFailure _failure(Object error) {
    if (error is ActiveListFailure) return error;
    if (error is PostgrestException) {
      return ActiveListFailure(
        switch (error.code) {
          '22023' => ActiveListFailureCode.invalid,
          'P0002' => ActiveListFailureCode.unavailable,
          '40001' => ActiveListFailureCode.stale,
          '23505' => ActiveListFailureCode.retryConflict,
          '55000' => ActiveListFailureCode.archived,
          '54000' => ActiveListFailureCode.capacity,
          _ => ActiveListFailureCode.generic,
        },
      );
    }
    return const ActiveListFailure(ActiveListFailureCode.transport);
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

  static String _boundedString(Object? value, int min, int max) {
    final result = _string(value);
    if (result.trim() != result || result.length < min || result.length > max) {
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

  static DateTime? _nullableDateTime(Object? value) =>
      value == null ? null : _dateTime(value);
}
