import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/push/domain/push_repository.dart';
import 'package:list_and_split/features/push/presentation/push_controller.dart';
import 'package:list_and_split/features/push/presentation/push_providers.dart';
import 'package:list_and_split/features/push/presentation/push_settings_card.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

void main() {
  late _Platform platform;
  late _Repository repository;
  late PushController controller;
  late List<PushDestination> destinations;
  setUp(() {
    platform = _Platform();
    repository = _Repository();
    destinations = [];
    controller =
        PushController(platform, repository, onDestination: destinations.add);
  });
  tearDown(() async {
    if (controller.mounted) controller.dispose();
    await platform.stream.close();
  });
  for (final locale in ['en', 'pt']) {
    for (final dark in [false, true]) {
      testWidgets(
          'push settings remain operable at 200 percent $locale dark=$dark',
          (tester) async {
        await controller.setAccount('a', locale);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              supabaseRuntimeReadyProvider.overrideWithValue(true),
              pushControllerProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp(
                locale: Locale(locale),
                theme: dark ? AppTheme.dark : AppTheme.light,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(2)),
                    child: Scaffold(
                        body: SingleChildScrollView(
                            child: PushSettingsCard()))))));
        await tester.pumpAndSettle();
        final toggle = find.byType(SwitchListTile);
        final strings = AppLocalizations.of(tester.element(toggle));
        expect(find.text(strings.pushExplanation), findsOneWidget);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  test('permission is never requested merely by signing in', () async {
    await controller.setAccount('a', 'en');
    expect(platform.permissionRequests, 0);
    expect(controller.state.enabled, false);
    await controller.setEnabled(true);
    expect(platform.permissionRequests, 1);
    expect(controller.state.enabled, true);
    expect(repository.registrations, ['a:binding-a']);
    expect(platform.confirmed, ['binding-a']);
  });
  test('denial and local disable stop alerts without clearing account data',
      () async {
    platform.permission = false;
    await controller.setAccount('a', 'pt');
    await controller.setEnabled(true);
    expect(repository.registrations, isEmpty);
    expect(controller.state.permission, false);
    platform.permission = true;
    await controller.setEnabled(true);
    repository.failure = true;
    await controller.setEnabled(false);
    expect(platform.localEnabled, false);
    expect(controller.state.enabled, false);
    expect(controller.state.failed, true);
  });
  test('failed enrollment is recoverable; duplicate taps do not register twice',
      () async {
    await controller.setAccount('a', 'en');
    repository.pending = Completer<void>();
    final enabling = controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await controller.setEnabled(true);
    expect(repository.registrations, hasLength(1));
    repository.pending!.completeError(StateError('offline'));
    await enabling;
    expect(controller.state.failed, true);
    expect(controller.state.enabled, false);
    expect(platform.localEnabled, false);
    repository.pending = null;
    await controller.refresh();
    expect(controller.state.enabled, true);
    expect(controller.state.failed, false);
  });
  test('late registration cannot reactivate the previous account', () async {
    await controller.setAccount('a', 'en');
    repository.pending = Completer<void>();
    final enabling = controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    final old = repository.pending!;
    repository.pending = null;
    await controller.setAccount('b', 'en');
    old.complete();
    await enabling;
    expect(platform.account, 'b');
    expect(platform.confirmed, isEmpty);
    expect(controller.state.enabled, false);
  });
  test(
      'token changes coalesce behind a registration and confirm latest binding',
      () async {
    platform.desired = true;
    repository.pending = Completer<void>();
    final loading = controller.setAccount('a', 'en');
    await Future<void>.delayed(Duration.zero);
    platform.stream.add(null);
    platform.stream.add(null);
    await Future<void>.delayed(Duration.zero);
    final pending = repository.pending!;
    repository.pending = null;
    pending.complete();
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(repository.registrations, hasLength(2));
    expect(controller.state.enabled, true);
  });
  test('logout clears native binding before a failed server unregister',
      () async {
    platform.desired = true;
    await controller.setAccount('a', 'en');
    repository.failure = true;
    await controller.stopBeforeSignOut();
    expect(platform.account, isNull);
    expect(platform.localEnabled, false);
    expect(controller.state.enabled, false);
    platform.stream.add(const PushTap('old', 'binding-a', 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations, isEmpty);
  });
  test('routing is deduplicated, account-bound and rechecks missing access',
      () async {
    await controller.setAccount('a', 'en');
    platform.stream.add(const PushTap('x', 'binding-b', 'b'));
    platform.stream.add(const PushTap('x', 'wrong', 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.resolves, 0);
    platform.stream.add(const PushTap('one', 'binding-a', 'a'));
    platform.stream.add(const PushTap('one', 'binding-a', 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations, hasLength(1));
    expect(repository.resolves, 1);
    repository.destination = null;
    platform.stream.add(const PushTap('missing', 'binding-a', 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations, hasLength(1));
  });
  test('account switch during destination lookup discards old route', () async {
    await controller.setAccount('a', 'en');
    repository.routePending = Completer<PushDestination?>();
    platform.stream.add(const PushTap('one', 'binding-a', 'a'));
    await Future<void>.delayed(Duration.zero);
    await controller.setAccount('b', 'pt');
    repository.routePending!.complete(const PushDestination('notification'));
    await Future<void>.delayed(Duration.zero);
    expect(destinations, isEmpty);
  });
  test('unconfigured platform never sends registrations or asks permission',
      () async {
    platform.available = false;
    await controller.setAccount('a', 'en');
    await controller.setEnabled(true);
    expect(repository.registrations, isEmpty);
    expect(platform.permissionRequests, 0);
    expect(controller.state.available, false);
  });
}

class _Platform implements PushPlatform {
  final stream = StreamController<PushTap?>.broadcast();
  bool available = true,
      permission = true,
      desired = false,
      localEnabled = false;
  int permissionRequests = 0;
  String? account;
  final confirmed = <String>[];
  PushBinding get binding => PushBinding(
      available: available,
      permission: permission,
      enabled: desired,
      installation: 'installation',
      binding: 'binding-$account',
      token: desired && permission ? 'token' : null);
  @override
  Stream<PushTap?> get events => stream.stream;
  @override
  Future<PushBinding?> bind(String? value, String language) async {
    if (account != null && account != value) desired = false;
    account = value;
    if (value == null) {
      localEnabled = false;
      return null;
    }
    return binding;
  }

  @override
  Future<PushBinding> enable() async {
    permissionRequests++;
    desired = permission;
    return binding;
  }

  @override
  Future<PushBinding> disable() async {
    desired = false;
    localEnabled = false;
    return binding;
  }

  @override
  Future<void> confirm(String id) async {
    if (id == binding.binding) {
      confirmed.add(id);
      localEnabled = true;
    }
  }

  @override
  Future<PushTap?> takeTap() async => null;
  @override
  Future<void> visibleChat(String? list) async {}
  @override
  Future<void> openSettings() async {}
}

class _Repository implements PushRepository {
  final registrations = <String>[];
  bool failure = false;
  int resolves = 0;
  Completer<void>? pending;
  Completer<PushDestination?>? routePending;
  PushDestination? destination = const PushDestination('notification');
  @override
  Future<void> register(String account, PushBinding binding) async {
    registrations.add('$account:${binding.binding}');
    if (failure) throw StateError('offline');
    await pending?.future;
  }

  @override
  Future<void> unregister(String account, PushBinding binding) async {
    if (failure) throw StateError('offline');
  }

  @override
  Future<PushDestination?> resolve(PushTap tap) async {
    resolves++;
    return routePending == null ? destination : await routePending!.future;
  }
}
