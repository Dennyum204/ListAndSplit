import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/domain/account_data_export.dart';

import 'account_data_export_fixtures.dart';

void main() {
  group('AccountDataExportDocument', () {
    test('maps every approved schema-v2 section', () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(),
      );

      expect(document.product, AccountDataExportDocument.supportedProduct);
      expect(document.schemaVersion, 2);
      expect(document.exportedAt, DateTime.utc(2026, 7, 19, 8, 58, 10, 123));
      expect(document.authIdentity.email, 'alpha@example.test');
      expect(document.authIdentity.lastSignInAt, isNull);
      expect(document.profile.username, 'alpha_user');
      expect(document.profile.onboardingCompletedAt, isNotNull);
      expect(document.outgoingBlocks.single.username, 'beta_user');
      expect(
        document.activeRelationships.single.status,
        AccountRelationshipStatus.friends,
      );
      expect(document.activeRelationships.single.version, 4);
      expect(
        document.visibleNotifications.single.actionStatus,
        AccountNotificationActionStatus.actionable,
      );
      expect(
        document.visibleNotifications.single.expectedRelationshipVersion,
        4,
      );
      expect(document.activeLists, hasLength(2));
      expect(document.activeLists.first.title, 'Groceries');
      expect(document.activeLists.first.status, AccountActiveListStatus.active);
      expect(document.activeLists.first.items.single.name, 'Coffee');
      expect(
        document.activeLists.first.items.single.quantityThousandths,
        1500,
      );
      expect(document.activeLists.first.items.single.unitCode, 'pack');
      expect(
          document.activeLists.last.status, AccountActiveListStatus.archived);
    });

    test('maps verified incomplete profile and empty arrays', () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(
          incompleteProfile: true,
          emptyCollections: true,
        ),
      );

      expect(document.profile.username, isNull);
      expect(document.profile.displayName, isNull);
      expect(document.profile.onboardingCompletedAt, isNull);
      expect(document.outgoingBlocks, isEmpty);
      expect(document.activeRelationships, isEmpty);
      expect(document.visibleNotifications, isEmpty);
      expect(document.activeLists, isEmpty);
    });

    test('retains deliberate historical schema-v1 fixture support', () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(schemaVersion: 1),
      );

      expect(document.schemaVersion, 1);
      expect(document.activeLists, isEmpty);
      expect(document.toJson(), isNot(contains('active_lists')));
    });

    test('maps privacy-minimal schema-v3 shared-list access', () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(schemaVersion: 3),
      );

      expect(document.schemaVersion, 3);
      expect(document.activeLists, hasLength(2));
      expect(document.sharedListAccess, hasLength(1));
      final access = document.sharedListAccess.single;
      expect(access.listId, '88888888-8888-4888-8888-888888888888');
      expect(access.listTitle, 'Shared trip');
      expect(access.listStatus, AccountActiveListStatus.active);
      expect(access.accessState, AccountSharedListAccessState.member);
      expect(access.accessVersion, 5);
      expect(access.stateChangedAt.isAfter(access.createdAt), isTrue);
      expect(access.toJson().keys, {
        'list_id',
        'list_title',
        'list_status',
        'access_state',
        'access_version',
        'created_at',
        'state_changed_at',
      });
      expect(document.toJson(), contains('shared_list_access'));
    });

    test('maps schema-v4 private categories, templates, quantities and order',
        () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(schemaVersion: 4),
      );

      expect(document.schemaVersion, 4);
      expect(document.templateCategories.single.name, 'Weekly shops');
      final template = document.templates.single;
      expect(template.name, 'Weekly groceries');
      expect(template.categoryId, document.templateCategories.single.id);
      expect(template.items.single.name, 'Coffee');
      expect(template.items.single.quantityThousandths, 1500);
      expect(template.items.single.position, 1);
      expect(document.toJson(), contains('template_categories'));
      expect(document.toJson(), contains('templates'));
    });

    test('maps schema-v5 owned-list Split with exact integer shares', () {
      final document = AccountDataExportDocument.fromJson(
        validAccountDataExportJson(schemaVersion: 5),
      );

      expect(document.schemaVersion, 5);
      final split = document.activeLists.first.split!;
      expect(split.settings.currencyCode, 'CHF');
      expect(split.settings.version, 2);
      expect(split.participants, hasLength(2));
      expect(split.participants.first.username, 'alpha_user');
      expect(split.expenses.single.description, 'Shared coffee');
      expect(split.expenses.single.amountMinor, 1001);
      expect(
        split.expenses.single.shares.map((share) => share.amountMinor),
        [501, 500],
      );
      expect(document.activeLists.last.includesSplitField, isTrue);
      expect(document.activeLists.last.split, isNull);
      expect(document.toJson(), validAccountDataExportJson(schemaVersion: 5));
    });

    test(
        'maps schema-v6 owned-list immutable settlements and optional reversal',
        () {
      final json = validAccountDataExportJson(schemaVersion: 6);
      final document = AccountDataExportDocument.fromJson(json);

      expect(document.schemaVersion, 6);
      final split = document.activeLists.first.split!;
      expect(split.includesSettlementsField, isTrue);
      expect(split.settlements, hasLength(2));

      final partial = split.settlements.first;
      expect(partial.id, '12121212-1212-4121-8121-121212121212');
      expect(
        partial.payerParticipantId,
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      );
      expect(
        partial.recipientParticipantId,
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      );
      expect(
        partial.recordedByParticipantId,
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      );
      expect(partial.amountMinor, 250);
      expect(partial.note, 'Partial repayment');
      expect(partial.createdAt, DateTime.utc(2026, 7, 19, 7, 15));
      expect(partial.reversal, isNull);

      final reversed = split.settlements.last;
      expect(reversed.amountMinor, 100);
      expect(reversed.note, isNull);
      expect(
        reversed.reversal!.reversedByParticipantId,
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      );
      expect(reversed.reversal!.reason, 'Recorded twice');
      expect(
        reversed.reversal!.createdAt,
        DateTime.utc(2026, 7, 19, 7, 30),
      );
      expect(document.toJson(), json);
    });

    test('keeps the schema-v5 Split key contract unchanged', () {
      final json = validAccountDataExportJson(schemaVersion: 5);
      final splitJson = _ownedSplit(json);
      final document = AccountDataExportDocument.fromJson(json);

      expect(splitJson.keys, {'settings', 'participants', 'expenses'});
      expect(splitJson, isNot(contains('settlements')));
      expect(document.activeLists.first.split!.includesSettlementsField, false);
      expect(document.activeLists.first.split!.settlements, isEmpty);
      expect(document.toJson(), json);

      splitJson['settlements'] = <Object?>[];
      expect(
        () => AccountDataExportDocument.fromJson(json),
        throwsA(isA<AccountDataExportFailure>()),
      );
    });

    test('keeps schema-v1 through v4 owned-list shapes strict and compatible',
        () {
      for (final version in [1, 2, 3, 4]) {
        final json = validAccountDataExportJson(schemaVersion: version);
        final document = AccountDataExportDocument.fromJson(json);
        expect(document.toJson(), json);
        expect(
          document.activeLists.every((list) => !list.includesSplitField),
          isTrue,
        );
      }

      final legacyWithSplit = validAccountDataExportJson(schemaVersion: 4);
      (legacyWithSplit['active_lists'] as List)
          .cast<Map<String, dynamic>>()
          .first['split'] = null;
      expect(
        () => AccountDataExportDocument.fromJson(legacyWithSplit),
        throwsA(isA<AccountDataExportFailure>()),
      );
    });

    test('rejects malformed or privacy-expanded schema-v5 Split data', () {
      Map<String, dynamic> splitOf(Map<String, dynamic> root) =>
          ((root['active_lists'] as List).first
              as Map<String, dynamic>)['split'] as Map<String, dynamic>;

      final missingSplit = validAccountDataExportJson(schemaVersion: 5);
      ((missingSplit['active_lists'] as List).first as Map<String, dynamic>)
          .remove('split');

      final leakedBalance = validAccountDataExportJson(schemaVersion: 5);
      ((splitOf(leakedBalance)['participants'] as List).first
          as Map<String, dynamic>)['balance_minor'] = 0;

      final leakedRequest = validAccountDataExportJson(schemaVersion: 5);
      ((splitOf(leakedRequest)['expenses'] as List).first
              as Map<String, dynamic>)['creation_request_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final badShareTotal = validAccountDataExportJson(schemaVersion: 5);
      (((splitOf(badShareTotal)['expenses'] as List).first
              as Map<String, dynamic>)['shares'] as List)
          .cast<Map<String, dynamic>>()
          .last['amount_minor'] = 499;

      final unknownActor = validAccountDataExportJson(schemaVersion: 5);
      ((splitOf(unknownActor)['expenses'] as List).first
              as Map<String, dynamic>)['last_editor_participant_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final currentAnonymized = validAccountDataExportJson(schemaVersion: 5);
      final currentAnonymizedSplit = splitOf(currentAnonymized);
      final originalParticipants =
          currentAnonymizedSplit['participants'] as List;
      final currentAnonymizedParticipant = Map<String, dynamic>.from(
        originalParticipants.first as Map,
      )
        ..['profile_id'] = null
        ..['username'] = null
        ..['display_name'] = null
        ..['is_anonymized'] = true
        ..['is_current'] = true;
      currentAnonymizedSplit['participants'] = <Object?>[
        currentAnonymizedParticipant,
        ...originalParticipants.skip(1),
      ];

      for (final json in [
        missingSplit,
        leakedBalance,
        leakedRequest,
        badShareTotal,
        unknownActor,
        currentAnonymized,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects missing or privacy-expanded schema-v6 settlement history',
        () {
      final missingSettlements = validAccountDataExportJson(schemaVersion: 6);
      _ownedSplit(missingSettlements).remove('settlements');

      final leakedRequest = validAccountDataExportJson(schemaVersion: 6);
      _settlements(leakedRequest).first['creation_request_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final leakedBalance = validAccountDataExportJson(schemaVersion: 6);
      _settlements(leakedBalance).first['balance_after_minor'] = 250;

      final leakedSuggestion = validAccountDataExportJson(schemaVersion: 6);
      _ownedSplit(leakedSuggestion)['suggestions'] = <Object?>[];

      final leakedReversalRequest =
          validAccountDataExportJson(schemaVersion: 6);
      (_settlements(leakedReversalRequest).last['reversal']
              as Map<String, dynamic>)['reversal_request_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final sharedListSplit = validAccountDataExportJson(schemaVersion: 6);
      ((sharedListSplit['shared_list_access'] as List).single
          as Map<String, dynamic>)['split'] = <String, dynamic>{};

      for (final json in [
        missingSettlements,
        leakedRequest,
        leakedBalance,
        leakedSuggestion,
        leakedReversalRequest,
        sharedListSplit,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects invalid schema-v6 settlement identities and amounts', () {
      final duplicateId = validAccountDataExportJson(schemaVersion: 6);
      _settlements(duplicateId).last['id'] =
          _settlements(duplicateId).first['id'];

      final selfPayment = validAccountDataExportJson(schemaVersion: 6);
      _settlements(selfPayment).first['recipient_participant_id'] =
          _settlements(selfPayment).first['payer_participant_id'];

      final zeroAmount = validAccountDataExportJson(schemaVersion: 6);
      _settlements(zeroAmount).first['amount_minor'] = 0;

      final impreciseAmount = validAccountDataExportJson(schemaVersion: 6);
      _settlements(impreciseAmount).first['amount_minor'] = 1.5;

      final unknownPayer = validAccountDataExportJson(schemaVersion: 6);
      _settlements(unknownPayer).first['payer_participant_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final unknownRecipient = validAccountDataExportJson(schemaVersion: 6);
      _settlements(unknownRecipient).first['recipient_participant_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final unknownRecorder = validAccountDataExportJson(schemaVersion: 6);
      _settlements(unknownRecorder).first['recorded_by_participant_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      final unknownReverser = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(unknownReverser).last['reversal']
              as Map<String, dynamic>)['reversed_by_participant_id'] =
          'ffffffff-ffff-4fff-8fff-ffffffffffff';

      for (final json in [
        duplicateId,
        selfPayment,
        zeroAmount,
        impreciseAmount,
        unknownPayer,
        unknownRecipient,
        unknownRecorder,
        unknownReverser,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects noncanonical schema-v6 settlement notes and reversals', () {
      final emptyNote = validAccountDataExportJson(schemaVersion: 6);
      _settlements(emptyNote).first['note'] = '';

      final paddedNote = validAccountDataExportJson(schemaVersion: 6);
      _settlements(paddedNote).first['note'] = ' padded ';

      final longNote = validAccountDataExportJson(schemaVersion: 6);
      _settlements(longNote).first['note'] = List.filled(121, 'n').join();

      final emptyReason = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(emptyReason).last['reversal']
          as Map<String, dynamic>)['reason'] = '';

      final paddedReason = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(paddedReason).last['reversal']
          as Map<String, dynamic>)['reason'] = ' duplicate ';

      final longReason = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(longReason).last['reversal']
          as Map<String, dynamic>)['reason'] = List.filled(121, 'r').join();

      final earlyReversal = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(earlyReversal).last['reversal']
          as Map<String, dynamic>)['created_at'] = '2026-07-19T07:19:59.999Z';

      final nonUtcReversal = validAccountDataExportJson(schemaVersion: 6);
      (_settlements(nonUtcReversal).last['reversal']
          as Map<String, dynamic>)['created_at'] = '2026-07-19T07:30:00';

      final malformedReversal = validAccountDataExportJson(schemaVersion: 6);
      _settlements(malformedReversal).last['reversal'] = <Object?>[];

      for (final json in [
        emptyNote,
        paddedNote,
        longNote,
        emptyReason,
        paddedReason,
        longReason,
        earlyReversal,
        nonUtcReversal,
        malformedReversal,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('schema versions 1 and 2 never fabricate shared-list access', () {
      for (final version in [1, 2]) {
        final document = AccountDataExportDocument.fromJson(
          validAccountDataExportJson(schemaVersion: version),
        );
        expect(document.sharedListAccess, isEmpty);
        expect(document.toJson(), isNot(contains('shared_list_access')));
      }
    });

    test('schema-v3 accepts every retained caller-relative access state', () {
      for (final state in AccountSharedListAccessState.values) {
        final json = validAccountDataExportJson(schemaVersion: 3);
        ((json['shared_list_access'] as List).single
            as Map<String, dynamic>)['access_state'] = state.wireValue;

        final document = AccountDataExportDocument.fromJson(json);

        expect(document.sharedListAccess.single.accessState, state);
      }
    });

    test('rejects unsupported schema versions', () {
      final json = validAccountDataExportJson()..['schema_version'] = 7;

      expect(
        () => AccountDataExportDocument.fromJson(json),
        throwsA(isA<AccountDataExportFailure>()),
      );
    });

    test('rejects missing and extra root fields', () {
      final missing = validAccountDataExportJson()..remove('profile');
      final extra = validAccountDataExportJson()..['server_internal'] = true;

      expect(
        () => AccountDataExportDocument.fromJson(missing),
        throwsA(isA<AccountDataExportFailure>()),
      );
      expect(
        () => AccountDataExportDocument.fromJson(extra),
        throwsA(isA<AccountDataExportFailure>()),
      );
    });

    test('rejects malformed nested objects, arrays, and timestamps', () {
      final malformedProfile = validAccountDataExportJson()
        ..['profile'] = {'id': 'not-an-export-profile'};
      final malformedArray = validAccountDataExportJson()
        ..['outgoing_blocks'] = {'not': 'an array'};
      final malformedTimestamp = validAccountDataExportJson()
        ..['exported_at'] = 'not-a-timestamp';
      final nonUtcTimestamp = validAccountDataExportJson()
        ..['exported_at'] = '2026-07-19T08:00:00';

      for (final json in [
        malformedProfile,
        malformedArray,
        malformedTimestamp,
        nonUtcTimestamp,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects malformed or privacy-expanded active-list data', () {
      final unknownUnit = validAccountDataExportJson();
      (((unknownUnit['active_lists'] as List).first
              as Map<String, dynamic>)['items'] as List)
          .cast<Map<String, dynamic>>()
          .single['unit_code'] = 'localized kilograms';

      final leakedRequest = validAccountDataExportJson();
      ((leakedRequest['active_lists'] as List).first
              as Map<String, dynamic>)['creation_request_id'] =
          '88888888-8888-4888-8888-888888888888';

      final impreciseQuantity = validAccountDataExportJson();
      ((((impreciseQuantity['active_lists'] as List).first
              as Map<String, dynamic>)['items'] as List)
          .first as Map<String, dynamic>)['quantity_thousandths'] = 1.5;

      for (final json in [unknownUnit, leakedRequest, impreciseQuantity]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects malformed or privacy-expanded shared-list access', () {
      final ownerLeak = validAccountDataExportJson(schemaVersion: 3);
      ((ownerLeak['shared_list_access'] as List).single
              as Map<String, dynamic>)['owner_profile_id'] =
          '99999999-9999-4999-8999-999999999999';

      final itemLeak = validAccountDataExportJson(schemaVersion: 3);
      ((itemLeak['shared_list_access'] as List).single
          as Map<String, dynamic>)['items'] = <Object?>[];

      final invalidState = validAccountDataExportJson(schemaVersion: 3);
      ((invalidState['shared_list_access'] as List).single
          as Map<String, dynamic>)['access_state'] = 'blocked';

      final invalidVersion = validAccountDataExportJson(schemaVersion: 3);
      ((invalidVersion['shared_list_access'] as List).single
          as Map<String, dynamic>)['access_version'] = 0;

      final reversedTimestamps = validAccountDataExportJson(schemaVersion: 3);
      ((reversedTimestamps['shared_list_access'] as List).single
              as Map<String, dynamic>)['state_changed_at'] =
          '2026-07-19T04:00:00.000Z';

      for (final json in [
        ownerLeak,
        itemLeak,
        invalidState,
        invalidVersion,
        reversedTimestamps,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('rejects inconsistent profile, read, and action shapes', () {
      final incompleteButCompleted = validAccountDataExportJson(
        incompleteProfile: true,
      );
      (incompleteButCompleted['profile']
              as Map<String, dynamic>)['onboarding_completed_at'] =
          '2026-07-19T08:00:00.000Z';

      final inconsistentRead = validAccountDataExportJson();
      (inconsistentRead['visible_notifications'] as List)
          .cast<Map<String, dynamic>>()
          .single['is_read'] = true;

      final inconsistentAction = validAccountDataExportJson();
      (inconsistentAction['visible_notifications'] as List)
          .cast<Map<String, dynamic>>()
          .single['expected_relationship_version'] = null;

      for (final json in [
        incompleteButCompleted,
        inconsistentRead,
        inconsistentAction,
      ]) {
        expect(
          () => AccountDataExportDocument.fromJson(json),
          throwsA(isA<AccountDataExportFailure>()),
        );
      }
    });

    test('failures never include payload contents', () {
      const privateValue = 'private-person@example.test';
      final json = validAccountDataExportJson();
      (json['auth_identity'] as Map<String, dynamic>)['email'] = privateValue;
      json['schema_version'] = 99;

      try {
        AccountDataExportDocument.fromJson(json);
        fail('malformed export should fail');
      } catch (error) {
        expect(error, isA<AccountDataExportFailure>());
        expect(error.toString(), isNot(contains(privateValue)));
      }
    });
  });
}

Map<String, dynamic> _ownedSplit(Map<String, dynamic> root) {
  return ((root['active_lists'] as List).first as Map<String, dynamic>)['split']
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> _settlements(Map<String, dynamic> root) {
  return (_ownedSplit(root)['settlements'] as List)
      .cast<Map<String, dynamic>>();
}
