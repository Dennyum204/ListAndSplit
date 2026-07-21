import 'package:list_and_split/features/account/domain/account_deletion_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionSessionIdentity {
  const AccountDeletionSessionIdentity({
    required this.userId,
    required this.accessToken,
  });

  final String userId;
  final String accessToken;
}

typedef AccountDeletionReauthenticate = Future<AccountDeletionSessionIdentity?>
    Function(
  String email,
  String password,
);
typedef AccountDeletionCurrentSession = AccountDeletionSessionIdentity?
    Function();
typedef AccountDeletionFunctionInvoke = Future<void> Function(
  String confirmation,
);
typedef AccountDeletionGetUser = Future<String?> Function();
typedef AccountDeletionLocalSignOut = Future<void> Function();
typedef AccountDeletionImpactRpc = Future<Object?> Function();

class SupabaseAccountDeletionRepository
    implements AccountDeletionRepository, AccountDeletionImpactRepository {
  SupabaseAccountDeletionRepository(
    SupabaseClient client, {
    AccountDeletionReauthenticate? reauthenticate,
    AccountDeletionCurrentSession? currentSession,
    AccountDeletionFunctionInvoke? invokeDeletion,
    AccountDeletionGetUser? getUser,
    AccountDeletionLocalSignOut? localSignOut,
    AccountDeletionImpactRpc? getListImpact,
  })  : _reauthenticate = reauthenticate ??
            ((email, password) async {
              final response = await client.auth.signInWithPassword(
                email: email,
                password: password,
              );
              final session = response.session;
              return session == null
                  ? null
                  : AccountDeletionSessionIdentity(
                      userId: session.user.id,
                      accessToken: session.accessToken,
                    );
            }),
        _currentSession = currentSession ??
            (() {
              final session = client.auth.currentSession;
              return session == null
                  ? null
                  : AccountDeletionSessionIdentity(
                      userId: session.user.id,
                      accessToken: session.accessToken,
                    );
            }),
        _invokeDeletion = invokeDeletion ??
            ((confirmation) async {
              final response = await client.functions.invoke(
                'delete-account',
                body: <String, Object?>{'confirmation': confirmation},
              );
              final data = response.data;
              if (response.status != 200 ||
                  data is! Map ||
                  data.length != 1 ||
                  data['deleted'] != true) {
                throw StateError('invalid account deletion response');
              }
            }),
        _getUser =
            getUser ?? (() async => (await client.auth.getUser()).user?.id),
        _localSignOut = localSignOut ??
            (() => client.auth.signOut(scope: SignOutScope.local)),
        _getListImpact = getListImpact ??
            (() => client.rpc<Object?>('get_account_deletion_list_impact'));

  final AccountDeletionReauthenticate _reauthenticate;
  final AccountDeletionCurrentSession _currentSession;
  final AccountDeletionFunctionInvoke _invokeDeletion;
  final AccountDeletionGetUser _getUser;
  final AccountDeletionLocalSignOut _localSignOut;
  final AccountDeletionImpactRpc _getListImpact;

  @override
  Future<AccountDeletionListImpact> getListImpact() async {
    try {
      final response = await _getListImpact();
      if (response is! List ||
          response.length != 1 ||
          response.single is! Map) {
        throw const FormatException();
      }
      final row = Map<String, dynamic>.from(response.single as Map);
      if (row.length != 2) throw const FormatException();
      final listCount = row['owned_shared_list_count'];
      final participantCount = row['affected_participant_count'];
      if (listCount is! int ||
          listCount < 0 ||
          participantCount is! int ||
          participantCount < 0) {
        throw const FormatException();
      }
      return AccountDeletionListImpact(
        ownedSharedListCount: listCount,
        affectedParticipantCount: participantCount,
      );
    } catch (_) {
      throw const AccountDeletionFailure(AccountDeletionFailureCode.retryable);
    }
  }

  @override
  Future<void> deleteOwnAccount({
    required String email,
    required String password,
    required String confirmation,
  }) async {
    final originalSession = _currentSession();
    if (originalSession == null) {
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.reauthenticationRequired,
      );
    }

    late final AccountDeletionSessionIdentity? reauthenticatedSession;
    try {
      reauthenticatedSession = await _reauthenticate(email, password);
    } on AuthRetryableFetchException {
      throw const AccountDeletionFailure(AccountDeletionFailureCode.offline);
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        throw const AccountDeletionFailure(
          AccountDeletionFailureCode.wrongPassword,
        );
      }
      if (_isAuthoritativeInvalidAuthError(error)) {
        final result = await validateCurrentAccount();
        if (result == AuthoritativeAccountState.missing) return;
        if (result == AuthoritativeAccountState.transientFailure) {
          throw const AccountDeletionFailure(
            AccountDeletionFailureCode.offline,
          );
        }
      }
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.retryable,
      );
    } catch (_) {
      throw const AccountDeletionFailure(AccountDeletionFailureCode.offline);
    }

    final activeSession = _currentSession();
    if (reauthenticatedSession == null ||
        activeSession == null ||
        reauthenticatedSession.userId != originalSession.userId ||
        activeSession.userId != originalSession.userId ||
        activeSession.accessToken != reauthenticatedSession.accessToken) {
      throw const AccountDeletionFailure(
        AccountDeletionFailureCode.reauthenticationRequired,
      );
    }

    try {
      await _invokeDeletion(confirmation);
    } on FunctionException catch (error) {
      switch (error.status) {
        case 401:
          await _reconcileOrThrow(
            whenAccountExists:
                AccountDeletionFailureCode.reauthenticationRequired,
          );
        case 409:
          throw const AccountDeletionFailure(
            AccountDeletionFailureCode.reauthenticationRequired,
          );
        case 422:
          throw const AccountDeletionFailure(
            AccountDeletionFailureCode.confirmationMismatch,
          );
        default:
          throw const AccountDeletionFailure(
            AccountDeletionFailureCode.retryable,
          );
      }
    } catch (_) {
      await _reconcileOrThrow(
        whenAccountExists: AccountDeletionFailureCode.retryable,
      );
    }
  }

  Future<void> _reconcileOrThrow({
    required AccountDeletionFailureCode whenAccountExists,
  }) async {
    switch (await validateCurrentAccount()) {
      case AuthoritativeAccountState.missing:
        return;
      case AuthoritativeAccountState.valid:
        throw AccountDeletionFailure(whenAccountExists);
      case AuthoritativeAccountState.invalidSession:
        throw const AccountDeletionFailure(
          AccountDeletionFailureCode.reauthenticationRequired,
        );
      case AuthoritativeAccountState.transientFailure:
        throw const AccountDeletionFailure(AccountDeletionFailureCode.offline);
    }
  }

  @override
  Future<AuthoritativeAccountState> validateCurrentAccount() async {
    final expectedUserId = _currentSession()?.userId;
    if (expectedUserId == null) {
      return AuthoritativeAccountState.invalidSession;
    }

    try {
      final authoritativeUserId = await _getUser();
      return authoritativeUserId == expectedUserId
          ? AuthoritativeAccountState.valid
          : AuthoritativeAccountState.invalidSession;
    } on AuthRetryableFetchException {
      return AuthoritativeAccountState.transientFailure;
    } on AuthException catch (error) {
      if (error.code == 'user_not_found' || error.statusCode == '404') {
        return AuthoritativeAccountState.missing;
      }
      return _isAuthoritativeInvalidAuthError(error)
          ? AuthoritativeAccountState.invalidSession
          : AuthoritativeAccountState.transientFailure;
    } catch (_) {
      return AuthoritativeAccountState.transientFailure;
    }
  }

  @override
  Future<void> clearLocalSession() async {
    try {
      await _localSignOut();
    } catch (_) {
      // GoTrue removes the local session before attempting its best-effort
      // server-side sign-out. Deletion success must not be obscured here.
    }
  }

  static bool _isAuthoritativeInvalidAuthError(AuthException error) {
    return const {'401', '403', '404'}.contains(error.statusCode) ||
        const {
          'bad_jwt',
          'invalid_jwt',
          'session_not_found',
          'user_not_found',
        }.contains(error.code);
  }
}
