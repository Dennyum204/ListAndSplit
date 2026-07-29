import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/creation_request_id.dart';

void main() {
  test('Lists presentation stays behind repository boundaries', () {
    final presentationFiles = Directory('lib/features/lists/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    expect(presentationFiles, isNotEmpty);
    for (final file in presentationFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:supabase_flutter')),
        reason: '${file.path} must not import the Supabase transport.',
      );
      expect(
        source,
        isNot(contains('SupabaseClient')),
        reason: '${file.path} must not construct a Supabase client.',
      );
      expect(
        source,
        isNot(contains('.rpc(')),
        reason: '${file.path} must call RPCs through a repository.',
      );
      expect(
        source,
        isNot(contains('.from(')),
        reason: '${file.path} must not query tables directly.',
      );
    }
  });

  test('creation request IDs are unique RFC 4122 version-4 UUIDs', () {
    final ids = List.generate(100, (_) => secureCreationRequestId()).toSet();
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(ids, hasLength(100));
    expect(ids.every(pattern.hasMatch), isTrue);
  });

  test('Chat unread UI remains scoped to list detail only', () {
    final detail = File(
      'lib/features/lists/presentation/active_list_detail_screen.dart',
    ).readAsStringSync();
    expect(detail, contains('activeListChatUnreadControllerProvider'));
    expect(detail, contains("Key('listChatButton')"));

    for (final path in [
      'lib/features/lists/presentation/active_lists_screen.dart',
      'lib/app/screens/authenticated_shell.dart',
      'lib/features/notifications/presentation/notification_bell.dart',
      'lib/features/notifications/presentation/notification_centre_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('activeListChatUnreadControllerProvider')),
        reason: '$path must not display a Chat unread badge.',
      );
      expect(
        source,
        isNot(contains('listChatButton')),
        reason: '$path must not expose the list-detail Chat entry point.',
      );
    }
  });
}
