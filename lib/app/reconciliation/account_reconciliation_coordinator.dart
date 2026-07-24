import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';

class AccountReconciliationCoordinator {
  AccountReconciliationCoordinator(
    this._gateway,
    this._registry, {
    Duration closedChannelRetryDelay = const Duration(seconds: 1),
    Duration burstCooldown = const Duration(milliseconds: 250),
    AccountRealtimeDiagnosticSink diagnosticSink =
        _debugPrintAccountRealtimeDiagnostic,
  })  : _closedChannelRetryDelay = closedChannelRetryDelay,
        _burstCooldown = burstCooldown,
        _diagnosticSink = diagnosticSink;

  final AccountRealtimeGateway _gateway;
  final ReconciliationRegistry _registry;
  final Duration _closedChannelRetryDelay;
  final Duration _burstCooldown;
  final AccountRealtimeDiagnosticSink _diagnosticSink;

  String? _desiredAccountId;
  String? _activeAccountId;
  AccountRealtimeSubscription? _subscription;
  Timer? _restartTimer;
  Timer? _burstTimer;
  Future<void>? _transitionFuture;
  var _restartRequested = false;
  var _subscriptionUnhealthy = false;
  var _resumeReconciledDuringRecovery = false;
  var _reconciliationRunning = false;
  var _dirtyAgain = false;
  var _generation = 0;
  var _disposed = false;

  String? get activeAccountId => _activeAccountId;

  void setAccount(String? authenticatedProfileId) {
    if (_disposed) return;
    if (_desiredAccountId == authenticatedProfileId) {
      if (authenticatedProfileId != null &&
          (_subscription == null || _subscriptionUnhealthy)) {
        _requestImmediateRecovery();
      }
      return;
    }
    _desiredAccountId = authenticatedProfileId;
    _restartTimer?.cancel();
    _restartRequested = false;
    _ensureTransitionDrain();
  }

  void resume() {
    if (_disposed || _activeAccountId == null) return;
    final needsRecovery = _subscription == null || _subscriptionUnhealthy;
    if (!needsRecovery || !_resumeReconciledDuringRecovery) {
      _requestReconciliation(_generation);
    }
    if (needsRecovery) {
      _resumeReconciledDuringRecovery = true;
      _requestImmediateRecovery();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _desiredAccountId = null;
    _restartTimer?.cancel();
    _burstTimer?.cancel();
    _restartRequested = false;
    _subscriptionUnhealthy = false;
    _resumeReconciledDuringRecovery = false;
    ++_generation;
    final transition = _transitionFuture;
    if (transition != null) await transition;
    final subscription = _subscription;
    _subscription = null;
    _activeAccountId = null;
    if (subscription != null) await subscription.close();
  }

  void _ensureTransitionDrain() {
    if (_disposed || _transitionFuture != null || !_needsTransition) return;
    final transition = _drainAccountTransitions();
    _transitionFuture = transition;
    unawaited(
      transition.whenComplete(() {
        if (identical(_transitionFuture, transition)) {
          _transitionFuture = null;
        }
        if (!_disposed && _restartTimer?.isActive != true && _needsTransition) {
          _ensureTransitionDrain();
        }
      }),
    );
  }

  Future<void> _drainAccountTransitions() async {
    while (!_disposed && _needsTransition) {
      final accountChanged = _activeAccountId != _desiredAccountId;
      _restartTimer?.cancel();
      _restartRequested = false;
      if (accountChanged) {
        _restartTimer?.cancel();
        _burstTimer?.cancel();
        _dirtyAgain = false;
        _resumeReconciledDuringRecovery = false;
        _activeAccountId = null;
      }

      final generation = ++_generation;
      final oldSubscription = _subscription;
      _subscription = null;
      _subscriptionUnhealthy = false;
      if (oldSubscription != null) {
        try {
          await oldSubscription.close();
        } catch (_) {
          _subscription = oldSubscription;
          _markSubscriptionUnhealthy();
          if (_disposed) return;
          _emitDiagnostic(
            const AccountRealtimeStatusUpdate(
              status: AccountRealtimeStatus.channelError,
              errorReported: true,
            ),
            AccountRealtimeRecoveryAction.recoveryScheduled,
          );
          _scheduleTransitionRetry();
          return;
        }
      }
      if (_disposed) return;

      final accountId = _desiredAccountId;
      if (accountId == null) {
        _activeAccountId = null;
        continue;
      }
      _activeAccountId = accountId;
      try {
        _subscription = _gateway.subscribe(
          authenticatedProfileId: accountId,
          onInvalidation: () => _requestReconciliation(generation),
          onStatus: (update) => _handleStatus(generation, update),
        );
      } catch (_) {
        _markSubscriptionUnhealthy();
        _emitDiagnostic(
          const AccountRealtimeStatusUpdate(
            status: AccountRealtimeStatus.channelError,
            errorReported: true,
          ),
          AccountRealtimeRecoveryAction.recoveryScheduled,
        );
        _scheduleTransitionRetry();
        return;
      }
    }
  }

  void _handleStatus(int generation, AccountRealtimeStatusUpdate update) {
    if (!_isCurrent(generation)) return;
    switch (update.status) {
      case AccountRealtimeStatus.subscribed:
        final recoveryCancelled =
            _restartTimer?.isActive == true || _restartRequested;
        _restartTimer?.cancel();
        _restartRequested = false;
        _subscriptionUnhealthy = false;
        _resumeReconciledDuringRecovery = false;
        _emitDiagnostic(
          update,
          recoveryCancelled
              ? AccountRealtimeRecoveryAction.recoveryCancelled
              : AccountRealtimeRecoveryAction.reconciliationRequested,
        );
        _requestReconciliation(generation);
      case AccountRealtimeStatus.closed:
      case AccountRealtimeStatus.channelError:
      case AccountRealtimeStatus.timedOut:
        _markSubscriptionUnhealthy();
        final action = _scheduleChannelRecovery(generation);
        _emitDiagnostic(update, action);
    }
  }

  AccountRealtimeRecoveryAction _scheduleChannelRecovery(int generation) {
    if (!_isCurrent(generation) ||
        _restartRequested ||
        _restartTimer?.isActive == true) {
      return AccountRealtimeRecoveryAction.recoveryCoalesced;
    }
    _restartTimer = Timer(_closedChannelRetryDelay, () {
      if (!_isCurrent(generation) || !_subscriptionUnhealthy) return;
      _restartRequested = true;
      _ensureTransitionDrain();
    });
    return AccountRealtimeRecoveryAction.recoveryScheduled;
  }

  void _requestImmediateRecovery() {
    if (_disposed ||
        _activeAccountId == null ||
        _activeAccountId != _desiredAccountId ||
        _transitionFuture != null ||
        _restartRequested) {
      return;
    }
    _restartTimer?.cancel();
    _restartRequested = true;
    _ensureTransitionDrain();
  }

  void _scheduleTransitionRetry() {
    if (_disposed || _restartTimer?.isActive == true) return;
    _restartTimer = Timer(_closedChannelRetryDelay, () {
      if (_disposed) return;
      _restartRequested = true;
      _ensureTransitionDrain();
    });
  }

  void _emitDiagnostic(
    AccountRealtimeStatusUpdate update,
    AccountRealtimeRecoveryAction action,
  ) {
    _diagnosticSink(
      AccountRealtimeDiagnostic(update: update, action: action),
    );
  }

  void _markSubscriptionUnhealthy() {
    if (!_subscriptionUnhealthy) {
      _resumeReconciledDuringRecovery = false;
    }
    _subscriptionUnhealthy = true;
  }

  void _requestReconciliation(int generation) {
    if (!_isCurrent(generation)) return;
    if (_reconciliationRunning) {
      _dirtyAgain = true;
      return;
    }
    unawaited(_runReconciliationBurst(generation));
  }

  Future<void> _runReconciliationBurst(int generation) async {
    if (_reconciliationRunning || !_isCurrent(generation)) return;
    _reconciliationRunning = true;
    var passes = 0;
    try {
      do {
        _dirtyAgain = false;
        await _registry.reconcile();
        passes += 1;
      } while (_isCurrent(generation) && _dirtyAgain && passes < 2);
    } finally {
      _reconciliationRunning = false;
    }
    if (!_isCurrent(generation) && _dirtyAgain && !_disposed) {
      _dirtyAgain = false;
      _requestReconciliation(_generation);
      return;
    }
    if (_isCurrent(generation) && _dirtyAgain) {
      _dirtyAgain = false;
      _burstTimer?.cancel();
      _burstTimer = Timer(
        _burstCooldown,
        () => _requestReconciliation(generation),
      );
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed &&
      generation == _generation &&
      _activeAccountId != null &&
      _activeAccountId == _desiredAccountId;

  bool get _needsTransition =>
      _activeAccountId != _desiredAccountId ||
      (_activeAccountId != null &&
          _activeAccountId == _desiredAccountId &&
          (_subscription == null || _restartRequested));
}

void _debugPrintAccountRealtimeDiagnostic(
  AccountRealtimeDiagnostic diagnostic,
) {
  debugPrint(diagnostic.message);
}
