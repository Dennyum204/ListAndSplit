import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/settings/data/shared_preferences_theme_preference_repository.dart';
import 'package:list_and_split/features/settings/domain/theme_preference.dart';
import 'package:list_and_split/features/settings/presentation/theme_preference_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_theme_preference_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = SharedPreferencesThemePreferenceRepository.storageKey;

  for (final value in [null, 'unknown', true, 42]) {
    test('missing or invalid stored preference $value defaults to system',
        () async {
      SharedPreferences.setMockInitialValues({if (value != null) key: value});
      expect(await SharedPreferencesThemePreferenceRepository().read(),
          ThemePreference.system);
    });
  }

  for (final preference in ThemePreference.values) {
    test('persists ${preference.name} across repository instances', () async {
      SharedPreferences.setMockInitialValues({'unrelated': 'preserve'});
      await SharedPreferencesThemePreferenceRepository().write(preference);
      expect(await SharedPreferencesThemePreferenceRepository().read(),
          preference);
      final storage = await SharedPreferences.getInstance();
      expect(storage.getString(key), preference.name);
      expect(storage.getString('unrelated'), 'preserve');
    });
  }

  test('restores saved preference and maps all Flutter modes', () async {
    final repository = FakeThemePreferenceRepository()
      ..preference = ThemePreference.dark;
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    expect(controller.state.isLoading, isTrue);
    await _flush();
    expect(controller.state.themeMode, ThemeMode.dark);
    await controller.select(ThemePreference.light);
    expect(controller.state.themeMode, ThemeMode.light);
    await controller.select(ThemePreference.system);
    expect(controller.state.themeMode, ThemeMode.system);
  });

  test('unavailable storage does not block startup or later selection',
      () async {
    final repository = FakeThemePreferenceRepository()..failRead = true;
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.preference, ThemePreference.system);
    await controller.select(ThemePreference.dark);
    expect(controller.state.preference, ThemePreference.dark);
  });

  test('initial restore cannot overwrite an accepted selection', () async {
    final repository = FakeThemePreferenceRepository()
      ..readGate = Completer<ThemePreference>();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.select(ThemePreference.light);
    expect(repository.writes, isEmpty);
    repository.readGate!.complete(ThemePreference.dark);
    await _flush();
    await controller.select(ThemePreference.light);
    expect(controller.state.preference, ThemePreference.light);
    expect(repository.writes, [ThemePreference.light]);
  });

  test('rapid selections cannot race or write the same choice twice', () async {
    final repository = FakeThemePreferenceRepository()
      ..writeGate = Completer<void>();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    final save = controller.select(ThemePreference.dark);
    expect(controller.state.preference, ThemePreference.dark);
    expect(controller.state.isSaving, isTrue);
    await controller.select(ThemePreference.dark);
    await controller.select(ThemePreference.light);
    expect(repository.writes, [ThemePreference.dark]);
    repository.writeGate!.complete();
    await save;
    await controller.select(ThemePreference.dark);
    expect(controller.state.isSaving, isFalse);
    expect(repository.writes, [ThemePreference.dark]);
  });

  test('save failure restores previous theme and permits retry', () async {
    final repository = FakeThemePreferenceRepository()..failWrite = true;
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    await controller.select(ThemePreference.dark);
    expect(controller.state.preference, ThemePreference.system);
    expect(controller.state.saveFailed, isTrue);
    expect(controller.state.isSaving, isFalse);
    repository.failWrite = false;
    await controller.select(ThemePreference.dark);
    expect(controller.state.preference, ThemePreference.dark);
    expect(controller.state.saveFailed, isFalse);
    expect(repository.writes, [ThemePreference.dark, ThemePreference.dark]);
  });

  test('controller disposal during restore is safe', () async {
    final repository = FakeThemePreferenceRepository()
      ..readGate = Completer<ThemePreference>();
    final controller = ThemePreferenceController(repository)..dispose();
    repository.readGate!.complete(ThemePreference.dark);
    await _flush();
    await controller.select(ThemePreference.light);
    expect(repository.writes, isEmpty);
  });

  for (final fails in [false, true]) {
    test('controller disposal during save is safe (failure: $fails)', () async {
      final repository = FakeThemePreferenceRepository()
        ..writeGate = Completer<void>()
        ..failWrite = fails;
      final controller = ThemePreferenceController(repository);
      await _flush();
      final save = controller.select(ThemePreference.dark);
      controller.dispose();
      repository.writeGate!.complete();
      await save;
    });
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
