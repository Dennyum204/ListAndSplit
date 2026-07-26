import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

enum ModerationQueueFilter {
  open('open'),
  takenDown('taken_down'),
  closed('closed');

  const ModerationQueueFilter(this.wireValue);

  final String wireValue;
}

enum PublicTemplateModerationAction {
  dismiss('dismiss'),
  takeDown('take_down'),
  restore('restore');

  const PublicTemplateModerationAction(this.wireValue);

  final String wireValue;
}

class ModerationQueueCursor {
  const ModerationQueueCursor({
    required this.at,
    required this.groupId,
  });

  final DateTime at;
  final String groupId;
}

class ModerationQueueCase {
  const ModerationQueueCase({
    required this.groupId,
    required this.templateId,
    required this.templateName,
    required this.reportedRevision,
    required this.reportCount,
    required this.status,
    required this.version,
    required this.firstReportedAt,
    required this.closedAt,
    required this.sourceChanged,
    required this.sourceUnpublished,
    required this.sourceDeleted,
    required this.sourceModerated,
    required this.isRestricted,
    required this.restrictionVersion,
  });

  final String groupId;
  final String templateId;
  final String templateName;
  final int reportedRevision;
  final int reportCount;
  final String status;
  final int version;
  final DateTime firstReportedAt;
  final DateTime? closedAt;
  final bool sourceChanged;
  final bool sourceUnpublished;
  final bool sourceDeleted;
  final bool sourceModerated;
  final bool isRestricted;
  final int? restrictionVersion;
}

class ModerationQueuePage {
  ModerationQueuePage({
    required this.filter,
    required List<ModerationQueueCase> cases,
    required this.nextCursor,
  }) : cases = List.unmodifiable(cases);

  final ModerationQueueFilter filter;
  final List<ModerationQueueCase> cases;
  final ModerationQueueCursor? nextCursor;
}

class ModerationSnapshotItem {
  const ModerationSnapshotItem({
    required this.name,
    required this.quantity,
    required this.position,
  });

  final String name;
  final ListQuantity quantity;
  final int position;
}

class ModerationTemplateSnapshot {
  ModerationTemplateSnapshot({
    required this.name,
    required List<ModerationSnapshotItem> items,
  }) : items = List.unmodifiable(items);

  final String name;
  final List<ModerationSnapshotItem> items;
}

class ModerationReporterProfile {
  const ModerationReporterProfile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;
}

class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.reason,
    required this.explanation,
    required this.createdAt,
    required this.reporter,
  });

  final String id;
  final PublicTemplateReportReason reason;
  final String? explanation;
  final DateTime createdAt;
  final ModerationReporterProfile? reporter;
}

class ModerationCurrentTemplate {
  ModerationCurrentTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.isPublic,
    required List<ModerationSnapshotItem> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String name;
  final int version;
  final bool isPublic;
  final List<ModerationSnapshotItem> items;
}

class ModerationRestriction {
  const ModerationRestriction({
    required this.active,
    required this.version,
    required this.reason,
    required this.imposedAt,
    required this.restoredAt,
    required this.sourceDeletedAt,
  });

  final bool active;
  final int version;
  final PublicTemplateReportReason reason;
  final DateTime imposedAt;
  final DateTime? restoredAt;
  final DateTime? sourceDeletedAt;
}

class PublicTemplateModerationCase {
  PublicTemplateModerationCase({
    required this.summary,
    required this.reportedSnapshot,
    required List<ModerationReport> reports,
    required this.currentTemplate,
    required this.restriction,
  }) : reports = List.unmodifiable(reports);

  final ModerationQueueCase summary;
  final ModerationTemplateSnapshot reportedSnapshot;
  final List<ModerationReport> reports;
  final ModerationCurrentTemplate? currentTemplate;
  final ModerationRestriction? restriction;
}

class ModerationActionResult {
  const ModerationActionResult({
    required this.eventId,
    required this.action,
    required this.groupId,
    required this.groupVersion,
    required this.restrictionVersion,
    required this.templateVersion,
    required this.createdAt,
  });

  final String eventId;
  final PublicTemplateModerationAction action;
  final String? groupId;
  final int? groupVersion;
  final int? restrictionVersion;
  final int? templateVersion;
  final DateTime createdAt;
}
