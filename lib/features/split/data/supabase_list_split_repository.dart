import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ListSplitRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseListSplitRepository implements ListSplitRepository {
  SupabaseListSplitRepository(
    SupabaseClient client, {
    ListSplitRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final ListSplitRpc _rpc;

  @override
  Future<ListSplitOverview> getSplit(String listId) => _call(
        'get_active_list_split',
        {'target_list_id': listId},
      );

  @override
  Future<ListSplitOverview> enableSplit(
    String listId,
    SplitCurrency currency, {
    required int expectedListVersion,
  }) =>
      _call(
        'enable_active_list_split',
        {
          'target_list_id': listId,
          'new_currency_code': currency.code,
          'expected_list_version': expectedListVersion,
        },
      );

  @override
  Future<ListSplitOverview> changeCurrency(
    String listId,
    SplitCurrency currency, {
    required int expectedSplitVersion,
  }) =>
      _call(
        'change_active_list_split_currency',
        {
          'target_list_id': listId,
          'new_currency_code': currency.code,
          'expected_split_version': expectedSplitVersion,
        },
      );

  @override
  Future<ListSplitOverview> createExpense(
    String listId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required String requestId,
    required int expectedSplitVersion,
  }) =>
      _call(
        'create_active_list_expense',
        {
          'target_list_id': listId,
          'new_description': description,
          'new_amount_minor': amountMinor,
          'payer_participant_id': payerParticipantId,
          'beneficiary_participant_ids': beneficiaryParticipantIds,
          'creation_request_id': requestId,
          'expected_split_version': expectedSplitVersion,
        },
      );

  @override
  Future<ListSplitOverview> updateExpense(
    String listId,
    String expenseId, {
    required String description,
    required int amountMinor,
    required String payerParticipantId,
    required List<String> beneficiaryParticipantIds,
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  }) =>
      _call(
        'update_active_list_expense',
        {
          'target_list_id': listId,
          'target_expense_id': expenseId,
          'new_description': description,
          'new_amount_minor': amountMinor,
          'payer_participant_id': payerParticipantId,
          'beneficiary_participant_ids': beneficiaryParticipantIds,
          'expected_split_version': expectedSplitVersion,
          'expected_expense_version': expectedExpenseVersion,
        },
      );

  @override
  Future<ListSplitOverview> deleteExpense(
    String listId,
    String expenseId, {
    required int expectedSplitVersion,
    required int expectedExpenseVersion,
  }) =>
      _call(
        'delete_active_list_expense',
        {
          'target_list_id': listId,
          'target_expense_id': expenseId,
          'expected_split_version': expectedSplitVersion,
          'expected_expense_version': expectedExpenseVersion,
        },
      );

  Future<ListSplitOverview> _call(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    try {
      return _overview(_object(await _rpc(functionName, params: params)));
    } catch (error) {
      throw _failure(error);
    }
  }

  static ListSplitOverview _overview(Map<String, dynamic> json) {
    _expectExactKeys(json, const {
      'list_id',
      'list_title',
      'list_status',
      'list_version',
      'is_owner',
      'enabled',
      'writable',
      'settings',
      'participants',
      'expenses',
    });
    final listId = _uuid(json['list_id']);
    final listStatus = SplitListStatus.fromWire(_string(json['list_status']));
    final enabled = _boolean(json['enabled']);
    final writable = _boolean(json['writable']);
    final settings =
        json['settings'] == null ? null : _settings(_object(json['settings']));
    if (enabled != (settings != null) ||
        writable != (enabled && listStatus == SplitListStatus.active)) {
      throw const FormatException('invalid Split state');
    }
    final participants = _objects(json['participants'])
        .map(_participant)
        .toList(growable: false);
    final participantIds = participants.map((entry) => entry.id).toSet();
    if (participantIds.length != participants.length) {
      throw const FormatException('duplicate participant');
    }
    final expenses = _objects(json['expenses'])
        .map((entry) => _expense(entry, participantIds))
        .toList(growable: false);
    final expenseIds = expenses.map((entry) => entry.id).toSet();
    if (expenseIds.length != expenses.length) {
      throw const FormatException('invalid expense collection');
    }
    if (!enabled && (participants.isNotEmpty || expenses.isNotEmpty)) {
      throw const FormatException('disabled Split contains records');
    }
    final paidByParticipant = {for (final id in participantIds) id: 0};
    final owedByParticipant = {for (final id in participantIds) id: 0};
    for (final expense in expenses) {
      paidByParticipant[expense.payerParticipantId] =
          paidByParticipant[expense.payerParticipantId]! + expense.amountMinor;
      for (final share in expense.shares) {
        owedByParticipant[share.participantId] =
            owedByParticipant[share.participantId]! + share.amountMinor;
      }
    }
    for (final participant in participants) {
      if (participant.paidMinor != paidByParticipant[participant.id] ||
          participant.owedMinor != owedByParticipant[participant.id]) {
        throw const FormatException('invalid participant balances');
      }
    }
    return ListSplitOverview(
      listId: listId,
      listTitle: _boundedString(json['list_title'], 1, 80),
      listStatus: listStatus,
      listVersion: _positiveInt(json['list_version']),
      isOwner: _boolean(json['is_owner']),
      enabled: enabled,
      writable: writable,
      settings: settings,
      participants: participants,
      expenses: expenses,
    );
  }

  static ListSplitSettings _settings(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {'currency_code', 'version', 'created_at', 'updated_at'},
    );
    final createdAt = _dateTime(json['created_at']);
    final updatedAt = _dateTime(json['updated_at']);
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException('invalid Split settings timestamps');
    }
    return ListSplitSettings(
      currency: SplitCurrency.fromCode(_string(json['currency_code'])),
      version: _positiveInt(json['version']),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static ListSplitParticipant _participant(Map<String, dynamic> json) {
    _expectExactKeys(json, const {
      'id',
      'profile_id',
      'username',
      'display_name',
      'is_anonymized',
      'is_current',
      'paid_minor',
      'owed_minor',
      'balance_minor',
    });
    final profileId = _nullableUuid(json['profile_id']);
    final username = _nullableString(json['username']);
    final displayName = _nullableString(json['display_name']);
    final isAnonymized = _boolean(json['is_anonymized']);
    final isCurrent = _boolean(json['is_current']);
    final paid = _nonNegativeInt(json['paid_minor']);
    final owed = _nonNegativeInt(json['owed_minor']);
    final balance = _integer(json['balance_minor']);
    if (balance != paid - owed ||
        isAnonymized != (profileId == null) ||
        (isAnonymized && isCurrent) ||
        (isAnonymized && (username != null || displayName != null)) ||
        (!isAnonymized && (username == null || displayName == null))) {
      throw const FormatException('invalid Split participant');
    }
    return ListSplitParticipant(
      id: _uuid(json['id']),
      profileId: profileId,
      username: username,
      displayName: displayName,
      isAnonymized: isAnonymized,
      isCurrent: isCurrent,
      paidMinor: paid,
      owedMinor: owed,
      balanceMinor: balance,
    );
  }

  static ListSplitExpense _expense(
    Map<String, dynamic> json,
    Set<String> participantIds,
  ) {
    _expectExactKeys(json, const {
      'id',
      'description',
      'amount_minor',
      'payer_participant_id',
      'creator_participant_id',
      'last_editor_participant_id',
      'version',
      'created_at',
      'updated_at',
      'beneficiary_participant_ids',
      'shares',
    });
    final amount = _positiveInt(json['amount_minor']);
    if (amount > splitExpenseAmountMaxMinor) {
      throw const FormatException('invalid expense amount');
    }
    final payerId = _uuid(json['payer_participant_id']);
    final creatorId = _uuid(json['creator_participant_id']);
    final editorId = _uuid(json['last_editor_participant_id']);
    if (!participantIds.containsAll([payerId, creatorId, editorId])) {
      throw const FormatException('unknown expense actor');
    }
    final beneficiaries = _uuidList(json['beneficiary_participant_ids']);
    if (beneficiaries.isEmpty ||
        beneficiaries.toSet().length != beneficiaries.length ||
        !participantIds.containsAll(beneficiaries)) {
      throw const FormatException('invalid beneficiaries');
    }
    final shares = _objects(json['shares']).map((shareJson) {
      _expectExactKeys(shareJson, const {'participant_id', 'amount_minor'});
      return ListExpenseShare(
        participantId: _uuid(shareJson['participant_id']),
        amountMinor: _nonNegativeInt(shareJson['amount_minor']),
      );
    }).toList(growable: false);
    if (shares.length != beneficiaries.length ||
        shares.map((entry) => entry.participantId).toSet().length !=
            shares.length ||
        !shares
            .map((entry) => entry.participantId)
            .toSet()
            .containsAll(beneficiaries) ||
        shares.fold<int>(0, (sum, entry) => sum + entry.amountMinor) !=
            amount) {
      throw const FormatException('invalid expense shares');
    }
    final createdAt = _dateTime(json['created_at']);
    final updatedAt = _dateTime(json['updated_at']);
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException('invalid expense timestamps');
    }
    return ListSplitExpense(
      id: _uuid(json['id']),
      description: _boundedString(
        json['description'],
        1,
        splitExpenseDescriptionMaxLength,
      ),
      amountMinor: amount,
      payerParticipantId: payerId,
      creatorParticipantId: creatorId,
      lastEditorParticipantId: editorId,
      version: _positiveInt(json['version']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      beneficiaryParticipantIds: beneficiaries,
      shares: shares,
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const FormatException('expected object');
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _objects(Object? value) {
    if (value is! List) throw const FormatException('expected objects');
    return value.map(_object).toList(growable: false);
  }

  static void _expectExactKeys(
    Map<String, dynamic> json,
    Set<String> expected,
  ) {
    if (json.length != expected.length ||
        !json.keys.toSet().containsAll(expected)) {
      throw const FormatException('unexpected projection keys');
    }
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

  static String? _nullableUuid(Object? value) =>
      value == null ? null : _uuid(value);

  static List<String> _uuidList(Object? value) {
    if (value is! List) throw const FormatException('expected UUID list');
    return value.map(_uuid).toList(growable: false);
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid string');
    }
    return value;
  }

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    return _string(value);
  }

  static String _boundedString(Object? value, int min, int max) {
    final result = _string(value);
    if (result.trim() != result || result.length < min || result.length > max) {
      throw const FormatException('invalid bounded string');
    }
    return result;
  }

  static bool _boolean(Object? value) {
    if (value is! bool) throw const FormatException('invalid boolean');
    return value;
  }

  static int _integer(Object? value) {
    if (value is! int) throw const FormatException('invalid integer');
    return value;
  }

  static int _positiveInt(Object? value) {
    final result = _integer(value);
    if (result < 1) throw const FormatException('invalid positive integer');
    return result;
  }

  static int _nonNegativeInt(Object? value) {
    final result = _integer(value);
    if (result < 0) throw const FormatException('invalid non-negative integer');
    return result;
  }

  static DateTime _dateTime(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('invalid UTC timestamp');
    }
    return parsed;
  }

  static ListSplitFailure _failure(Object error) {
    if (error is ListSplitFailure) return error;
    if (error is PostgrestException) {
      return ListSplitFailure(
        switch (error.code) {
          '22023' => ListSplitFailureCode.invalid,
          'P0002' || '42501' => ListSplitFailureCode.unavailable,
          '40001' => ListSplitFailureCode.stale,
          '55000' => ListSplitFailureCode.archived,
          '54000' => ListSplitFailureCode.capacity,
          _ => ListSplitFailureCode.generic,
        },
      );
    }
    if (error is FormatException) {
      return const ListSplitFailure(ListSplitFailureCode.generic);
    }
    return const ListSplitFailure(ListSplitFailureCode.transport);
  }
}
