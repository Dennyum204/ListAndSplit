import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/account/domain/account_data_export_repository.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';

enum AccountDataExportStage { idle, preparing, sharing }

enum AccountDataExportMessage { shared, dismissed, failed }

class AccountDataExportState {
  const AccountDataExportState({
    this.stage = AccountDataExportStage.idle,
    this.message,
  });

  final AccountDataExportStage stage;
  final AccountDataExportMessage? message;

  bool get isBusy => stage != AccountDataExportStage.idle;
}

class AccountDataExportController
    extends StateNotifier<AccountDataExportState> {
  AccountDataExportController(
    this._repository,
    this._shareService, {
    required bool hasVerifiedUser,
  })  : _hasVerifiedUser = hasVerifiedUser,
        super(const AccountDataExportState());

  final AccountDataExportRepository _repository;
  final AccountDataExportShareService _shareService;
  final bool _hasVerifiedUser;

  Future<bool> download({AccountDataShareOrigin? origin}) async {
    if (state.isBusy || !_hasVerifiedUser) return false;
    state = const AccountDataExportState(
      stage: AccountDataExportStage.preparing,
    );

    try {
      final document = await _repository.exportOwnAccountData();
      if (!mounted) return false;
      state = const AccountDataExportState(
        stage: AccountDataExportStage.sharing,
      );
      final result = await _shareService.share(document, origin: origin);
      if (!mounted) return false;
      state = AccountDataExportState(
        message: result == AccountDataShareResult.dismissed
            ? AccountDataExportMessage.dismissed
            : AccountDataExportMessage.shared,
      );
      return result == AccountDataShareResult.shared;
    } catch (_) {
      if (mounted) {
        state = const AccountDataExportState(
          message: AccountDataExportMessage.failed,
        );
      }
      return false;
    }
  }
}
