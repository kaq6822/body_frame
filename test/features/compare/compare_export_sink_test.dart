import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:body_frame/features/compare/services/compare_export_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_frame_compare_share_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('보호 디렉터리의 공유 PNG를 성공 후 즉시 정리하고 origin을 전달한다', () async {
    Rect? receivedOrigin;
    final sink = CompareExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {text, sharePositionOrigin}) async {
        expect(files, hasLength(1));
        expect(await File(files.single.path).readAsBytes(), [1, 2, 3]);
        expect(text, '공유 문구');
        receivedOrigin = sharePositionOrigin;
      },
    );

    await sink.share(
      Uint8List.fromList([1, 2, 3]),
      name: '../unsafe-name',
      text: '공유 문구',
      sharePositionOrigin: const Rect.fromLTWH(10, 20, 30, 40),
    );

    expect(receivedOrigin, const Rect.fromLTWH(10, 20, 30, 40));
    expect(await Directory('${root.path}/compare_share').exists(), isFalse);
  });

  test('공유 플러그인이 실패해도 파생 PNG를 정리한다', () async {
    final sink = CompareExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {text, sharePositionOrigin}) async {
        expect(await File(files.single.path).exists(), isTrue);
        throw StateError('injected share failure');
      },
    );

    await expectLater(
      sink.share(Uint8List.fromList([9]), name: 'result'),
      throwsA(isA<StateError>()),
    );
    expect(await Directory('${root.path}/compare_share').exists(), isFalse);
  });
}
