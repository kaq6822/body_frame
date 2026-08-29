import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:body_frame/features/records/services/photo_export_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 공유는 플랫폼 채널(share_plus)을 타므로 테스트 VM에서는 실제 호출이 불가능하다.
/// 호출부를 주입해 성공·실패 양쪽 경로에서 파생 파일이 정리되는지 확인한다.
void main() {
  late Directory root;

  String shareDirPath() => p.join(root.path, PhotoExportSinkImpl.shareDirName);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_frame_photo_share_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('격자 합성본은 공유 시점에만 존재하고 성공 후 즉시 정리된다', () async {
    List<int>? sharedBytes;
    String? sharedName;
    Rect? receivedOrigin;
    final sink = PhotoExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {sharePositionOrigin}) async {
        expect(files, hasLength(1));
        // 공유 시트가 읽는 순간에는 파일이 있어야 한다.
        sharedBytes = await File(files.single.path).readAsBytes();
        sharedName = files.single.name;
        receivedOrigin = sharePositionOrigin;
      },
    );

    await sink.sharePng(
      Uint8List.fromList([1, 2, 3]),
      // 경로 구분자가 섞여도 전용 디렉터리를 벗어나지 않아야 한다.
      name: '../photo-1_grid',
      sharePositionOrigin: const Rect.fromLTWH(10, 20, 30, 40),
    );

    expect(sharedBytes, [1, 2, 3]);
    expect(sharedName, 'photo-1_grid.png');
    expect(receivedOrigin, const Rect.fromLTWH(10, 20, 30, 40));
    expect(await Directory(shareDirPath()).exists(), isFalse);
  });

  test('공유가 실패해도 격자 합성본을 남기지 않는다', () async {
    final sink = PhotoExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {sharePositionOrigin}) async {
        expect(await File(files.single.path).exists(), isTrue);
        throw StateError('injected share failure');
      },
    );

    await expectLater(
      sink.sharePng(Uint8List.fromList([9]), name: 'photo-1_grid'),
      throwsA(isA<StateError>()),
    );
    expect(await Directory(shareDirPath()).exists(), isFalse);
  });

  test('앞선 공유가 남긴 파일이 있으면 새 공유가 먼저 걷어낸다', () async {
    // 앱이 공유 도중 강제 종료된 상황을 재현한다.
    final leftoverDir = Directory(shareDirPath())..createSync(recursive: true);
    final leftover = File(p.join(leftoverDir.path, 'stale.png'))
      ..writeAsBytesSync(const [7]);

    final sink = PhotoExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {sharePositionOrigin}) async {
        expect(leftover.existsSync(), isFalse);
        expect(Directory(shareDirPath()).listSync(), hasLength(1));
      },
    );

    await sink.sharePng(Uint8List.fromList([1]), name: 'photo-1_grid');

    expect(await Directory(shareDirPath()).exists(), isFalse);
  });

  test('원본 공유는 저장소의 파일을 그대로 넘기고 파생 파일을 만들지 않는다', () async {
    final original = File(p.join(root.path, 'front.jpg'))
      ..writeAsBytesSync(const [1, 2]);
    String? sharedPath;
    Rect? receivedOrigin;
    final sink = PhotoExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {sharePositionOrigin}) async {
        sharedPath = files.single.path;
        receivedOrigin = sharePositionOrigin;
      },
    );

    await sink.shareOriginalFile(original.path);

    expect(sharedPath, original.path);
    // 원본은 공유 후에도 그대로 남는다.
    expect(original.existsSync(), isTrue);
    expect(await Directory(shareDirPath()).exists(), isFalse);
    // iPad popover는 비어 있지 않은 기준 사각형이 필수라 기본값을 채워 넘긴다.
    expect(receivedOrigin, const Rect.fromLTWH(0, 0, 1, 1));
  });

  test('비어 있는 기준 사각형은 기본값으로 대체한다', () async {
    Rect? receivedOrigin;
    final sink = PhotoExportSinkImpl(
      supportDirectoryProvider: () async => root,
      shareInvoker: (files, {sharePositionOrigin}) async {
        receivedOrigin = sharePositionOrigin;
      },
    );

    await sink.sharePng(
      Uint8List.fromList([1]),
      name: 'photo-1_grid',
      sharePositionOrigin: Rect.zero,
    );

    expect(receivedOrigin, const Rect.fromLTWH(0, 0, 1, 1));
  });
}
