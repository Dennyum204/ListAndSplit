import 'package:list_and_split/features/account/domain/account_data_export.dart';

abstract interface class AccountDataExportRepository {
  Future<AccountDataExportDocument> exportOwnAccountData();
}
