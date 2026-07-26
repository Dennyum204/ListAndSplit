import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';

enum PublicTemplateReportReason {
  spamScamDeceptive('spam_scam_deceptive'),
  hateHarassmentBullying('hate_harassment_bullying'),
  sexualContent('sexual_content'),
  violenceDangerous('violence_dangerous'),
  illegalRegulated('illegal_regulated'),
  personalConfidentialInformation('personal_confidential_information'),
  copyrightTrademark('copyright_trademark'),
  other('other');

  const PublicTemplateReportReason(this.wireValue);

  final String wireValue;

  bool get requiresExplanation =>
      this == PublicTemplateReportReason.copyrightTrademark ||
      this == PublicTemplateReportReason.other;
}

class PublicTemplateReportResult {
  const PublicTemplateReportResult({
    required this.reportId,
    required this.groupId,
    required this.reportedRevision,
    required this.createdAt,
  });

  final String reportId;
  final String groupId;
  final int reportedRevision;
  final DateTime createdAt;
}

class PublicTemplateProfile {
  const PublicTemplateProfile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;
  final String username;
  final String displayName;
}

class PublicTemplateSummary {
  const PublicTemplateSummary({
    required this.id,
    required this.name,
    required this.version,
    required this.itemCount,
    required this.publishedAt,
  });

  final String id;
  final String name;
  final int version;
  final int itemCount;
  final DateTime publishedAt;
}

class PublicTemplateCursor {
  const PublicTemplateCursor({
    required this.publishedAt,
    required this.templateId,
  });

  final DateTime publishedAt;
  final String templateId;
}

class PublicTemplatePage {
  PublicTemplatePage({
    required this.profile,
    required List<PublicTemplateSummary> templates,
    required this.nextCursor,
  }) : templates = List.unmodifiable(templates);

  final PublicTemplateProfile profile;
  final List<PublicTemplateSummary> templates;
  final PublicTemplateCursor? nextCursor;
}

class PublicTemplateItem {
  const PublicTemplateItem({
    required this.name,
    required this.quantity,
    required this.position,
  });

  final String name;
  final ListQuantity quantity;
  final int position;
}

class PublicTemplateDetail {
  PublicTemplateDetail({
    required this.profile,
    required this.summary,
    required List<PublicTemplateItem> items,
  }) : items = List.unmodifiable(items) {
    if (summary.itemCount != this.items.length) {
      throw const FormatException('inconsistent public template item count');
    }
  }

  final PublicTemplateProfile profile;
  final PublicTemplateSummary summary;
  final List<PublicTemplateItem> items;
}

class PublicTemplateCopyResult {
  const PublicTemplateCopyResult({required this.template});

  final PrivateTemplateSummary template;
}
