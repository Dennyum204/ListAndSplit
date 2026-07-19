import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_controller.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fakes.dart';
import 'account_data_export_fixtures.dart';

final _testVerifiedUserIdProvider = StateProvider<String?>((ref) => 'user-1');

void main() {
  late FakeAccountDataExportRepository repository;
  late FakeAccountDataExportShareService shareService;
  late AccountDataExportController controller;

  setUp(() {
    repository = FakeAccountDataExportRepository()
      ..document = validAccountDataExportDocument();
    shareService = FakeAccountDataExportShareService();
    controller = AccountDataExportController(
      repository,
      shareService,
      hasVerifiedUser: true,
    );
  });

  tearDown(() {
    if (controller.mounted) controller.dispose();
  });

  test('moves through preparing and sharing and blocks duplicate taps',
      () async {
    final exportCompleter = Completer<AccountDataExportDocument>();
    final shareCompleter = Completer<AccountDataShareResult>();
    repository.completer = exportCompleter;
    shareService.completer = shareCompleter;

    final first = controller.download();
    expect(controller.state.stage, AccountDataExportStage.preparing);
    expect(await controller.download(), isFalse);
    expect(repository.exportCalls, 1);

    exportCompleter.complete(validAccountDataExportDocument());
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.stage, AccountDataExportStage.sharing);
    expect(shareService.shareCalls, 1);

    shareCompleter.complete(AccountDataShareResult.shared);
    expect(await first, isTrue);
    expect(controller.state.stage, AccountDataExportStage.idle);
    expect(controller.state.message, AccountDataExportMessage.shared);
  });

  test('reports share dismissal without treating it as success', () async {
    shareService.result = AccountDataShareResult.dismissed;

    expect(await controller.download(), isFalse);
    expect(controller.state.message, AccountDataExportMessage.dismissed);
  });

  test('maps RPC and share failures to the same safe state', () async {
    repository.failure = StateError('private RPC response');
    expect(await controller.download(), isFalse);
    expect(controller.state.message, AccountDataExportMessage.failed);

    repository.failure = null;
    shareService.failure = StateError('private local export');
    expect(await controller.download(), isFalse);
    expect(controller.state.message, AccountDataExportMessage.failed);
  });

  test('does not publish state after controller disposal', () async {
    final completer = Completer<AccountDataExportDocument>();
    repository.completer = completer;
    final pending = controller.download();

    controller.dispose();
    completer.complete(validAccountDataExportDocument());

    expect(await pending, isFalse);
    expect(shareService.shareCalls, 0);
  });

  test('rejects export without a verified session', () async {
    controller.dispose();
    controller = AccountDataExportController(
      repository,
      shareService,
      hasVerifiedUser: false,
    );

    expect(await controller.download(), isFalse);
    expect(repository.exportCalls, 0);
  });

  test('session identity replacement reconstructs and clears state', () async {
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWith(
          (ref) => ref.watch(_testVerifiedUserIdProvider),
        ),
        accountDataExportRepositoryProvider.overrideWithValue(repository),
        accountDataExportShareServiceProvider.overrideWithValue(shareService),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      accountDataExportControllerProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container
        .read(accountDataExportControllerProvider.notifier)
        .download();
    expect(
      container.read(accountDataExportControllerProvider).message,
      AccountDataExportMessage.shared,
    );

    container.read(_testVerifiedUserIdProvider.notifier).state = 'user-2';
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(accountDataExportControllerProvider),
      isA<AccountDataExportState>()
          .having((state) => state.stage, 'stage', AccountDataExportStage.idle)
          .having((state) => state.message, 'message', isNull),
    );
  });
}
