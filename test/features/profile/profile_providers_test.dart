import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/profile/domain/user_profile.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  test('profile loads when the initial session becomes verified', () async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profile),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });
    final loaded = Completer<UserProfile>();
    container.listen(
      ownProfileProvider,
      (previous, next) {
        final value = next.valueOrNull;
        if (value != null && !loaded.isCompleted) loaded.complete(value);
      },
      fireImmediately: true,
    );

    expect(
      await loaded.future.timeout(const Duration(seconds: 1)),
      same(FakeProfileRepository.completeProfile),
    );
    expect(profile.fetchCalls, 1);
  });
}
