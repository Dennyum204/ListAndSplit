import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef AccountTemporaryDirectory = Future<Directory> Function();
typedef AccountExportFileWriter = Future<void> Function(
  String path,
  List<int> bytes,
);
typedef AccountExportNativeShare = Future<ShareResult> Function(
  List<XFile> files, {
  Rect? sharePositionOrigin,
});

class TemporaryAccountDataExportShareService
    implements AccountDataExportShareService {
  TemporaryAccountDataExportShareService({
    AccountTemporaryDirectory? temporaryDirectory,
    AccountExportFileWriter? writeFile,
    AccountExportNativeShare? nativeShare,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _writeFile = writeFile ?? _writeFileBytes,
        _nativeShare = nativeShare ?? _shareFiles;

  final AccountTemporaryDirectory _temporaryDirectory;
  final AccountExportFileWriter _writeFile;
  final AccountExportNativeShare _nativeShare;

  @override
  Future<AccountDataShareResult> share(
    AccountDataExportDocument document, {
    AccountDataShareOrigin? origin,
  }) async {
    try {
      final directory = await _temporaryDirectory();
      final filename = filenameFor(document.exportedAt);
      final separator = Platform.pathSeparator;
      final path = '${directory.path}'
          '${directory.path.endsWith(separator) ? '' : separator}'
          '$filename';
      final encoded = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n',
      );
      await _writeFile(path, encoded);
      final shareResult = await _nativeShare(
        [XFile(path, mimeType: 'application/json')],
        sharePositionOrigin: origin == null
            ? null
            : Rect.fromLTWH(
                origin.left,
                origin.top,
                origin.width,
                origin.height,
              ),
      );
      return shareResult.status == ShareResultStatus.dismissed
          ? AccountDataShareResult.dismissed
          : AccountDataShareResult.shared;
    } catch (_) {
      throw const AccountDataExportFailure();
    }
  }

  static String filenameFor(DateTime exportedAt) {
    final utc = exportedAt.toUtc();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'list-and-split-data-export-'
        '${utc.year.toString().padLeft(4, '0')}'
        '${twoDigits(utc.month)}'
        '${twoDigits(utc.day)}T'
        '${twoDigits(utc.hour)}'
        '${twoDigits(utc.minute)}'
        '${twoDigits(utc.second)}Z.json';
  }

  static Future<void> _writeFileBytes(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static Future<ShareResult> _shareFiles(
    List<XFile> files, {
    Rect? sharePositionOrigin,
  }) {
    return Share.shareXFiles(
      files,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
