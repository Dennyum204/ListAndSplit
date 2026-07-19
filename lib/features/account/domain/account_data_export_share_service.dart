import 'package:list_and_split/features/account/domain/account_data_export.dart';

enum AccountDataShareResult { shared, dismissed }

class AccountDataShareOrigin {
  const AccountDataShareOrigin({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

abstract interface class AccountDataExportShareService {
  Future<AccountDataShareResult> share(
    AccountDataExportDocument document, {
    AccountDataShareOrigin? origin,
  });
}
