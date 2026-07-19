import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/data/supabase_account_deletion_repository.dart';
import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late AccountDeletionSessionIdentity? activeSession;
  late List<String> events;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'public-key');
    activeSession = const AccountDeletionSessionIdentity(
      userId: 'user-1',
      accessToken: 'old-session',
    );
    events = [];
  });

  tearDown(() => client.dispose());

  test('forwards credentials unchanged and invokes with confirmation only',
      () async {
    String? receivedEmail;
    String? receivedPassword;
    String? receivedConfirmation;
    final repository = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (email, password) async {
        events.add('reauthenticate');
        receivedEmail = email;
        receivedPassword = password;
        activeSession = const AccountDeletionSessionIdentity(
          userId: 'user-1',
          accessToken: 'new-session',
        );
        return activeSession;
      },
      invokeDeletion: (confirmation) async {
        events.add('delete');
        receivedConfirmation = confirmation;
        expect(activeSession?.accessToken, 'new-session');
      },
      getUser: () async => 'user-1',
      localSignOut: () async {},
    );

    await repository.deleteOwnAccount(
      email: 'Exact.Email@example.com',
      password: ' Pass Word ',
      confirmation: ' Exact_Name ',
    );

    expect(events, ['reauthenticate', 'delete']);
    expect(receivedEmail, 'Exact.Email@example.com');
    expect(receivedPassword, ' Pass Word ');
    expect(receivedConfirmation, ' Exact_Name ');
  });

  test('wrong password prevents deletion invocation', () async {
    var invokeCalls = 0;
    final repository = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (_, __) => throw AuthApiException(
        'private details',
        statusCode: '400',
        code: 'invalid_credentials',
      ),
      invokeDeletion: (_) async => invokeCalls += 1,
      getUser: () async => 'user-1',
      localSignOut: () async {},
    );

    await expectLater(
      repository.deleteOwnAccount(
        email: 'person@example.com',
        password: 'wrong',
        confirmation: 'person',
      ),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.wrongPassword,
        ),
      ),
    );
    expect(invokeCalls, 0);
  });

  test('offline reauthentication preserves the current local session',
      () async {
    var invokeCalls = 0;
    var localSignOutCalls = 0;
    final repository = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (_, __) => throw AuthRetryableFetchException(),
      invokeDeletion: (_) async => invokeCalls += 1,
      getUser: () async => 'user-1',
      localSignOut: () async => localSignOutCalls += 1,
    );

    await expectLater(
      _delete(repository),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.offline,
        ),
      ),
    );
    expect(invokeCalls, 0);
    expect(localSignOutCalls, 0);
  });

  test('requires the newly returned session to be active', () async {
    var invokeCalls = 0;
    final repository = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (_, __) async => const AccountDeletionSessionIdentity(
        userId: 'user-1',
        accessToken: 'new-session-not-active',
      ),
      invokeDeletion: (_) async => invokeCalls += 1,
      getUser: () async => 'user-1',
      localSignOut: () async {},
    );

    await expectLater(
      repository.deleteOwnAccount(
        email: 'person@example.com',
        password: 'password',
        confirmation: 'person',
      ),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.reauthenticationRequired,
        ),
      ),
    );
    expect(invokeCalls, 0);
  });

  for (final entry in <int, AccountDeletionFailureCode>{
    409: AccountDeletionFailureCode.reauthenticationRequired,
    422: AccountDeletionFailureCode.confirmationMismatch,
    503: AccountDeletionFailureCode.retryable,
  }.entries) {
    test('maps function status ${entry.key} to ${entry.value.name}', () async {
      final repository = _readyRepository(
        client,
        activeSession: () => activeSession,
        setActiveSession: (session) => activeSession = session,
        invokeDeletion: (_) => throw FunctionException(
          status: entry.key,
          details: const {'private': 'not exposed'},
        ),
        getUser: () async => 'user-1',
      );

      await expectLater(
        _delete(repository),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (failure) => failure.code,
            'code',
            entry.value,
          ),
        ),
      );
    });
  }

  test('lost response reconciles an authoritatively deleted user as success',
      () async {
    final repository = _readyRepository(
      client,
      activeSession: () => activeSession,
      setActiveSession: (session) => activeSession = session,
      invokeDeletion: (_) => throw StateError('connection lost'),
      getUser: () => throw AuthApiException(
        'private details',
        statusCode: '401',
        code: 'user_not_found',
      ),
    );

    await expectLater(_delete(repository), completes);
  });

  test('lost response keeps an existing account retryable', () async {
    final repository = _readyRepository(
      client,
      activeSession: () => activeSession,
      setActiveSession: (session) => activeSession = session,
      invokeDeletion: (_) => throw StateError('connection lost'),
      getUser: () async => 'user-1',
    );

    await expectLater(
      _delete(repository),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.retryable,
        ),
      ),
    );
  });

  test('lost response never claims success for only an invalid session',
      () async {
    final repository = _readyRepository(
      client,
      activeSession: () => activeSession,
      setActiveSession: (session) => activeSession = session,
      invokeDeletion: (_) => throw StateError('connection lost'),
      getUser: () => throw AuthApiException(
        'private details',
        statusCode: '401',
        code: 'session_not_found',
      ),
    );

    await expectLater(
      _delete(repository),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.reauthenticationRequired,
        ),
      ),
    );
  });

  test('offline reconciliation preserves uncertainty and the local session',
      () async {
    var localSignOutCalls = 0;
    final repository = _readyRepository(
      client,
      activeSession: () => activeSession,
      setActiveSession: (session) => activeSession = session,
      invokeDeletion: (_) => throw StateError('connection lost'),
      getUser: () => throw AuthRetryableFetchException(),
      localSignOut: () async => localSignOutCalls += 1,
    );

    await expectLater(
      _delete(repository),
      throwsA(
        isA<AccountDeletionFailure>().having(
          (failure) => failure.code,
          'code',
          AccountDeletionFailureCode.offline,
        ),
      ),
    );
    expect(localSignOutCalls, 0);
  });

  test('authoritative validation distinguishes invalid and transient sessions',
      () async {
    final invalid = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (_, __) async => activeSession,
      invokeDeletion: (_) async {},
      getUser: () => throw AuthApiException(
        'private details',
        statusCode: '401',
        code: 'session_not_found',
      ),
      localSignOut: () async {},
    );
    expect(
      await invalid.validateCurrentAccount(),
      AuthoritativeAccountState.invalidSession,
    );

    final transient = SupabaseAccountDeletionRepository(
      client,
      currentSession: () => activeSession,
      reauthenticate: (_, __) async => activeSession,
      invokeDeletion: (_) async {},
      getUser: () => throw StateError('offline'),
      localSignOut: () async {},
    );
    expect(
      await transient.validateCurrentAccount(),
      AuthoritativeAccountState.transientFailure,
    );
  });
}

SupabaseAccountDeletionRepository _readyRepository(
  SupabaseClient client, {
  required AccountDeletionCurrentSession activeSession,
  required void Function(AccountDeletionSessionIdentity session)
      setActiveSession,
  required AccountDeletionFunctionInvoke invokeDeletion,
  required AccountDeletionGetUser getUser,
  AccountDeletionLocalSignOut? localSignOut,
}) {
  return SupabaseAccountDeletionRepository(
    client,
    currentSession: activeSession,
    reauthenticate: (_, __) async {
      const session = AccountDeletionSessionIdentity(
        userId: 'user-1',
        accessToken: 'new-session',
      );
      setActiveSession(session);
      return session;
    },
    invokeDeletion: invokeDeletion,
    getUser: getUser,
    localSignOut: localSignOut ?? () async {},
  );
}

Future<void> _delete(AccountDeletionRepository repository) {
  return repository.deleteOwnAccount(
    email: 'person@example.com',
    password: 'password',
    confirmation: 'person',
  );
}
