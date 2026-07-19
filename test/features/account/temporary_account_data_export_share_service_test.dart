import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/account/data/temporary_account_data_export_share_service.dart';
import 'package:list_and_split/features/account/domain/account_data_export.dart';
import 'package:list_and_split/features/account/domain/account_data_export_share_service.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'account_data_export_fixtures.dart';

void main() {
  late List<_WriteCall> writes;
  late List<XFile> sharedFiles;
  late Rect? sharedOrigin;
  late ShareResult shareResult;
  late Object? writeFailure;
  late Object? shareFailure;
  late TemporaryAccountDataExportShareService service;

  setUp(() {
    writes = [];
    sharedFiles = [];
    sharedOrigin = null;
    shareResult = const ShareResult('destination', ShareResultStatus.success);
    writeFailure = null;
    shareFailure = null;
    service = TemporaryAccountDataExportShareService(
      temporaryDirectory: () async => Directory('private-cache'),
      writeFile: (path, bytes) async {
        if (writeFailure != null) throw writeFailure!;
        writes.add(_WriteCall(path, List.unmodifiable(bytes)));
      },
      nativeShare: (files, {sharePositionOrigin}) async {
        if (shareFailure != null) throw shareFailure!;
        sharedFiles = List.unmodifiable(files);
        sharedOrigin = sharePositionOrigin;
        return shareResult;
      },
    );
  });

  test('writes deterministic pretty UTF-8 JSON to temporary cache', () async {
    final document = validAccountDataExportDocument();

    await service.share(document);
    final firstBytes = writes.single.bytes;
    final output = utf8.decode(firstBytes);

    expect(output, startsWith('{\n  "product": "list_and_split",'));
    expect(output, endsWith('\n'));
    expect(jsonDecode(output), document.toJson());
    expect(writes.single.path, startsWith('private-cache'));
    expect(
      writes.single.path,
      endsWith('list-and-split-data-export-20260719T085810Z.json'),
    );

    writes.clear();
    await service.share(document);
    expect(writes.single.bytes, firstBytes);
  });

  test('shares one JSON MIME file with the supplied iPad origin', () async {
    const origin = AccountDataShareOrigin(
      left: 10,
      top: 20,
      width: 120,
      height: 48,
    );

    expect(
      await service.share(validAccountDataExportDocument(), origin: origin),
      AccountDataShareResult.shared,
    );
    expect(sharedFiles, hasLength(1));
    expect(sharedFiles.single.mimeType, 'application/json');
    expect(sharedOrigin, const Rect.fromLTWH(10, 20, 120, 48));
  });

  test('uses only a privacy-safe filename', () {
    final filename = TemporaryAccountDataExportShareService.filenameFor(
      DateTime.parse('2026-07-19T10:58:10.000+02:00'),
    );

    expect(filename, 'list-and-split-data-export-20260719T085810Z.json');
    expect(filename, isNot(contains('alpha_user')));
    expect(filename, isNot(contains('example.test')));
    expect(filename, isNot(contains('11111111')));
  });

  test('distinguishes share dismissal from completion', () async {
    shareResult = const ShareResult('', ShareResultStatus.dismissed);
    expect(
      await service.share(validAccountDataExportDocument()),
      AccountDataShareResult.dismissed,
    );

    shareResult = ShareResult.unavailable;
    expect(
      await service.share(validAccountDataExportDocument()),
      AccountDataShareResult.shared,
    );
  });

  test('maps file write and native share failures safely', () async {
    writeFailure = StateError('private file content');
    await expectLater(
      service.share(validAccountDataExportDocument()),
      throwsA(isA<AccountDataExportFailure>()),
    );
    expect(sharedFiles, isEmpty);

    writeFailure = null;
    shareFailure = StateError('private share content');
    try {
      await service.share(validAccountDataExportDocument());
      fail('share failure should be mapped');
    } catch (error) {
      expect(error, isA<AccountDataExportFailure>());
      expect(error.toString(), isNot(contains('private share content')));
    }
  });
}

class _WriteCall {
  const _WriteCall(this.path, this.bytes);

  final String path;
  final List<int> bytes;
}
