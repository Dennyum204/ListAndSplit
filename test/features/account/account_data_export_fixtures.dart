import 'package:list_and_split/features/account/domain/account_data_export.dart';

Map<String, dynamic> validAccountDataExportJson({
  bool incompleteProfile = false,
  bool emptyCollections = false,
}) {
  return {
    'product': 'list_and_split',
    'schema_version': 1,
    'exported_at': '2026-07-19T08:58:10.123Z',
    'auth_identity': {
      'id': '11111111-1111-4111-8111-111111111111',
      'email': 'alpha@example.test',
      'email_confirmed_at': '2026-07-18T08:00:00.000Z',
      'created_at': '2026-07-17T08:00:00.000Z',
      'updated_at': '2026-07-19T07:00:00.000Z',
      'last_sign_in_at': null,
    },
    'profile': {
      'id': '11111111-1111-4111-8111-111111111111',
      'username': incompleteProfile ? null : 'alpha_user',
      'display_name': incompleteProfile ? null : 'Alpha User',
      'created_at': '2026-07-17T08:00:00.000Z',
      'updated_at': '2026-07-19T07:00:00.000Z',
      'onboarding_completed_at':
          incompleteProfile ? null : '2026-07-18T09:00:00.000Z',
    },
    'outgoing_blocks': emptyCollections
        ? <Object?>[]
        : [
            {
              'profile_id': '22222222-2222-4222-8222-222222222222',
              'username': 'beta_user',
              'display_name': 'Beta User',
              'created_at': '2026-07-19T06:00:00.000Z',
            },
          ],
    'active_relationships': emptyCollections
        ? <Object?>[]
        : [
            {
              'profile_id': '33333333-3333-4333-8333-333333333333',
              'username': 'gamma_user',
              'display_name': 'Gamma User',
              'status': 'friends',
              'version': 4,
              'state_changed_at': '2026-07-19T06:30:00.000Z',
            },
          ],
    'visible_notifications': emptyCollections
        ? <Object?>[]
        : [
            {
              'id': '44444444-4444-4444-8444-444444444444',
              'type': 'friend_request',
              'created_at': '2026-07-19T07:00:00.000Z',
              'is_read': false,
              'read_at': null,
              'expires_at': '2027-01-15T07:00:00.000Z',
              'actor_profile_id': '33333333-3333-4333-8333-333333333333',
              'actor_username': 'gamma_user',
              'actor_display_name': 'Gamma User',
              'action_status': 'actionable',
              'expected_relationship_version': 4,
            },
          ],
  };
}

AccountDataExportDocument validAccountDataExportDocument({
  bool incompleteProfile = false,
  bool emptyCollections = false,
}) {
  return AccountDataExportDocument.fromJson(
    validAccountDataExportJson(
      incompleteProfile: incompleteProfile,
      emptyCollections: emptyCollections,
    ),
  );
}
