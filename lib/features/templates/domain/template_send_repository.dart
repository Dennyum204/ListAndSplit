import 'package:list_and_split/features/templates/domain/template_send.dart';

enum TemplateSendFailureCode {
  invalid,
  unavailable,
  stale,
  retryConflict,
  capacity,
  noLongerPending,
  transport,
  generic,
}

class TemplateSendFailure implements Exception {
  const TemplateSendFailure(this.code);

  final TemplateSendFailureCode code;
}

abstract interface class TemplateSendRepository {
  Future<List<TemplateSendProfile>> listEligibleRecipients(
    String templateId, {
    int pageSize = 20,
    TemplateSendRecipientCursor? cursor,
  });

  Future<TemplateSendMutationResult> sendTemplate(
    String templateId,
    String recipientProfileId, {
    required int expectedTemplateVersion,
    required String requestId,
  });

  Future<List<ReceivedTemplateSendSummary>> listReceived({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  });

  Future<List<SentTemplateSendSummary>> listSent({
    TemplateSendHistoryFilter filter = TemplateSendHistoryFilter.pending,
    int pageSize = 20,
    TemplateSendCursor? cursor,
  });

  Future<ReceivedTemplateSendDetail> getReceived(String templateSendId);

  Future<TemplateSendMutationResult> accept(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  });

  Future<TemplateSendMutationResult> decline(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  });

  Future<TemplateSendMutationResult> revoke(
    String templateSendId, {
    required int expectedVersion,
    required String requestId,
  });
}
