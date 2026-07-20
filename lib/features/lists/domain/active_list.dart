import 'package:list_and_split/features/lists/domain/list_quantity.dart';

enum ActiveListStatus {
  active('active'),
  archived('archived');

  const ActiveListStatus(this.wireValue);

  final String wireValue;

  static ActiveListStatus fromWire(String value) => switch (value) {
        'active' => active,
        'archived' => archived,
        _ => throw const FormatException('unknown list status'),
      };
}

class ActiveListSummary {
  const ActiveListSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.version,
    required this.itemCount,
    required this.completedItemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.archivedAt,
  });

  final String id;
  final String title;
  final ActiveListStatus status;
  final int version;
  final int itemCount;
  final int completedItemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  ActiveListCursor get cursor => ActiveListCursor(
        sortAt: status == ActiveListStatus.active ? updatedAt : archivedAt!,
        id: id,
      );

  ActiveListSummary copyWith({
    String? title,
    ActiveListStatus? status,
    int? version,
    int? itemCount,
    int? completedItemCount,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return ActiveListSummary(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      version: version ?? this.version,
      itemCount: itemCount ?? this.itemCount,
      completedItemCount: completedItemCount ?? this.completedItemCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
    );
  }
}

class ActiveListCursor {
  const ActiveListCursor({required this.sortAt, required this.id});

  final DateTime sortAt;
  final String id;
}

class ActiveListPage {
  ActiveListPage(
      {required List<ActiveListSummary> lists, required this.hasMore})
      : lists = List.unmodifiable(lists);

  final List<ActiveListSummary> lists;
  final bool hasMore;

  ActiveListCursor? get nextCursor => lists.isEmpty ? null : lists.last.cursor;
}

class ActiveListItem {
  const ActiveListItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.position,
    required this.version,
    required this.completedAt,
    required this.completedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final ListQuantity quantity;
  final ListUnit? unit;
  final int position;
  final int version;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCompleted => completedAt != null;
}

class ActiveListDetail {
  ActiveListDetail({
    required this.summary,
    required List<ActiveListItem> items,
  }) : items = List.unmodifiable(items);

  final ActiveListSummary summary;
  final List<ActiveListItem> items;
}
