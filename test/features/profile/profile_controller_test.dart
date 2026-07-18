import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/profile/domain/profile_repository.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeProfileRepository repository;
  late int changeCount;
  late ProfileController controller;

  setUp(() {
    repository = FakeProfileRepository();
    changeCount = 0;
    controller = ProfileController(
      repository,
      onProfileChanged: () => changeCount += 1,
    );
  });

  tearDown(() => controller.dispose());

  test('onboarding validates and sends canonical values', () async {
    expect(
      await controller.completeOnboarding(
        username: '1bad',
        displayName: ' ',
      ),
      isFalse,
    );
    expect(
      controller.state.fieldErrors[ProfileField.username],
      ProfileValidationIssue.usernameInvalid,
    );
    expect(repository.completeCalls, 0);

    expect(
      await controller.completeOnboarding(
        username: ' Fernando_1 ',
        displayName: '  Fernando Pereira  ',
      ),
      isTrue,
    );
    expect(repository.lastUsername, 'fernando_1');
    expect(repository.lastDisplayName, 'Fernando Pereira');
    expect(changeCount, 1);
  });

  test('reports a duplicate username without exposing backend details',
      () async {
    repository.failure =
        const ProfileFailure(ProfileFailureCode.usernameUnavailable);

    expect(
      await controller.completeOnboarding(
        username: 'fernando_1',
        displayName: 'Fernando',
      ),
      isFalse,
    );
    expect(
      controller.state.message,
      ProfileActionMessage.usernameUnavailable,
    );
  });

  test('profile editing changes only the display name', () async {
    repository = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    controller.dispose();
    controller = ProfileController(
      repository,
      onProfileChanged: () => changeCount += 1,
    );

    expect(await controller.updateDisplayName('  Fer  '), isTrue);
    expect(repository.updateCalls, 1);
    expect(repository.completeCalls, 0);
    expect(repository.lastDisplayName, 'Fer');
    expect(repository.profile.username, 'fernando_1');
  });
}
