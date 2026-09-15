import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:list_and_split/app/startup/startup_host.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import '../support/ui_preview_capture.dart';

void main() {
  const channel = MethodChannel('com.ferbatech.listandsplit/startup');
  setUpAll(prepareUiPreviewFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('initialized app has a root scope independent of welcome',
      (tester) async {
    // Like the router, an ordinary unscoped dependent provider must resolve the
    // configured app root, never a notLoaded ancestor belonging to the cover.
    final dependent = Provider<bool>(
        (ref) => ref.watch(appConfigurationProvider).isConfigured);
    final ready = Completer<Widget>();
    await tester.pumpWidget(StartupHost(initialize: () => ready.future));
    await tester.pump();
    expect(tester.takeException(), isNull);
    ready.complete(ProviderScope(
        overrides: [
          appConfigurationProvider
              .overrideWithValue(const AppConfiguration.devConfigured()),
        ],
        child: Consumer(
            builder: (context, ref, _) => MaterialApp(
                  home: Text(ref.watch(dependent)
                      ? 'Configured destination'
                      : 'Wrong root'),
                ))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Configured destination'), findsOneWidget);
    final element = tester.element(find.text('Configured destination'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Wrong root'), findsNothing);
    expect(tester.element(find.text('Configured destination')), same(element));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'initialization is concurrent, destination widget survives cover and resume',
      (tester) async {
    final ready = Completer<Widget>();
    var started = 0;
    await tester.pumpWidget(ProviderScope(child: StartupHost(initialize: () {
      started++;
      return ready.future;
    })));
    expect(started, 1);
    expect(find.byType(WelcomeApp), findsOneWidget);
    ready.complete(
        const MaterialApp(home: Scaffold(body: Text('Restored route'))));
    await tester.pump();
    await tester.pump();
    final appElement = tester.element(find.text('Restored route'));
    expect(find.byType(WelcomeApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(WelcomeApp), findsNothing);
    expect(tester.element(find.text('Restored route')), same(appElement));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(WelcomeApp), findsNothing);
    expect(started, 1);
  });
  for (final reduced in [false, true]) {
    testWidgets(
        'urgent destination / reduced motion bypass before three seconds reduced=$reduced',
        (tester) async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => !reduced);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(ProviderScope(
          child: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: StartupHost(
                  initialize: () async =>
                      const MaterialApp(home: Text('Destination'))))));
      await tester.pump();
      await tester.pump();
      expect(find.byType(WelcomeApp), findsNothing);
      expect(find.text('Destination'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('startup error is recoverable without another timed cover',
      (tester) async {
    var attempts = 0;
    await tester
        .pumpWidget(ProviderScope(child: StartupHost(initialize: () async {
      if (++attempts == 1) throw StateError('redacted');
      return const MaterialApp(home: Text('Ready'));
    })));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('redacted'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(WelcomeApp), findsNothing);
  });
  for (final locale in ['en', 'pt']) {
    testWidgets('welcome $locale remains readable at 200 percent text',
        (tester) async {
      SharedPreferences.setMockInitialValues({'language.locale': locale});
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(
          child: uiPreviewBoundary(const WelcomeApp(reducedMotion: true))));
      await tester.pumpAndSettle();
      expect(
          find.text(locale == 'en'
              ? 'Good to have you here.'
              : 'Que bom ter-te por aqui.'),
          findsOneWidget);
      await captureUiPreview(tester, 'welcome-$locale-large');
      expect(tester.takeException(), isNull);
    });
  }
}
