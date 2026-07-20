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

    test('rejects unsupported schema versions', () {
      final json = validAccountDataExportJson()..['schema_version'] = 3;

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
