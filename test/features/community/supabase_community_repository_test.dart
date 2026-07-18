import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/data/supabase_community_repository.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseCommunityRepository repository;

  setUp(() {
    calls = [];
    response = null;
    failure = null;
    repository = SupabaseCommunityRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('maps the minimal exact discovery response and RPC arguments', () async {
    response = [
      {
        'profile_id': 'profile-2',
        'username': 'beta_user',
        'display_name': 'Beta User',
      },
    ];

    final result = await repository.findProfileByUsername('beta_user');

    expect(result?.id, 'profile-2');
    expect(result?.username, 'beta_user');
    expect(result?.displayName, 'Beta User');
    expect(calls.single.functionName, 'find_profile_by_username');
    expect(calls.single.params, {'search_username': 'beta_user'});
  });

  test('maps empty discovery and private blocked profiles', () async {
    response = <Object?>[];
    expect(await repository.findProfileByUsername('missing_user'), isNull);

    response = [
      {
        'profile_id': 'profile-3',
        'username': 'gamma_user',
        'display_name': 'Gamma User',
      },
    ];
    final profiles = await repository.listBlockedProfiles();

    expect(profiles, hasLength(1));
    expect(profiles.single.id, 'profile-3');
    expect(calls.last.functionName, 'list_blocked_profiles');
    expect(calls.last.params, isNull);
  });

  test('uses only the reviewed block and unblock RPC parameters', () async {
    await repository.blockProfile('profile-2');
    await repository.unblockProfile('profile-2');

    expect(calls[0].functionName, 'block_profile');
    expect(calls[0].params, {'target_profile_id': 'profile-2'});
    expect(calls[1].functionName, 'unblock_profile');
    expect(calls[1].params, {'target_profile_id': 'profile-2'});
  });

  test('converts malformed and backend responses to a generic failure',
      () async {
    response = {'profile_id': 'not-a-list'};
    await expectLater(
      repository.findProfileByUsername('beta_user'),
      throwsA(isA<CommunityFailure>()),
    );

    failure = StateError('backend details');
    await expectLater(
      repository.listBlockedProfiles(),
      throwsA(isA<CommunityFailure>()),
    );
  });
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
