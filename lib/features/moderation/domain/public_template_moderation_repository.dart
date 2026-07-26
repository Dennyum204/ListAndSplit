import 'package:list_and_split/features/moderation/domain/public_template_moderation.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';

enum PublicTemplateModerationFailureCode {
  invalid,
  unavailable,
  stale,
  retryConflict,
  revoked,
  transport,
  generic,
}

class PublicTemplateModerationFailure implements Exception {
  const PublicTemplateModerationFailure(this.code);

  final PublicTemplateModerationFailureCode code;
}

abstract interface class PublicTemplateModerationRepository {
  Future<bool> isModerator();

  Future<ModerationQueuePage> listQueue(
    ModerationQueueFilter filter, {
    int pageSize = 20,
    ModerationQueueCursor? cursor,
  });

  Future<PublicTemplateModerationCase> getCase(String groupId);

  Future<ModerationActionResult> dismiss(
    String groupId, {
    required int expectedGroupVersion,
    required String privateNote,
    required String requestId,
  });

  Future<ModerationActionResult> takeDown(
    String groupId, {
    required int expectedGroupVersion,
    required int expectedTemplateVersion,
    required PublicTemplateReportReason ownerReason,
    required String privateNote,
    required String requestId,
  });

  Future<ModerationActionResult> restore(
    String templateId, {
    required int expectedRestrictionVersion,
    required int expectedTemplateVersion,
    required String privateNote,
    required String requestId,
  });
}
