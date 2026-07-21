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

  test('errors rely on SDK retry and unexpected close is replaced once',
      () async {
    final gateway = _FakeGateway();
    final coordinator = AccountReconciliationCoordinator(
      gateway,
      ReconciliationRegistry(),
      closedChannelRetryDelay: Duration.zero,
    );
    coordinator.setAccount('account-a');
    await _flush();
    final subscription = gateway.subscriptions.single;

    subscription.emitStatus(AccountRealtimeStatus.channelError);
    subscription.emitStatus(AccountRealtimeStatus.timedOut);
    await _flush();
    expect(gateway.subscriptions, hasLength(1));

    subscription.emitStatus(AccountRealtimeStatus.closed);
    await _flush();
    expect(subscription.closeCalls, 1);
    expect(gateway.subscriptions, hasLength(2));
    expect(gateway.accountIds, ['account-a', 'account-a']);
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

  @override
  AccountRealtimeSubscription subscribe({
    required String authenticatedProfileId,
    required void Function() onInvalidation,
    required void Function(AccountRealtimeStatus status) onStatus,
  }) {
    accountIds.add(authenticatedProfileId);
    final subscription = _FakeSubscription(onInvalidation, onStatus);
    subscriptions.add(subscription);
    return subscription;
  }
}

class _FakeSubscription implements AccountRealtimeSubscription {
  _FakeSubscription(this._onInvalidation, this._onStatus);

  final void Function() _onInvalidation;
  final void Function(AccountRealtimeStatus status) _onStatus;
  Completer<void>? closeCompleter;
  int closeCalls = 0;

  void emitInvalidation() => _onInvalidation();

  void emitStatus(AccountRealtimeStatus status) => _onStatus(status);

  @override
  Future<void> close() async {
    closeCalls += 1;
    await closeCompleter?.future;
  }
}
