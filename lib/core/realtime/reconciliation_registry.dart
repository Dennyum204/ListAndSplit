import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ReconciliationTask = Future<void> Function();

class ReconciliationRegistry {
  final Map<Object, ReconciliationTask> _tasks = {};

  void Function() register(ReconciliationTask task) {
    final registration = Object();
    _tasks[registration] = task;
    return () => _tasks.remove(registration);
  }

  Future<void> reconcile() async {
    final tasks = List<ReconciliationTask>.of(_tasks.values);
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
  ReconciliationTask task,
) {
  final unregister = ref.read(reconciliationRegistryProvider).register(task);
  ref.onDispose(unregister);
}
