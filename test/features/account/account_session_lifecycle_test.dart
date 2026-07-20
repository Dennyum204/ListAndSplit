import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:list_and_split/features/account/presentation/account_deletion_providers.dart';
import 'package:list_and_split/features/account/presentation/account_session_lifecycle.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('resume signs out an authoritatively deleted account',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..validationResult = AuthoritativeAccountState.missing;
    await _pumpLifecycle(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.validationCalls, 1);
    expect(repository.clearSessionCalls, 1);
  });

  testWidgets('resume preserves the session after an offline validation',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..validationResult = AuthoritativeAccountState.transientFailure;
    await _pumpLifecycle(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.validationCalls, 1);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets('resume signs out an authoritatively invalid session',
      (tester) async {
    final repository = FakeAccountDeletionRepository()
      ..validationResult = AuthoritativeAccountState.invalidSession;
    await _pumpLifecycle(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.clearSessionCalls, 1);
  });

  testWidgets('overlapping resume events share one validation boundary',
      (tester) async {
    final completer = Completer<AuthoritativeAccountState>();
    final repository = FakeAccountDeletionRepository()
      ..validationCompleter = completer;
    await _pumpLifecycle(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.validationCalls, 1);

    completer.complete(AuthoritativeAccountState.valid);
    await tester.pumpAndSettle();
    expect(repository.clearSessionCalls, 0);
  });
}

Future<void> _pumpLifecycle(
  WidgetTester tester,
  FakeAccountDeletionRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.configured(),
        ),
        authSessionProvider
            .overrideWith((ref) => Stream.value(verifiedSession)),
        accountDeletionRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: AccountSessionLifecycle(child: SizedBox()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
