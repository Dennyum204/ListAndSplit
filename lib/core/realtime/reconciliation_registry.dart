import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ReconciliationTask = Future<void> Function();

enum ReconciliationScope {
  chat,
  full,
}

class ReconciliationRegistry {
  final Map<Object, ({ReconciliationScope scope, ReconciliationTask task})>
      _tasks = {};

  void Function() register(
    ReconciliationTask task, {
    ReconciliationScope scope = ReconciliationScope.full,
  }) {
    final registration = Object();
    _tasks[registration] = (scope: scope, task: task);
    return () => _tasks.remove(registration);
  }

  Future<void> reconcile({
    ReconciliationScope scope = ReconciliationScope.full,
  }) async {
    final tasks = _tasks.values
        .where(
          (registration) =>
              scope == ReconciliationScope.full ||
              registration.scope == ReconciliationScope.chat,
        )
        .map((registration) => registration.task)
        .toList(growable: false);
    await Future.wait(tasks.map(_runSafely));
  }

  Future<void> _runSafely(ReconciliationTask task) async {
    try {
      await task();
    } catch (_) {
      // One transient repository failure must not prevent other projections
      // from reconciling. Each feature preserves its cached state and remains
      // manually refreshable.
    }
  }
}

final reconciliationRegistryProvider = Provider<ReconciliationRegistry>(
  (ref) => ReconciliationRegistry(),
);

void registerForReconciliation(
  Ref<Object?> ref,
  ReconciliationTask task, {
  ReconciliationScope scope = ReconciliationScope.full,
}) {
  final unregister =
      ref.read(reconciliationRegistryProvider).register(task, scope: scope);
  ref.onDispose(unregister);
}
