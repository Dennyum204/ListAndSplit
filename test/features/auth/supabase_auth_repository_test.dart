import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/auth/data/password_recovery_marker.dart';
import 'package:list_and_split/features/auth/data/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('http://localhost:54321', 'test-anon-key');
  });

  test('auth stream errors preserve the session and later events continue',
      () async {
    final authStates = StreamController<AuthState>();
    final repository = SupabaseAuthRepository(
      client,
      _MemoryRecoveryMarker(),
      authStateChanges: authStates.stream,
    );
    final session = _session();
    final statesFuture = repository.observeSession().take(3).toList();

    authStates.add(AuthState(AuthChangeEvent.initialSession, session));
    authStates.addError(StateError('transient refresh failure'));
    authStates.add(AuthState(AuthChangeEvent.tokenRefreshed, session));
    await authStates.close();

    final states = await statesFuture;
    expect(states, hasLength(3));
    expect(states.map((state) => state.user?.id), everyElement('user-1'));
  });

  test('marker failures still surface from session observation', () async {
    final authStates = StreamController<AuthState>();
    final repository = SupabaseAuthRepository(
      client,
      _FailingRecoveryMarker(),
      authStateChanges: authStates.stream,
    );

    final expectation = expectLater(
      repository.observeSession(),
      emitsError(isA<StateError>()),
    );
    authStates.add(AuthState(AuthChangeEvent.initialSession, _session()));

    await expectation;
    await authStates.close();
  });
}

Session _session() => Session(
      accessToken: 'not-a-real-token',
      tokenType: 'bearer',
      user: const User(
        id: 'user-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        email: 'person@example.com',
        emailConfirmedAt: '2026-07-18T00:00:00Z',
        createdAt: '2026-07-18T00:00:00Z',
      ),
    );

class _MemoryRecoveryMarker implements PasswordRecoveryMarker {
  var value = false;

  @override
  Future<bool> read() async => value;

  @override
  Future<void> write(bool isPending) async => value = isPending;
}

class _FailingRecoveryMarker implements PasswordRecoveryMarker {
  @override
  Future<bool> read() => Future.error(StateError('storage unavailable'));

  @override
  Future<void> write(bool isPending) async {}
}
