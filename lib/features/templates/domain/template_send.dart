import 'package:list_and_split/features/lists/domain/list_quantity.dart';

enum TemplateSendState {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  revoked('revoked'),
  unavailable('unavailable');

  const TemplateSendState(this.wireValue);

  final String wireValue;

  static TemplateSendState parse(String value) {
    return values.firstWhere(
      (state) => state.wireValue == value,
      orElse: () => throw const FormatException('invalid template send state'),
    );
  }
}

enum TemplateSendHistoryFilter {
  pending('pending'),
  history('history');

  const TemplateSendHistoryFilter(this.wireValue);

  final String wireValue;
}

class TemplateSendProfile {
  const TemplateSendProfile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;
}

class TemplateSendRecipientCursor {
  const TemplateSendRecipientCursor({
    required this.username,
    required this.profileId,
  });

  final String username;
  final String profileId;
}

class TemplateSendCursor {
  const TemplateSendCursor({
    required this.stateChangedAt,
    required this.templateSendId,
  });

  final DateTime stateChangedAt;
  final String templateSendId;
}

class ReceivedTemplateSendSummary {
  const ReceivedTemplateSendSummary({
    required this.id,
    required this.sender,
    required this.snapshotName,
    required this.itemCount,
    required this.state,
    required this.version,
    required this.createdAt,
    required this.stateChangedAt,
  });

  final String id;
  final TemplateSendProfile sender;
  final String snapshotName;
  final int itemCount;
  final TemplateSendState state;
  final int version;
  final DateTime createdAt;
  final DateTime stateChangedAt;
}

class SentTemplateSendSummary {
  const SentTemplateSendSummary({
    required this.id,
    required this.recipient,
    required this.snapshotName,
    required this.itemCount,
    required this.state,
    required this.version,
    required this.createdAt,
    required this.stateChangedAt,
  });

  final String id;
  final TemplateSendProfile recipient;
  final String snapshotName;
  final int itemCount;
  final TemplateSendState state;
  final int version;
  final DateTime createdAt;
  final DateTime stateChangedAt;
}

class TemplateSendSnapshotItem {
  const TemplateSendSnapshotItem({
    required this.name,
    required this.quantity,
    required this.position,
  });

  final String name;
  final ListQuantity quantity;
  final int position;
}

class ReceivedTemplateSendDetail {
  ReceivedTemplateSendDetail({
    required this.summary,
    required this.acceptedTemplateId,
    required List<TemplateSendSnapshotItem> items,
  }) : items = List.unmodifiable(items) {
    if (summary.itemCount != this.items.length) {
      throw const FormatException('inconsistent template send item count');
    }
  }

  final ReceivedTemplateSendSummary summary;
  final String? acceptedTemplateId;
  final List<TemplateSendSnapshotItem> items;
}

class TemplateSendMutationResult {
  const TemplateSendMutationResult({
    required this.id,
    required this.state,
    required this.version,
    required this.stateChangedAt,
    this.acceptedTemplateId,
    this.snapshotName,
    this.itemCount,
    this.createdAt,
  }) : assert(
          acceptedTemplateId == null || state == TemplateSendState.accepted,
        );

  final String id;
  final TemplateSendState state;
  final int version;
  final DateTime stateChangedAt;
  final String? acceptedTemplateId;
  final String? snapshotName;
  final int? itemCount;
  final DateTime? createdAt;
}
