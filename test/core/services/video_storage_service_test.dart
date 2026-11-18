import 'dart:io';

import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/core/services/app_logger.dart';
import 'package:bodymark/core/services/video_storage_service.dart';
import 'package:bodymark/features/videos/video_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late VideoStorageServiceImpl service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bodymark_video_');
    service = VideoStorageServiceImpl(rootPath: root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> source(String name, List<int> bytes) async {
    final dir = await Directory(p.join(root.path, 'cache')).create();
    return File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
  }

  test('원본 바이트를 그대로 videos/{yyyyMM}/{uuid}.{확장자}에 복사한다', () async {
    final bytes = List<int>.generate(300000, (i) => i % 251);
    final src = await source('lesson.MOV', bytes);

    final saved = await service.saveOriginal(
      capturedAt: DateTime(2026, 11, 4, 15),
      sourcePath: src.path,
    );

    expect(await File(saved).readAsBytes(), bytes);
    // 원본(임시 파일)은 건드리지 않는다. 정리는 호출부 몫이다.
    expect(await src.exists(), isTrue);
    final stored = await service.toStoredPath(saved);
    expect(stored, matches(RegExp(r'^videos/202611/[0-9a-f-]{36}\.mov$')));
    expect(await service.resolvePath(stored), saved);
    final staging = Directory(
      p.join(
        root.path,
        PhotoStorageServiceImpl.rootDirName,
        PhotoStorageServiceImpl.stagingDirName,
      ),
    );
    expect(await staging.list().toList(), isEmpty);
  });

  test('원본이 없으면 실패하고 저장소와 staging에 아무것도 남기지 않는다', () async {
    await expectLater(
      service.saveOriginal(
        capturedAt: DateTime(2026, 11, 4),
        sourcePath: p.join(root.path, 'missing.mp4'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    final videos = Directory(p.join(root.path, 'videos'));
    final files = await videos.exists()
        ? (await videos.list(recursive: true).toList())
              .whereType<File>()
              .toList()
        : <File>[];
    expect(files, isEmpty);
  });

  test('남은 동영상 staging은 사진 저장소의 시작 정리가 함께 지운다', () async {
    final photos = PhotoStorageServiceImpl(rootPath: root.path);
    final staging = await Directory(
      p.join(
        root.path,
        PhotoStorageServiceImpl.rootDirName,
        PhotoStorageServiceImpl.stagingDirName,
      ),
    ).create(recursive: true);
    await File(p.join(staging.path, 'video.partial')).writeAsBytes([1, 2, 3]);

    expect(await photos.cleanupStagingLeftovers(), 1);
    expect(await staging.list().toList(), isEmpty);
  });

  test('경로 해석은 앞부분을 신뢰하지 않고 videos/ 이하만 다시 붙인다', () async {
    final moved = await service.resolvePath(
      '/var/mobile/Containers/OLD/Documents/videos/202611/a.mp4',
    );
    expect(moved, p.join(root.path, 'videos', '202611', 'a.mp4'));

    for (final bad in [
      'photos/202611/a.jpg',
      'videos/202611/../../photos/a.jpg',
      'videos/a.mp4',
      'videos/2026xx/a.mp4',
      'videos/202611/sub/a.mp4',
      '/tmp/cache/a.mp4',
      '',
    ]) {
      await expectLater(
        service.resolvePath(bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('삭제는 저장소 파일만 지우고 없는 파일은 무시한다', () async {
    final src = await source('a.mp4', [1, 2, 3]);
    final saved = await service.saveOriginal(
      capturedAt: DateTime(2026, 11, 4),
      sourcePath: src.path,
    );
    final stored = await service.toStoredPath(saved);
    await service.deleteFile(stored);
    expect(await File(saved).exists(), isFalse);
    await service.deleteFile(stored);
    await expectLater(service.deleteFile(src.path), throwsFormatException);
    expect(await src.exists(), isTrue);
  });

  test('picker 사본은 앱 임시 디렉터리 안일 때만 지운다', () async {
    final temp = await Directory(p.join(root.path, 'cache')).create();
    final copy = await File(
      p.join(temp.path, 'image_picker_1.mp4'),
    ).writeAsBytes([1]);
    final gallery = await Directory(p.join(root.path, 'DCIM')).create();
    final original = await File(
      p.join(gallery.path, 'lesson.mp4'),
    ).writeAsBytes([1]);
    final sneaky = p.join(temp.path, '..', 'DCIM', 'lesson.mp4');

    for (final path in [original.path, sneaky]) {
      await deletePickerCopyBestEffort(
        path,
        roots: [temp.path],
        logger: AppLogger.instance,
      );
    }
    expect(await original.exists(), isTrue);

    await deletePickerCopyBestEffort(
      copy.path,
      roots: [temp.path],
      logger: AppLogger.instance,
    );
    expect(await copy.exists(), isFalse);
    // 없는 파일은 조용히 넘어간다.
    await deletePickerCopyBestEffort(
      copy.path,
      roots: [temp.path],
      logger: AppLogger.instance,
    );
  });
}
