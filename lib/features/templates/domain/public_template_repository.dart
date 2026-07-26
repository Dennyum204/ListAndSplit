import 'package:list_and_split/features/templates/domain/public_template.dart';

enum PublicTemplateFailureCode {
  invalid,
  unavailable,
  stale,
  retryConflict,
  capacity,
  transport,
  generic,
}

class PublicTemplateFailure implements Exception {
  const PublicTemplateFailure(this.code);

  final PublicTemplateFailureCode code;
}

abstract interface class PublicTemplateRepository {
  Future<PublicTemplatePage> listProfileTemplates(
    String profileId, {
    int pageSize = 20,
    PublicTemplateCursor? cursor,
  });

  Future<PublicTemplateDetail> getTemplate(
    String profileId,
    String templateId,
  );

  Future<PublicTemplateCopyResult> copyTemplate(
    String templateId, {
    required int expectedVersion,
    required String requestId,
  });
}
