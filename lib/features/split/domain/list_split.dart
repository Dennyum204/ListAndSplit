const splitExpenseDescriptionMaxLength = 120;
const splitExpenseAmountMaxMinor = 999999999;
const splitExpenseCapacity = 200;

enum SplitCurrency {
  chf('CHF', 2),
  eur('EUR', 2);

  const SplitCurrency(this.code, this.minorUnitDigits);

  final String code;
  final int minorUnitDigits;

  static SplitCurrency fromCode(String value) => switch (value) {
        'CHF' => chf,
        'EUR' => eur,
        _ => throw const FormatException('unsupported Split currency'),
      };
}

enum SplitListStatus {
  active('active'),
  archived('archived');

  const SplitListStatus(this.wireValue);

  final String wireValue;

  static SplitListStatus fromWire(String value) => switch (value) {
        'active' => active,
        'archived' => archived,
        _ => throw const FormatException('unknown list status'),
      };
}

class MoneyAmount {
  const MoneyAmount._(this.minorUnits, this.currency);

  factory MoneyAmount.fromMinorUnits(
    int minorUnits,
    SplitCurrency currency,
  ) =>
      MoneyAmount._(minorUnits, currency);

  static MoneyAmount? tryParse(
    String input, {
    required SplitCurrency currency,
  }) {
    final normalized = input.trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fractionText = match.group(2) ?? '';
    final fraction = fractionText.isEmpty
        ? 0
        : int.parse(fractionText.padRight(currency.minorUnitDigits, '0'));
    final scale = _powerOfTen(currency.minorUnitDigits);
    if (whole > splitExpenseAmountMaxMinor ~/ scale) return null;
    final minorUnits = whole * scale + fraction;
    if (minorUnits < 1 || minorUnits > splitExpenseAmountMaxMinor) return null;
    return MoneyAmount._(minorUnits, currency);
  }

  final int minorUnits;
  final SplitCurrency currency;

  String format({bool includeCode = true}) {
    final absolute = minorUnits.abs();
    final scale = _powerOfTen(currency.minorUnitDigits);
    final whole = absolute ~/ scale;
    final fraction =
        (absolute % scale).toString().padLeft(currency.minorUnitDigits, '0');
    final sign = minorUnits < 0 ? '-' : '';
    final value = '$sign$whole.$fraction';
    return includeCode ? '${currency.code} $value' : value;
  }

  static int _powerOfTen(int exponent) {
    var value = 1;
    for (var index = 0; index < exponent; index += 1) {
      value *= 10;
    }
    return value;
  }
}

class ListSplitSettings {
  const ListSplitSettings({
    required this.currency,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final SplitCurrency currency;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ListSplitParticipant {
  const ListSplitParticipant({
    required this.id,
    required this.profileId,
    required this.username,
    required this.displayName,
    required this.isAnonymized,
    required this.isCurrent,
    required this.paidMinor,
    required this.owedMinor,
    required this.balanceMinor,
  });

  final String id;
  final String? profileId;
  final String? username;
  final String? displayName;
  final bool isAnonymized;
  final bool isCurrent;
  final int paidMinor;
  final int owedMinor;
  final int balanceMinor;
}

class ListExpenseShare {
  const ListExpenseShare({
    required this.participantId,
    required this.amountMinor,
  });

  final String participantId;
  final int amountMinor;
}

class ListSplitExpense {
  ListSplitExpense({
    required this.id,
    required this.description,
    required this.amountMinor,
    required this.payerParticipantId,
    required this.creatorParticipantId,
    required this.lastEditorParticipantId,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required List<String> beneficiaryParticipantIds,
    required List<ListExpenseShare> shares,
  })  : beneficiaryParticipantIds =
            List.unmodifiable(beneficiaryParticipantIds),
        shares = List.unmodifiable(shares);

  final String id;
  final String description;
  final int amountMinor;
  final String payerParticipantId;
  final String creatorParticipantId;
  final String lastEditorParticipantId;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> beneficiaryParticipantIds;
  final List<ListExpenseShare> shares;
}

class ListSplitOverview {
  ListSplitOverview({
    required this.listId,
    required this.listTitle,
    required this.listStatus,
    required this.listVersion,
    required this.isOwner,
    required this.enabled,
    required this.writable,
    required this.settings,
    required List<ListSplitParticipant> participants,
    required List<ListSplitExpense> expenses,
  })  : participants = List.unmodifiable(participants),
        expenses = List.unmodifiable(expenses);

  final String listId;
  final String listTitle;
  final SplitListStatus listStatus;
  final int listVersion;
  final bool isOwner;
  final bool enabled;
  final bool writable;
  final ListSplitSettings? settings;
  final List<ListSplitParticipant> participants;
  final List<ListSplitExpense> expenses;

  SplitCurrency? get currency => settings?.currency;

  ListSplitParticipant? participantById(String participantId) {
    for (final participant in participants) {
      if (participant.id == participantId) return participant;
    }
    return null;
  }

  ListSplitParticipant? participantForProfile(String profileId) {
    for (final participant in participants) {
      if (participant.profileId == profileId) return participant;
    }
    return null;
  }
}
