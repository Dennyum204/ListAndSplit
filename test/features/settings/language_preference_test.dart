import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/settings/data/shared_preferences_language_preference_repository.dart';
import 'package:list_and_split/features/settings/domain/language_preference.dart';
import 'package:list_and_split/features/settings/presentation/language_preference_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_language_preference_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = SharedPreferencesLanguagePreferenceRepository.storageKey;

  for (final value in [null, 'unknown', true, 42]) {
    test('missing or invalid stored preference $value defaults to system',
        () async {
      SharedPreferences.setMockInitialValues({if (value != null) key: value});
      expect(await SharedPreferencesLanguagePreferenceRepository().read(),
          LanguagePreference.system);
    });
  }

  for (final preference in LanguagePreference.values) {
    test('persists ${preference.name} across repository instances', () async {
      SharedPreferences.setMockInitialValues({'unrelated': 'preserve'});
      await SharedPreferencesLanguagePreferenceRepository().write(preference);
      expect(await SharedPreferencesLanguagePreferenceRepository().read(),
          preference);
      final storage = await SharedPreferences.getInstance();
      expect(storage.getString(key), preference.name);
      expect(storage.getString('unrelated'), 'preserve');
    });
  }

  test('restores saved preference and maps all Flutter locales', () async {
    final repository = FakeLanguagePreferenceRepository()
      ..preference = LanguagePreference.pt;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    expect(controller.state.isLoading, isTrue);
    await _flush();
    expect(controller.state.locale, const Locale('pt'));
    await controller.select(LanguagePreference.en);
    expect(controller.state.locale, const Locale('en'));
    await controller.select(LanguagePreference.system);
    expect(controller.state.locale, null);
  });

  test('unavailable storage does not block startup or later selection',
      () async {
    final repository = FakeLanguagePreferenceRepository()..failRead = true;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.preference, LanguagePreference.system);
    await controller.select(LanguagePreference.pt);
    expect(controller.state.preference, LanguagePreference.pt);
  });

  test('initial restore cannot overwrite an accepted selection', () async {
    final repository = FakeLanguagePreferenceRepository()
      ..readGate = Completer<LanguagePreference>();
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.select(LanguagePreference.en);
    expect(repository.writes, isEmpty);
    repository.readGate!.complete(LanguagePreference.pt);
    await _flush();
    await controller.select(LanguagePreference.en);
    expect(controller.state.preference, LanguagePreference.en);
    expect(repository.writes, [LanguagePreference.en]);
  });

  test('System can be saved when the initial stored choice is unknown',
      () async {
    final repository = FakeLanguagePreferenceRepository()
      ..preference = LanguagePreference.pt
      ..failRead = true;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    expect(controller.state.readFailed, isTrue);
    await controller.select(LanguagePreference.system);
    expect(repository.preference, LanguagePreference.system);
    expect(controller.state.readFailed, isFalse);
    expect(repository.writes, [LanguagePreference.system]);
  });

  test('a failed acknowledgement reconciles the actual persisted language',
      () async {
    final repository = FakeLanguagePreferenceRepository()
      ..failAfterWrite = true;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    await controller.select(LanguagePreference.pt);
    expect(controller.state.preference, repository.preference);
    expect(controller.state.preference, LanguagePreference.pt);
    expect(controller.state.saveFailed, isTrue);
    expect(controller.state.readFailed, isFalse);
  });

  test(
      'failed recovery read is explicit and can restore the saved choice later',
      () async {
    final repository = FakeLanguagePreferenceRepository()
      ..preference = LanguagePreference.pt;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    repository
      ..failWrite = true
      ..failRead = true;
    await controller.select(LanguagePreference.en);
    expect(controller.state.preference, LanguagePreference.pt);
    expect(controller.state.readFailed, isTrue);
    repository.failRead = false;
    await controller.restore();
    expect(controller.state.preference, repository.preference);
    expect(controller.state.readFailed, isFalse);
  });

  test('rapid selections cannot race or write the same choice twice', () async {
    final repository = FakeLanguagePreferenceRepository()
      ..writeGate = Completer<void>();
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    final save = controller.select(LanguagePreference.pt);
    expect(controller.state.preference, LanguagePreference.pt);
    expect(controller.state.isSaving, isTrue);
    await controller.select(LanguagePreference.pt);
    await controller.select(LanguagePreference.en);
    expect(repository.writes, [LanguagePreference.pt]);
    repository.writeGate!.complete();
    await save;
    await controller.select(LanguagePreference.pt);
    expect(controller.state.isSaving, isFalse);
    expect(repository.writes, [LanguagePreference.pt]);
  });

  test('save failure restores previous language and permits retry', () async {
    final repository = FakeLanguagePreferenceRepository()..failWrite = true;
    final controller = LanguagePreferenceController(repository);
    addTearDown(controller.dispose);
    await _flush();
    await controller.select(LanguagePreference.pt);
    expect(controller.state.preference, LanguagePreference.system);
    expect(controller.state.saveFailed, isTrue);
    expect(controller.state.isSaving, isFalse);
    repository.failWrite = false;
    await controller.select(LanguagePreference.pt);
    expect(controller.state.preference, LanguagePreference.pt);
    expect(controller.state.saveFailed, isFalse);
    expect(repository.writes, [LanguagePreference.pt, LanguagePreference.pt]);
  });

  test('controller disposal during restore is safe', () async {
    final repository = FakeLanguagePreferenceRepository()
      ..readGate = Completer<LanguagePreference>();
    final controller = LanguagePreferenceController(repository)..dispose();
    repository.readGate!.complete(LanguagePreference.pt);
    await _flush();
    await controller.select(LanguagePreference.en);
    expect(repository.writes, isEmpty);
  });

  for (final fails in [false, true]) {
    test('controller disposal during save is safe (failure: $fails)', () async {
      final repository = FakeLanguagePreferenceRepository()
        ..writeGate = Completer<void>()
        ..failWrite = fails;
      final controller = LanguagePreferenceController(repository);
      await _flush();
      final save = controller.select(LanguagePreference.pt);
      controller.dispose();
      repository.writeGate!.complete();
      await save;
    });
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
