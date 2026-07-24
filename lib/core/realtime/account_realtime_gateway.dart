const accountInvalidationEvent = 'invalidate';

const accountInvalidationPayload = <String, Object>{'v': 1};

String accountRealtimeTopic(String authenticatedProfileId) =>
    'account:$authenticatedProfileId';

bool isAccountInvalidationEnvelope(Map<String, dynamic> envelope) {
  final payload = envelope['payload'];
  if (payload is Map) {
    final applicationPayload = Map<Object?, Object?>.of(payload);
    final transportId = applicationPayload.remove('id');
    if (transportId != null &&
        (transportId is! String || !_uuidPattern.hasMatch(transportId))) {
      return false;
    }
    final meta = envelope['meta'];
    if (transportId != null &&
        meta is Map &&
        meta['id'] != null &&
        meta['id'] != transportId) {
      return false;
    }
    return applicationPayload.length == 1 && applicationPayload['v'] == 1;
  }

  // The pinned local Realtime transport exposes the database-generated message
  // UUID beside the application payload, while the current wire protocol places
  // it in `meta`. It is transport metadata: validate and discard it, and never
  // expose it as application/domain data.
  final directPayload = Map<String, dynamic>.of(envelope);
  final transportId = directPayload.remove('id');
  if (transportId is! String || !_uuidPattern.hasMatch(transportId)) {
    return false;
  }
  return directPayload.length == 1 && directPayload['v'] == 1;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

enum AccountRealtimeStatus { subscribed, channelError, timedOut, closed }

final class AccountRealtimeStatusUpdate {
  const AccountRealtimeStatusUpdate({
    required this.status,
    required this.errorReported,
  });

  factory AccountRealtimeStatusUpdate.fromTransport(
    AccountRealtimeStatus status, {
    Object? error,
  }) =>
      AccountRealtimeStatusUpdate(
        status: status,
        errorReported: error != null,
      );

  final AccountRealtimeStatus status;
  final bool errorReported;

  @override
  String toString() => 'AccountRealtimeStatusUpdate('
      'status: ${status.name}, '
      'errorReported: $errorReported'
      ')';
}

enum AccountRealtimeRecoveryAction {
  reconciliationRequested,
  recoveryScheduled,
  recoveryCoalesced,
  recoveryCancelled,
}

final class AccountRealtimeDiagnostic {
  const AccountRealtimeDiagnostic({
    required this.update,
    required this.action,
  });

  final AccountRealtimeStatusUpdate update;
  final AccountRealtimeRecoveryAction action;

  String get message => '[account-realtime] '
      'status=${update.status.name} '
      'error=${update.errorReported ? 'reported' : 'none'} '
      'action=${action.name}';

  @override
  String toString() => message;
}

typedef AccountRealtimeDiagnosticSink = void Function(
  AccountRealtimeDiagnostic diagnostic,
);

abstract interface class AccountRealtimeSubscription {
  Future<void> close();
}

abstract interface class AccountRealtimeGateway {
  AccountRealtimeSubscription subscribe({
    required String authenticatedProfileId,
    required void Function() onInvalidation,
    required void Function(AccountRealtimeStatusUpdate update) onStatus,
  });
}
