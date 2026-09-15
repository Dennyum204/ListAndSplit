import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/profile/data/avatar_gallery.dart';
import 'package:list_and_split/features/profile/data/supabase_profile_avatar_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_avatar.dart';
import 'package:list_and_split/features/profile/presentation/avatar_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_avatar.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_screen.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/moderation/presentation/public_template_moderation_providers.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_controller.dart';
import 'package:list_and_split/features/account/data/avatar_account_data_export_repository.dart';
import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../account/account_data_export_fixtures.dart';
import '../../helpers/fakes.dart';
import '../../helpers/fake_public_template_moderation_repository.dart';
import '../../helpers/fake_language_preference_repository.dart';
import '../../helpers/fake_theme_preference_repository.dart';
import '../../support/ui_preview_capture.dart';

Uint8List thumbnail() => createAvatarThumbnail(Uint8List.fromList(
    image.encodePng(image.fill(image.Image(width: 300, height: 150),
        color: image.ColorRgb8(54, 116, 145)))));
Session fixtureSession([String id = '11111111-1111-4111-8111-111111111111']) =>
    Session(
        accessToken: 'local-test-token',
        tokenType: 'bearer',
        user: User(
            id: id,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-01-01T00:00:00Z'));

class Gallery implements AvatarGallery {
  Uint8List? bytes = Uint8List(100);
  Completer<Uint8List?>? pending;
  @override
  Future<Uint8List?> selectThumbnail() async =>
      pending == null ? bytes : await pending!.future;
}

class Repository implements ProfileAvatarRepository {
  int writes = 0, reads = 0;
  bool hasImage = true;
  Object? failure;
  Uint8List? bytes;
  Completer<ProfileAvatarMetadata>? pending;
  Completer<Uint8List?>? pendingRead;
  @override
  Future<ProfileAvatarMetadata> metadata() async =>
      ProfileAvatarMetadata(version: 7, hasImage: hasImage);
  @override
  Future<Uint8List?> read(AvatarTarget target) async {
    reads++;
    return pendingRead == null ? bytes : await pendingRead!.future;
  }

  Future<ProfileAvatarMetadata> mutate(int version, String expectedUser) async {
    writes++;
    expect(version, 7);
    expect(expectedUser, 'viewer');
    if (failure != null) throw failure!;
    return pending == null
        ? const ProfileAvatarMetadata(version: 8, hasImage: true)
        : await pending!.future;
  }

  @override
  Future<ProfileAvatarMetadata> replace(
          Uint8List bytes, int version, String id, String expectedUser) =>
      mutate(version, expectedUser);
  @override
  Future<ProfileAvatarMetadata> remove(
          int version, String id, String expectedUser) =>
      mutate(version, expectedUser);
}

void main() {
  setUpAll(prepareUiPreviewFonts);
  test('gallery creates a bounded metadata-free square PNG', () {
    final bytes = thumbnail();
    final decoded = image.decodePng(bytes)!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);
    expect(bytes.length, lessThanOrEqualTo(327680));
    final types = <String>[];
    var offset = 8;
    final data = ByteData.sublistView(bytes);
    while (offset < bytes.length) {
      types.add(ascii.decode(bytes.sublist(offset + 4, offset + 8)));
      offset += 12 + data.getUint32(offset);
    }
    expect(types.toSet(), {'IHDR', 'IDAT', 'IEND'});
  });
  for (final input in [
    Uint8List(0),
    Uint8List(10),
    Uint8List(5 * 1024 * 1024 + 1)
  ]) {
    test(
        'reject invalid/oversized input ${input.length}',
        () => expect(
            () => createAvatarThumbnail(input), throwsA(isA<AvatarFailure>())));
  }
  for (final value in [
    null,
    {},
    {'version': -1, 'has_image': true},
    {'version': 1, 'has_image': 1},
    {'version': 1, 'has_image': true, 'path': 'private'}
  ]) {
    test(
        'strict metadata rejects $value',
        () => expect(() => ProfileAvatarMetadata.fromJson(value),
            throwsA(isA<AvatarFailure>())));
  }
  test('context IDs cannot collide across profile Chat and Split', () {
    expect({
      const AvatarTarget.profile('id'),
      const AvatarTarget.chat('id'),
      const AvatarTarget.split('id')
    }, hasLength(3));
    expect(const AvatarTarget.chat('id'), const AvatarTarget.chat('id'));
  });
  for (final remove in [false, true]) {
    test(
        'successful ${remove ? 'removal' : 'replacement'} refreshes exactly once',
        () async {
      final repo = Repository();
      var refresh = 0;
      final c = AvatarController(repo, Gallery(), 'viewer', () => refresh++);
      addTearDown(c.dispose);
      await c.submit(remove: remove);
      expect(repo.writes, 1);
      expect(c.state.busy, false);
      expect(c.state.changed, true);
      expect(refresh, 1);
    });
  }
  test('cancel gallery neither writes nor refreshes', () async {
    final repo = Repository();
    var refresh = 0;
    final c = AvatarController(
        repo, Gallery()..bytes = null, 'viewer', () => refresh++);
    addTearDown(c.dispose);
    await c.submit(remove: false);
    expect(repo.writes, 0);
    expect(c.state.busy, false);
    expect(refresh, 0);
  });
  test(
      'stale conflict reloads once without retrying; a later user action succeeds',
      () async {
    final repo = Repository()
      ..failure = const AvatarFailure(AvatarFailureKind.stale);
    var refresh = 0;
    final controller =
        AvatarController(repo, Gallery(), 'viewer', () => refresh++);
    addTearDown(controller.dispose);
    await controller.submit(remove: false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.error, AvatarFailureKind.stale);
    expect(controller.state.busy, false);
    expect(repo.writes, 1);
    expect(refresh, 1);
    repo.failure = null;
    await controller.submit(remove: false);
    expect(repo.writes, 2);
    expect(refresh, 2);
    expect(controller.state.error, isNull);
    expect(controller.state.changed, true);
  });
  for (final error in [
    const AvatarFailure(AvatarFailureKind.stale),
    const AvatarFailure(AvatarFailureKind.busy),
    StateError('unexpected')
  ]) {
    test('failure $error stops progress and refreshes authoritatively',
        () async {
      final repo = Repository()..failure = error;
      var refresh = 0;
      final c = AvatarController(repo, Gallery(), 'viewer', () => refresh++);
      addTearDown(c.dispose);
      await c.submit(remove: false);
      expect(c.state.busy, false);
      expect(c.state.changed, false);
      expect(c.state.error, isNotNull);
      expect(refresh, 1);
    });
  }
  test('repeated taps coalesce during gallery and server submission', () async {
    final repo = Repository()..pending = Completer();
    final gallery = Gallery()..pending = Completer();
    final c = AvatarController(repo, gallery, 'viewer', () {});
    addTearDown(c.dispose);
    final first = c.submit(remove: false);
    await Future<void>.delayed(Duration.zero);
    await c.submit(remove: false);
    gallery.pending!.complete(Uint8List(100));
    await Future<void>.delayed(Duration.zero);
    await c.submit(remove: true);
    expect(repo.writes, 1);
    repo.pending!
        .complete(const ProfileAvatarMetadata(version: 8, hasImage: true));
    await first;
    expect(c.state.busy, false);
  });
  test('disposal during gallery cannot upload for a replaced session',
      () async {
    final repo = Repository();
    final gallery = Gallery()..pending = Completer();
    final c =
        AvatarController(repo, gallery, 'viewer', () => fail('late refresh'));
    final work = c.submit(remove: false);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    gallery.pending!.complete(Uint8List(100));
    await work;
    expect(repo.writes, 0);
  });
  test('disposal during upload has no late state or refresh', () async {
    final repo = Repository()..pending = Completer();
    final c =
        AvatarController(repo, Gallery(), 'viewer', () => fail('late refresh'));
    final work = c.submit(remove: true);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    repo.pending!.completeError(StateError('offline'));
    await work;
  });
  group('transport', () {
    late SupabaseClient client;
    Session? session;
    setUp(() {
      client = SupabaseClient('http://localhost', 'test-placeholder');
      session = fixtureSession();
    });
    tearDown(() => client.dispose());
    for (final operation in ['read', 'remove', 'export']) {
      test('stalled $operation request terminates with a recoverable failure',
          () async {
        final pending = Completer<FunctionResponse>();
        Future<FunctionResponse> invoke(
                String method,
                Map<String, String> headers,
                Uint8List? body,
                Map<String, String>? query) =>
            pending.future;
        if (operation == 'export') {
          final repository = AvatarAccountDataExportRepository(client,
              session: () => session,
              invoke: invoke,
              requestTimeout: Duration.zero);
          await expectLater(repository.exportOwnAccountData(),
              throwsA(isA<AccountDataExportFailure>()));
        } else {
          final repository = SupabaseProfileAvatarRepository(client,
              session: () => session,
              invoke: invoke,
              requestTimeout: Duration.zero);
          await expectLater(
              operation == 'read'
                  ? repository.read(const AvatarTarget.profile('target'))
                  : repository.remove(0, 'request', session!.user.id),
              throwsA(isA<AvatarFailure>()));
        }
        // A late response is consumed by the timeout future, never applied to UI.
        pending.complete(FunctionResponse(status: 200, data: null));
      });
    }
    test('uses contextual IDs and captured user authentication without URLs',
        () async {
      final bytes = thumbnail();
      final repo = SupabaseProfileAvatarRepository(client,
          session: () => session,
          invoke: (method, headers, body, query) async {
            expect(method, 'get');
            expect(headers['Authorization'], 'Bearer local-test-token');
            expect(body, isNull);
            expect(query, {'kind': 'chat', 'id': 'message'});
            return FunctionResponse(status: 200, data: bytes);
          });
      expect(await repo.read(const AvatarTarget.chat('message')), bytes);
    });
    test('no session cannot read or mutate', () async {
      session = null;
      final repo = SupabaseProfileAvatarRepository(client,
          session: () => session,
          invoke: (_, __, ___, ____) async =>
              throw StateError('must not invoke'));
      expect(await repo.read(const AvatarTarget.profile('x')), isNull);
      await expectLater(
          repo.remove(0, 'r', 'x'), throwsA(isA<AvatarFailure>()));
    });
    test('late bytes from old account are discarded', () async {
      final repo = SupabaseProfileAvatarRepository(client,
          session: () => session,
          invoke: (_, __, ___, ____) async {
            session = fixtureSession('other');
            return FunctionResponse(status: 200, data: thumbnail());
          });
      expect(await repo.read(const AvatarTarget.profile('x')), isNull);
    });
    for (final code in ['stale', 'busy', 'invalid_image', 'unexpected']) {
      test('maps $code without transport detail', () async {
        final repo = SupabaseProfileAvatarRepository(client,
            session: () => session,
            invoke: (_, __, ___, ____) async =>
                throw FunctionException(status: 409, details: {'error': code}));
        await expectLater(
            repo.remove(7, 'request', session!.user.id),
            throwsA(isA<AvatarFailure>().having(
                (e) => e.kind,
                'kind',
                switch (code) {
                  'stale' => AvatarFailureKind.stale,
                  'busy' => AvatarFailureKind.busy,
                  'invalid_image' => AvatarFailureKind.invalidImage,
                  _ => AvatarFailureKind.retryable
                })));
      });
    }
    test('replacement carries version and request but no target owner',
        () async {
      final repo = SupabaseProfileAvatarRepository(client,
          session: () => session,
          invoke: (method, headers, body, query) async {
            expect(method, 'put');
            expect(headers['if-match'], '7');
            expect(headers['x-request-id'], 'request');
            expect(query, isNull);
            expect(body, hasLength(100));
            return FunctionResponse(
                status: 200, data: {'version': 8, 'has_image': true});
          });
      expect(
          (await repo.replace(Uint8List(100), 7, 'request', session!.user.id))
              .version,
          8);
    });
    test('export captures caller, checks returned owner and keeps v12 payload',
        () async {
      final doc =
          validAccountDataExportJson(schemaVersion: 12, emptyCollections: true);
      session = fixtureSession((doc['auth_identity'] as Map)['id'] as String);
      doc['schema_version'] = 13;
      doc['avatar'] = null;
      final repo = AvatarAccountDataExportRepository(client,
          session: () => session,
          invoke: (method, headers, body, query) async {
            expect(method, 'post');
            expect(body, isNull);
            expect(query, isNull);
            expect(headers['x-request-id'], isNotEmpty);
            return FunctionResponse(status: 200, data: doc);
          });
      expect((await repo.exportOwnAccountData()).schemaVersion, 13);
    });
  });
  for (final hasImage in [false, true]) {
    test(
        'strict export v13 ${hasImage ? 'with photo' : 'without photo'} round trips',
        () {
      final doc =
          validAccountDataExportJson(schemaVersion: 12, emptyCollections: true)
            ..['schema_version'] = 13;
      doc['avatar'] = hasImage
          ? {
              'mime_type': 'image/png',
              'width': 256,
              'height': 256,
              'data_base64': base64Encode(thumbnail())
            }
          : null;
      expect(AccountDataExportDocument.fromJson(doc).toJson(), doc);
    });
  }
  test('old export versions never accept photo extension', () {
    final doc =
        validAccountDataExportJson(schemaVersion: 12, emptyCollections: true)
          ..['avatar'] = null;
    expect(() => AccountDataExportDocument.fromJson(doc),
        throwsA(isA<AccountDataExportFailure>()));
  });
  test('export rejects bearer URL and malformed thumbnail fields', () {
    final doc =
        validAccountDataExportJson(schemaVersion: 12, emptyCollections: true)
          ..['schema_version'] = 13;
    for (final avatar in [
      {'url': 'private'},
      {
        'mime_type': 'image/png',
        'width': 256,
        'height': 256,
        'data_base64': 'invalid'
      }
    ]) {
      doc['avatar'] = avatar;
      expect(() => AccountDataExportDocument.fromJson(doc),
          throwsA(isA<AccountDataExportFailure>()));
    }
  });
  for (final dark in [false, true]) {
    for (final locale in ['en', 'pt']) {
      testWidgets(
          'redesigned Profile integrates avatars, drafts and language $locale dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = Repository()..bytes = thumbnail();
        final registry = ReconciliationRegistry();
        final auth = FakeAuthRepository();
        addTearDown(auth.close);
        final profile = UserProfile(
            id: 'viewer',
            username: 'viewer',
            displayName: 'Viewer',
            onboardingCompletedAt: DateTime.utc(2026));
        await tester.pumpWidget(ProviderScope(
            overrides: [
              supabaseRuntimeReadyProvider.overrideWithValue(true),
              verifiedUserIdProvider.overrideWithValue('viewer'),
              profileAvatarRepositoryProvider.overrideWithValue(repo),
              avatarGalleryProvider.overrideWithValue(Gallery()),
              reconciliationRegistryProvider.overrideWithValue(registry),
              authRepositoryProvider.overrideWithValue(auth),
              profileRepositoryProvider
                  .overrideWithValue(FakeProfileRepository(profile: profile)),
              accountDataExportRepositoryProvider
                  .overrideWithValue(FakeAccountDataExportRepository()),
              accountDataExportShareServiceProvider
                  .overrideWithValue(FakeAccountDataExportShareService()),
              notificationRepositoryProvider
                  .overrideWithValue(FakeNotificationRepository()),
              publicTemplateModerationRepositoryProvider
                  .overrideWithValue(FakePublicTemplateModerationRepository()),
              languagePreferenceRepositoryProvider
                  .overrideWithValue(FakeLanguagePreferenceRepository()),
              themePreferenceRepositoryProvider
                  .overrideWithValue(FakeThemePreferenceRepository()),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: uiPreviewBoundary(child!),
              ),
              home: const ProfileScreen(),
            )));
        await tester.pumpAndSettle();
        final strings =
            AppLocalizations.of(tester.element(find.byType(ProfileScreen)));
        expect(find.text(strings.avatarUpdate), findsOneWidget);
        expect(find.byKey(const Key('removeAvatarButton')), findsOneWidget);
        expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).target,
            const AvatarTarget.profile('viewer'));
        await tester.runAsync(() => precacheImage(MemoryImage(repo.bytes!),
            tester.element(find.byType(ProfileAvatar))));
        await tester.pumpAndSettle();
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        await captureUiPreview(
            tester, 'avatar-profile-$locale-${dark ? 'dark' : 'light'}-large');
        final draft = find.byKey(const Key('profileDisplayName'));
        await tester.ensureVisible(draft);
        await tester.enterText(draft, 'Unsaved display name');
        repo.hasImage = false;
        repo.bytes = null;
        await registry.reconcile();
        await tester.pumpAndSettle();
        expect(find.text(strings.avatarAdd), findsOneWidget);
        expect(find.byKey(const Key('removeAvatarButton')), findsNothing);
        expect(tester.widget<TextField>(draft).controller!.text,
            'Unsaved display name');
        final language = find.byKey(const Key('languagePreference'));
        await tester.ensureVisible(language);
        await tester.pumpAndSettle();
        expect(language.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets(
          'avatar add/update/remove follows current metadata $locale dark=$dark',
          (tester) async {
        final repo = Repository()..hasImage = false;
        final gallery = Gallery()..bytes = null;
        final registry = ReconciliationRegistry();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              supabaseRuntimeReadyProvider.overrideWithValue(true),
              verifiedUserIdProvider.overrideWithValue('viewer'),
              profileAvatarRepositoryProvider.overrideWithValue(repo),
              avatarGalleryProvider.overrideWithValue(gallery),
              reconciliationRegistryProvider.overrideWithValue(registry),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AvatarEditorActions()),
            )));
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
            tester.element(find.byType(AvatarEditorActions)));
        expect(find.text(strings.avatarAdd), findsOneWidget);
        expect(find.byKey(const Key('removeAvatarButton')), findsNothing);
        await tester.tap(find.byKey(const Key('changeAvatarButton')));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        expect(find.text(strings.avatarSaved), findsNothing);
        expect(find.text(strings.avatarAdd), findsOneWidget);
        // Another device's current metadata controls which actions are offered.
        repo.hasImage = true;
        await registry.reconcile();
        await tester.pumpAndSettle();
        expect(find.text(strings.avatarUpdate), findsOneWidget);
        expect(find.byKey(const Key('removeAvatarButton')), findsOneWidget);
        repo.hasImage = false;
        await registry.reconcile();
        await tester.pumpAndSettle();
        expect(find.text(strings.avatarAdd), findsOneWidget);
        expect(find.byKey(const Key('removeAvatarButton')), findsNothing);
        expect(tester.takeException(), isNull);
      });
      testWidgets(
          'avatar actions $locale dark=$dark at 200% text remain accessible',
          (tester) async {
        final repo = Repository();
        final gallery = Gallery();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              supabaseRuntimeReadyProvider.overrideWithValue(true),
              verifiedUserIdProvider.overrideWithValue('viewer'),
              profileAvatarRepositoryProvider.overrideWithValue(repo),
              avatarGalleryProvider.overrideWithValue(gallery),
            ],
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(2)),
                    child: Scaffold(
                        body: SingleChildScrollView(
                            child: Column(children: [
                      ProfileAvatar(
                          label: 'Viewer',
                          target: AvatarTarget.profile('viewer')),
                      AvatarEditorActions()
                    ])))))));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('changeAvatarButton')));
        await tester.pumpAndSettle();
        expect(repo.writes, 1);
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final semantics = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }
  }
  test(
      'mounted avatar invalidates on account reconciliation and disposal unregisters',
      () async {
    final repo = Repository();
    final registry = ReconciliationRegistry();
    final container = ProviderContainer(overrides: [
      supabaseRuntimeReadyProvider.overrideWithValue(true),
      verifiedUserIdProvider.overrideWithValue('viewer'),
      profileAvatarRepositoryProvider.overrideWithValue(repo),
      reconciliationRegistryProvider.overrideWithValue(registry)
    ]);
    final sub = container.listen(
        avatarBytesProvider(const AvatarTarget.chat('message')), (_, __) {});
    await container
        .read(avatarBytesProvider(const AvatarTarget.chat('message')).future);
    expect(repo.reads, 1);
    await registry.reconcile();
    await container
        .read(avatarBytesProvider(const AvatarTarget.chat('message')).future);
    expect(repo.reads, 2);
    sub.close();
    container.dispose();
    await registry.reconcile();
    expect(repo.reads, 2);
  });
  testWidgets('authoritative access loss removes a mounted photo',
      (tester) async {
    final repo = Repository()..bytes = thumbnail();
    final registry = ReconciliationRegistry();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          supabaseRuntimeReadyProvider.overrideWithValue(true),
          verifiedUserIdProvider.overrideWithValue('viewer'),
          profileAvatarRepositoryProvider.overrideWithValue(repo),
          reconciliationRegistryProvider.overrideWithValue(registry),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: ProfileAvatar(
                    label: 'Viewer',
                    target: AvatarTarget.profile('viewer'))))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    repo.bytes = null;
    await registry.reconcile();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'avatar identity is stable on rebuild and fails closed during revalidation',
      (tester) async {
    final repo = Repository()..bytes = thumbnail();
    final registry = ReconciliationRegistry();
    final rebuild = ValueNotifier(0);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          supabaseRuntimeReadyProvider.overrideWithValue(true),
          verifiedUserIdProvider.overrideWithValue('viewer'),
          profileAvatarRepositoryProvider.overrideWithValue(repo),
          reconciliationRegistryProvider.overrideWithValue(registry),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (_, __, ___) => const ProfileAvatar(
              label: 'Viewer', target: AvatarTarget.profile('viewer')),
        )))));
    await tester.pumpAndSettle();
    final photo = tester.element(find.byType(Image));
    final size = tester.getSize(find.byType(ProfileAvatar));
    rebuild.value++;
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(Image)), same(photo));
    expect(repo.reads, 1);
    repo.pendingRead = Completer();
    await registry.reconcile();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(IdentityBadge), findsOneWidget);
    expect(tester.getSize(find.byType(ProfileAvatar)), size);
    repo.pendingRead!.completeError(const AvatarFailure());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(IdentityBadge), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    repo.pendingRead = null;
    repo.bytes = null;
    await registry.reconcile();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('old account read cannot populate a new provider generation', () async {
    final pending = Completer<Uint8List?>();
    final repo = Repository()..pendingRead = pending;
    final container = ProviderContainer(overrides: [
      supabaseRuntimeReadyProvider.overrideWithValue(true),
      verifiedUserIdProvider.overrideWithValue('viewer'),
      profileAvatarRepositoryProvider.overrideWithValue(repo),
    ]);
    final provider = avatarBytesProvider(const AvatarTarget.profile('viewer'));
    final subscription = container.listen(provider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    repo.pendingRead = null;
    container.updateOverrides([
      supabaseRuntimeReadyProvider.overrideWithValue(true),
      verifiedUserIdProvider.overrideWithValue('other'),
      profileAvatarRepositoryProvider.overrideWithValue(repo)
    ]);
    expect(await container.read(provider.future), isNull);
    pending.complete(thumbnail());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).valueOrNull, isNull);
    subscription.close();
    container.dispose();
  });
}
