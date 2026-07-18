import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('community presentation code stays behind repository boundaries', () {
    final presentationFiles = Directory(
      'lib/features/community/presentation',
    )
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
}
