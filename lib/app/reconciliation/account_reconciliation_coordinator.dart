import 'dart:async';

import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';

class AccountReconciliationCoordinator {
  AccountReconciliationCoordinator(
    this._gateway,
    this._registry, {
    Duration closedChannelRetryDelay = const Duration(seconds: 1),
    Duration burstCooldown = const Duration(milliseconds: 250),
  })  : _closedChannelRetryDelay = closedChannelRetryDelay,
        _burstCooldown = burstCooldown;

  final AccountRealtimeGateway _gateway;
  final ReconciliationRegistry _registry;
  final Duration _closedChannelRetryDelay;
  final Duration _burstCooldown;

  String? _desiredAccountId;
  String? _activeAccountId;
  AccountRealtimeSubscription? _subscription;
  Timer? _restartTimer;
  Timer? _burstTimer;
  var _transitionRunning = false;
  var _reconciliationRunning = false;
  var _dirtyAgain = false;
  var _generation = 0;
  var _disposed = false;

  String? get activeAccountId => _activeAccountId;

  void setAccount(String? authenticatedProfileId) {
    if (_disposed || _desiredAccountId == authenticatedProfileId) return;
    _desiredAccountId = authenticatedProfileId;
    unawaited(_drainAccountTransition());
  }

  void resume() {
    if (_disposed || _activeAccountId == null) return;
    _requestReconciliation(_generation);
    if (_subscription == null) _scheduleClosedChannelRestart(_generation);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _desiredAccountId = null;
    _restartTimer?.cancel();
    _burstTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    _activeAccountId = null;
    ++_generation;
    if (subscription != null) await subscription.close();
  }

  Future<void> _drainAccountTransition() async {
    if (_transitionRunning || _disposed) return;
    _transitionRunning = true;
    try {
      while (!_disposed && _activeAccountId != _desiredAccountId) {
        _restartTimer?.cancel();
        _burstTimer?.cancel();
        _dirtyAgain = false;
        final generation = ++_generation;
        final oldSubscription = _subscription;
        _subscription = null;
        _activeAccountId = null;
        if (oldSubscription != null) await oldSubscription.close();
        if (_disposed) return;

        final accountId = _desiredAccountId;
        if (accountId == null) continue;
        _activeAccountId = accountId;
        _subscription = _gateway.subscribe(
          authenticatedProfileId: accountId,
          onInvalidation: () => _requestReconciliation(generation),
          onStatus: (status) => _handleStatus(generation, status),
        );
      }
    } finally {
      _transitionRunning = false;
      if (!_disposed && _activeAccountId != _desiredAccountId) {
        unawaited(_drainAccountTransition());
      }
    }
  }

  void _handleStatus(int generation, AccountRealtimeStatus status) {
    if (!_isCurrent(generation)) return;
    switch (status) {
      case AccountRealtimeStatus.subscribed:
        _requestReconciliation(generation);
      case AccountRealtimeStatus.closed:
        final closedSubscription = _subscription;
        _subscription = null;
        if (closedSubscription != null) {
          unawaited(closedSubscription.close());
        }
        _scheduleClosedChannelRestart(generation);
      case AccountRealtimeStatus.channelError:
      case AccountRealtimeStatus.timedOut:
        // The pinned Realtime client retries channel errors/timeouts itself.
        // Cached state remains usable while resume/manual refresh stay available.
        break;
    }
  }

  void _scheduleClosedChannelRestart(int generation) {
    if (!_isCurrent(generation) || _restartTimer?.isActive == true) return;
    _restartTimer = Timer(_closedChannelRetryDelay, () {
      if (!_isCurrent(generation) || _subscription != null) return;
      final accountId = _activeAccountId;
      if (accountId == null) return;
      final replacementGeneration = ++_generation;
      _subscription = _gateway.subscribe(
        authenticatedProfileId: accountId,
        onInvalidation: () => _requestReconciliation(replacementGeneration),
        onStatus: (status) => _handleStatus(replacementGeneration, status),
      );
    });
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
}
