import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_coordinator.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_providers.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/realtime/supabase_account_realtime_gateway.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

void main() {
  test('starts exactly one channel only for an active account', () async {
    final gateway = _FakeGateway();
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
    );

    coordinator.setAccount(null);
    await _flush();
    expect(gateway.subscriptions, isEmpty);

    coordinator.setAccount('account-a');
    await _flush();
    coordinator.setAccount('account-a');
    await _flush();
    expect(gateway.accountIds, ['account-a']);

    await coordinator.dispose();
    expect(gateway.subscriptions.single.closeCalls, 1);
  });

  test('removes the old account channel before starting the new one', () async {
    final gateway = _FakeGateway();
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
    );
    coordinator.setAccount('account-a');
    await _flush();
    final oldSubscription = gateway.subscriptions.single;
    oldSubscription.closeCompleter = Completer<void>();

    coordinator.setAccount('account-b');
    await _flush();
    expect(oldSubscription.closeCalls, 1);
    expect(gateway.accountIds, ['account-a']);

    oldSubscription.closeCompleter!.complete();
    await _flush();
    expect(gateway.accountIds, ['account-a', 'account-b']);
    await coordinator.dispose();
  });

  test('SUBSCRIBED and resume each reconcile authoritatively', () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    var reconciliations = 0;
    registry.register(() async => reconciliations += 1);
    final coordinator = AccountReconciliationCoordinator(gateway, registry);
    coordinator.setAccount('account-a');
    await _flush();

    gateway.subscriptions.single.emitStatus(AccountRealtimeStatus.subscribed);
    await _flush();
    expect(reconciliations, 1);

    coordinator.resume();
    await _flush();
    expect(reconciliations, 2);
    expect(gateway.subscriptions, hasLength(1));
    await coordinator.dispose();
  });

  test('burst invalidations coalesce to one dirty follow-up', () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    final firstPass = Completer<void>();
    var reconciliations = 0;
    registry.register(() async {
      reconciliations += 1;
      if (reconciliations == 1) await firstPass.future;
    });
    final coordinator = AccountReconciliationCoordinator(gateway, registry);
    coordinator.setAccount('account-a');
    await _flush();
    final subscription = gateway.subscriptions.single;

    subscription.emitInvalidation();
    await _flush();
    subscription.emitInvalidation();
    subscription.emitInvalidation();
    subscription.emitInvalidation();
    firstPass.complete();
    await _flush();

    expect(reconciliations, 2);
    await coordinator.dispose();
  });

  test('late events from an old account generation are ignored', () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    var reconciliations = 0;
    registry.register(() async => reconciliations += 1);
    final coordinator = AccountReconciliationCoordinator(gateway, registry);
    coordinator.setAccount('account-a');
    await _flush();
    final oldSubscription = gateway.subscriptions.single;

    coordinator.setAccount('account-b');
    await _flush();
    oldSubscription.emitInvalidation();
    oldSubscription.emitStatus(AccountRealtimeStatus.subscribed);
    await _flush();

    expect(reconciliations, 0);
    gateway.subscriptions.last.emitInvalidation();
    await _flush();
    expect(reconciliations, 1);
    await coordinator.dispose();
  });

  test('new-account join is reconciled after an old pass completes', () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    final oldPass = Completer<void>();
    var reconciliations = 0;
    registry.register(() async {
      reconciliations += 1;
      if (reconciliations == 1) await oldPass.future;
    });
    final coordinator = AccountReconciliationCoordinator(gateway, registry);
    coordinator.setAccount('account-a');
    await _flush();
    gateway.subscriptions.single.emitInvalidation();
    await _flush();

    coordinator.setAccount('account-b');
    await _flush();
    gateway.subscriptions.last.emitStatus(AccountRealtimeStatus.subscribed);
    oldPass.complete();
    await _flush();

    expect(reconciliations, 2);
    await coordinator.dispose();
  });

  test('repeated errors and timeout coalesce into one serialized replacement',
      () async {
    final gateway = _FakeGateway();
    final diagnostics = <AccountRealtimeDiagnostic>[];
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: Duration.zero,
      diagnosticSink: diagnostics.add,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final subscription = gateway.subscriptions.single;
    subscription.closeCompleter = Completer<void>();

    subscription.emitStatus(
      AccountRealtimeStatus.channelError,
      error: Exception('private error details must not escape'),
    );
    subscription.emitStatus(AccountRealtimeStatus.channelError);
    subscription.emitStatus(AccountRealtimeStatus.timedOut);
    await _flush();
    expect(gateway.subscriptions, hasLength(1));
    expect(subscription.closeCalls, 1);

    subscription.emitStatus(AccountRealtimeStatus.closed);
    await _flush();
    expect(gateway.subscriptions, hasLength(1));

    subscription.closeCompleter!.complete();
    await _flush();
    expect(gateway.subscriptions, hasLength(2));
    expect(gateway.accountIds, ['account-a', 'account-a']);
    expect(gateway.maximumOpenSubscriptions, 1);
    expect(
      diagnostics.map((diagnostic) => diagnostic.action),
      containsAllInOrder([
        AccountRealtimeRecoveryAction.recoveryScheduled,
        AccountRealtimeRecoveryAction.recoveryCoalesced,
        AccountRealtimeRecoveryAction.recoveryCoalesced,
      ]),
    );
    expect(
      diagnostics.first.update.errorReported,
      isTrue,
    );
    await coordinator.dispose();
  });

  test('resume recovers a joined non-null unhealthy subscription only once',
      () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    var reconciliations = 0;
    registry.register(() async => reconciliations += 1);
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      registry,
      closedChannelRetryDelay: const Duration(days: 1),
    );
    coordinator.setAccount('account-a');
    await _flush();
    final unhealthy = gateway.subscriptions.single;
    unhealthy.emitStatus(AccountRealtimeStatus.subscribed);
    await _flush();
    expect(reconciliations, 1);
    unhealthy.closeCompleter = Completer<void>();
    unhealthy.emitStatus(AccountRealtimeStatus.channelError);

    coordinator.resume();
    coordinator.resume();
    coordinator.setAccount('account-a');
    await _flush();

    expect(unhealthy.closeCalls, 1);
    expect(gateway.subscriptions, hasLength(1));
    expect(reconciliations, 2);

    unhealthy.closeCompleter!.complete();
    await _flush();

    expect(gateway.accountIds, ['account-a', 'account-a']);
    expect(gateway.subscriptions, hasLength(2));
    expect(gateway.maximumOpenSubscriptions, 1);
    final recovered = gateway.subscriptions.last;
    recovered.emitStatus(AccountRealtimeStatus.subscribed);
    await _flush();
    expect(reconciliations, 3);
    recovered.emitInvalidation();
    await _flush();
    expect(reconciliations, 4);
    await coordinator.dispose();
  });

  test('a successful SDK rejoin cancels a pending replacement', () async {
    final gateway = _FakeGateway();
    final diagnostics = <AccountRealtimeDiagnostic>[];
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: Duration.zero,
      diagnosticSink: diagnostics.add,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final subscription = gateway.subscriptions.single;

    subscription.emitStatus(AccountRealtimeStatus.channelError);
    subscription.emitStatus(AccountRealtimeStatus.subscribed);
    await _flush();

    expect(gateway.subscriptions, hasLength(1));
    expect(subscription.closeCalls, 0);
    expect(subscription.isOpen, isTrue);
    expect(
      diagnostics.last.action,
      AccountRealtimeRecoveryAction.recoveryCancelled,
    );
    await coordinator.dispose();
  });

  test('account switch wins while unhealthy-channel teardown is serialized',
      () async {
    final gateway = _FakeGateway();
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: Duration.zero,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final oldSubscription = gateway.subscriptions.single;
    oldSubscription.closeCompleter = Completer<void>();
    oldSubscription.emitStatus(AccountRealtimeStatus.channelError);
    await _flush();
    expect(oldSubscription.closeCalls, 1);

    coordinator.setAccount('account-b');
    coordinator.resume();
    await _flush();
    expect(gateway.accountIds, ['account-a']);

    oldSubscription.closeCompleter!.complete();
    await _flush();

    expect(gateway.accountIds, ['account-a', 'account-b']);
    expect(gateway.maximumOpenSubscriptions, 1);
    expect(coordinator.activeAccountId, 'account-b');
    await coordinator.dispose();
  });

  test('failed teardown is retried before a replacement channel is created',
      () async {
    final gateway = _FakeGateway();
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: Duration.zero,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final unhealthy = gateway.subscriptions.single;
    unhealthy.closeFailuresRemaining = 1;

    unhealthy.emitStatus(AccountRealtimeStatus.channelError);
    await _flush();
    await _flush();

    expect(unhealthy.closeCalls, 2);
    expect(gateway.subscriptions, hasLength(2));
    expect(gateway.maximumOpenSubscriptions, 1);
    await coordinator.dispose();
  });

  test('diagnostics contain status and action but no transport error values',
      () async {
    final gateway = _FakeGateway();
    final messages = <String>[];
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: const Duration(days: 1),
      diagnosticSink: (diagnostic) => messages.add(diagnostic.message),
    );
    coordinator.setAccount('account-a');
    await _flush();

    const jwt = 'jwt-secret-value';
    const topic = 'account:private-profile-id';
    const payload = '{"amount_minor":12345}';
    gateway.subscriptions.single.emitStatus(
      AccountRealtimeStatus.channelError,
      error: Exception('$jwt $topic $payload'),
    );
    await _flush();

    expect(messages, hasLength(1));
    expect(messages.single, contains('status=channelError'));
    expect(messages.single, contains('error=reported'));
    expect(messages.single, contains('action=recoveryScheduled'));
    for (final privateValue in [jwt, topic, payload, '12345']) {
      expect(messages.single, isNot(contains(privateValue)));
    }
    await coordinator.dispose();
  });

  test('event during the follow-up remains bounded and is not lost', () async {
    final gateway = _FakeGateway();
    final registry = ReconciliationRegistry();
    final first = Completer<void>();
    final second = Completer<void>();
    var reconciliations = 0;
    registry.register(() async {
      reconciliations += 1;
      if (reconciliations == 1) await first.future;
      if (reconciliations == 2) await second.future;
    });
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      registry,
      burstCooldown: Duration.zero,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final subscription = gateway.subscriptions.single;

    subscription.emitInvalidation();
    await _flush();
    subscription.emitInvalidation();
    first.complete();
    await _flush();
    subscription.emitInvalidation();
    second.complete();
    await _flush();

    expect(reconciliations, 3);
    await coordinator.dispose();
  });

  test('provider gates channels on matching completed account identity',
      () async {
    final authenticatedId = StateProvider<String?>((ref) => null);
    final profile = StateProvider<UserProfile?>((ref) => null);
    final gateway = _FakeGateway();
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWith(
          (ref) => ref.watch(authenticatedId),
        ),
        ownProfileProvider.overrideWith(
          (ref) async => ref.watch(profile),
        ),
        accountRealtimeGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    container.read(accountReconciliationCoordinatorProvider);

    container.read(authenticatedId.notifier).state = 'account-a';
    container.read(profile.notifier).state = const UserProfile(
      id: 'account-a',
      username: null,
      displayName: null,
      onboardingCompletedAt: null,
    );
    await container.pump();
    expect(gateway.subscriptions, isEmpty);

    container.read(profile.notifier).state = UserProfile(
      id: 'account-a',
      username: 'account_a',
      displayName: 'Account A',
      onboardingCompletedAt: DateTime.utc(2026, 7, 21),
    );
    await container.pump();
    await _flush();
    expect(gateway.accountIds, ['account-a']);

    container.read(authenticatedId.notifier).state = 'account-b';
    await container.pump();
    await _flush();
    expect(gateway.subscriptions.first.closeCalls, 1);
    expect(gateway.accountIds, ['account-a']);

    container.read(profile.notifier).state = UserProfile(
      id: 'account-b',
      username: 'account_b',
      displayName: 'Account B',
      onboardingCompletedAt: DateTime.utc(2026, 7, 21),
    );
    await container.pump();
    await _flush();
    expect(gateway.accountIds, ['account-a', 'account-b']);

    container.read(authenticatedId.notifier).state = null;
    await container.pump();
    await _flush();
    expect(gateway.subscriptions.last.closeCalls, 1);
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeGateway implements AccountRealtimeGateway {
  final List<String> accountIds = [];
  final List<_FakeSubscription> subscriptions = [];
  int openSubscriptions = 0;
  int maximumOpenSubscriptions = 0;

  @override
  AccountRealtimeSubscription subscribe({
    required String authenticatedProfileId,
    required void Function() onInvalidation,
    required void Function(AccountRealtimeStatusUpdate update) onStatus,
  }) {
    accountIds.add(authenticatedProfileId);
    openSubscriptions += 1;
    if (openSubscriptions > maximumOpenSubscriptions) {
      maximumOpenSubscriptions = openSubscriptions;
    }
    late final _FakeSubscription subscription;
    subscription = _FakeSubscription(
      onInvalidation,
      onStatus,
      () => openSubscriptions -= 1,
    );
    subscriptions.add(subscription);
    return subscription;
  }
}

class _FakeSubscription implements AccountRealtimeSubscription {
  _FakeSubscription(this._onInvalidation, this._onStatus, this._onClosed);

  final void Function() _onInvalidation;
  final void Function(AccountRealtimeStatusUpdate update) _onStatus;
  final void Function() _onClosed;
  Completer<void>? closeCompleter;
  int closeFailuresRemaining = 0;
  int closeCalls = 0;
  bool isOpen = true;

  void emitInvalidation() => _onInvalidation();

  void emitStatus(AccountRealtimeStatus status, {Object? error}) => _onStatus(
        AccountRealtimeStatusUpdate.fromTransport(status, error: error),
      );

  @override
  Future<void> close() async {
    closeCalls += 1;
    await closeCompleter?.future;
    if (closeFailuresRemaining > 0) {
      closeFailuresRemaining -= 1;
      throw StateError('private close failure');
    }
    if (isOpen) {
      isOpen = false;
      _onClosed();
    }
  }
}
