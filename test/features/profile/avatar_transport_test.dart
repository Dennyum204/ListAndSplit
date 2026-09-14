import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:list_and_split/features/profile/data/avatar_gallery.dart';
import 'package:list_and_split/features/profile/data/supabase_profile_avatar_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('real Functions transport preserves PNG MIME and binary avatar bytes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client =
        SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    final png = createAvatarThumbnail(Uint8List.fromList(
        image.encodePng(image.Image(width: 300, height: 150))));
    final requests = <String>[];
    final contentTypes = <String?>[];
    final bodies = <List<int>>[];
    server.listen((request) async {
      requests.add(request.method);
      contentTypes.add(request.headers.value('content-type'));
      bodies.add(await request.fold<List<int>>([], (a, b) => a..addAll(b)));
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(png);
      } else if (contentTypes.last != 'image/png') {
        request.response.statusCode = 422;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"error":"invalid_image"}');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"version":1,"has_image":true}');
      }
      await request.response.close();
    });
    try {
      final session = Session(
          accessToken: 'test-token',
          tokenType: 'bearer',
          user: const User(
              id: '11111111-1111-4111-8111-111111111111',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01T00:00:00Z'));
      final repository =
          SupabaseProfileAvatarRepository(client, session: () => session);
      final result = await repository.replace(
          png, 0, '22222222-2222-4222-8222-222222222222', session.user.id);
      expect(result.version, 1);
      expect(await repository.read(AvatarTarget.profile(session.user.id)), png);
      expect(requests, ['PUT', 'GET']);
      expect(contentTypes.first, 'image/png');
      expect(bodies.first, png);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}
