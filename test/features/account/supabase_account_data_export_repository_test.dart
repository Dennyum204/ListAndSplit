import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/data/supabase_account_data_export_repository.dart';
import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_data_export_fixtures.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late String? currentUserId;
  late SupabaseAccountDataExportRepository repository;

  setUp(() {
    calls = [];
    response = validAccountDataExportJson();
    failure = null;
    currentUserId = '11111111-1111-4111-8111-111111111111';
    repository = SupabaseAccountDataExportRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
      currentUserId: () => currentUserId,
    );
  });

  test('calls only the parameterless reviewed RPC', () async {
    final document = await repository.exportOwnAccountData();

    expect(document.schemaVersion, 1);
    expect(calls, hasLength(1));
    expect(calls.single.functionName, 'export_own_account_data');
    expect(calls.single.params, isNull);
  });

  test('maps verified incomplete account response', () async {
    response = validAccountDataExportJson(
      incompleteProfile: true,
      emptyCollections: true,
    );

    final document = await repository.exportOwnAccountData();

    expect(document.profile.onboardingCompletedAt, isNull);
    expect(document.activeRelationships, isEmpty);
  });

  test('rejects missing, mismatched, and replaced session identities',
      () async {
    currentUserId = null;
    await expectLater(
      repository.exportOwnAccountData(),
      throwsA(isA<AccountDataExportFailure>()),
    );
    expect(calls, isEmpty);

    currentUserId = '22222222-2222-4222-8222-222222222222';
    await expectLater(
      repository.exportOwnAccountData(),
      throwsA(isA<AccountDataExportFailure>()),
    );

    currentUserId = '11111111-1111-4111-8111-111111111111';
    repository = SupabaseAccountDataExportRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        currentUserId = '22222222-2222-4222-8222-222222222222';
        return validAccountDataExportJson();
      },
      currentUserId: () => currentUserId,
    );
    await expectLater(
      repository.exportOwnAccountData(),
      throwsA(isA<AccountDataExportFailure>()),
    );
  });

  test('maps malformed and transport failures without exposing details',
      () async {
    response = ['not', 'an', 'object'];
    await expectLater(
      repository.exportOwnAccountData(),
      throwsA(isA<AccountDataExportFailure>()),
    );

    const privateTransportMessage = 'private payload value';
    failure = StateError(privateTransportMessage);
    try {
      await repository.exportOwnAccountData();
      fail('transport failure should be mapped');
    } catch (error) {
      expect(error, isA<AccountDataExportFailure>());
      expect(error.toString(), isNot(contains(privateTransportMessage)));
    }
  });
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
