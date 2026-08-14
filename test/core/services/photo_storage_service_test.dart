import 'dart:io';

import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final shotAt = DateTime(2026, 8, 8);

  test('DB용 경로는 상대경로이며 컨테이너 위치가 바뀌어도 해석된다', () async {
    final parent = await Directory.systemTemp.createTemp(
      'body_frame_storage_move_',
    );
    final oldRoot = Directory(p.join(parent.path, 'old'))..createSync();
    final service = PhotoStorageServiceImpl(rootPath: oldRoot.path);

    final absolute = await service.saveBytes(
      shotAt: shotAt,
      bytes: const [1, 2, 3],
      fileName: 'front.jpg',
    );
    final stored = await service.toStoredPath(absolute);
    expect(stored, 'photos/202608/front.jpg');

    final newRootPath = p.join(parent.path, 'new');
    await oldRoot.rename(newRootPath);
    final movedService = PhotoStorageServiceImpl(rootPath: newRootPath);

    final resolved = await movedService.resolvePath(stored);
    expect(await File(resolved).readAsBytes(), const [1, 2, 3]);

    // 기기 이전 등으로 컨테이너가 바뀌기 전 기록된 절대경로도 현재 root로
    // 옮겨 해석하며, 이전 절대경로 자체에는 접근하지 않는다.
    final legacyResolved = await movedService.resolvePath(absolute);
    expect(legacyResolved, resolved);

    await parent.delete(recursive: true);
  });

  test('촬영월별로 다른 디렉터리에 저장한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_bucket_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);

    final august = await service.saveBytes(
      shotAt: DateTime(2026, 8, 8),
      bytes: const [1],
      fileName: 'a.jpg',
    );
    final january = await service.saveBytes(
      shotAt: DateTime(2027, 1, 3),
      bytes: const [2],
      fileName: 'b.jpg',
    );

    expect(await service.toStoredPath(august), 'photos/202608/a.jpg');
    expect(await service.toStoredPath(january), 'photos/202701/b.jpg');

    await root.delete(recursive: true);
  });

  test('저장 경로가 photos root를 벗어나지 못한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_boundary_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);

    for (final storedPath in [
      '',
      '.',
      '..',
      '../outside.jpg',
      'photos/../outside.jpg',
      'photos/202608/../202609/outside.jpg',
      'photos/.staging/internal.partial',
      '/tmp/outside.jpg',
    ]) {
      await expectLater(
        service.resolvePath(storedPath),
        throwsA(isA<FormatException>()),
      );
    }

    final sentinel = File(p.join(root.path, 'sentinel.txt'));
    await sentinel.writeAsString('keep');
    await expectLater(
      service.deleteFile('../sentinel.txt'),
      throwsA(isA<FormatException>()),
    );
    expect(await sentinel.readAsString(), 'keep');

    await root.delete(recursive: true);
  });

  test('같은 파일명이 있으면 덮어쓰지 않고 접미사를 붙인다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_clobber_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);

    final first = await service.saveBytes(
      shotAt: shotAt,
      bytes: const [1],
      fileName: 'front.jpg',
    );
    final second = await service.saveBytes(
      shotAt: shotAt,
      bytes: const [2],
      fileName: 'front.jpg',
    );

    expect(first, isNot(second));
    expect(await File(first).readAsBytes(), const [1]);
    expect(await File(second).readAsBytes(), const [2]);

    await root.delete(recursive: true);
  });

  test('원본 복사는 바이트를 변형하지 않는다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_copy_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);
    final source = File(p.join(root.path, 'source.jpg'));
    final bytes = List<int>.generate(2048, (i) => i % 256);
    await source.writeAsBytes(bytes);

    final saved = await service.saveOriginal(
      shotAt: shotAt,
      sourcePath: source.path,
    );

    expect(await File(saved).readAsBytes(), bytes);
    // 원본은 그대로 남는다.
    expect(await source.readAsBytes(), bytes);

    await root.delete(recursive: true);
  });

  test('쓰기가 실패하면 staging만 정리하고 목적지에 파일을 남기지 않는다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_partial_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);

    await expectLater(
      service.saveOriginal(
        shotAt: shotAt,
        sourcePath: p.join(root.path, 'missing.jpg'),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final bucket = Directory(p.join(root.path, 'photos', '202608'));
    expect(bucket.existsSync() ? bucket.listSync() : const [], isEmpty);
    final staging = Directory(p.join(root.path, 'photos', '.staging'));
    expect(staging.existsSync() ? staging.listSync() : const [], isEmpty);

    await root.delete(recursive: true);
  });

  test('앱이 죽어 남은 staging 파일을 정리하고 저장된 원본은 건드리지 않는다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_staging_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);
    final saved = await service.saveBytes(
      shotAt: shotAt,
      bytes: const [1, 2, 3],
      fileName: 'front.jpg',
    );

    // rename으로 확정되기 전에 프로세스가 죽은 상황을 재현한다.
    final staging = Directory(p.join(root.path, 'photos', '.staging'))
      ..createSync(recursive: true);
    final leftover = File(p.join(staging.path, 'abandoned.partial'))
      ..writeAsBytesSync(const [9, 9, 9]);

    expect(await service.cleanupStagingLeftovers(), 1);
    expect(leftover.existsSync(), isFalse);
    // 정리 대상은 staging뿐이다. 관리 저장소의 원본은 그대로 남는다.
    expect(File(saved).existsSync(), isTrue);
    // 지울 것이 없으면 0을 돌려주고 조용히 끝난다.
    expect(await service.cleanupStagingLeftovers(), 0);

    await root.delete(recursive: true);
  });

  test('삭제한 파일은 저장소에서 사라지고 없는 파일 삭제는 무시한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_delete_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);
    final saved = await service.saveBytes(
      shotAt: shotAt,
      bytes: const [1],
      fileName: 'front.jpg',
    );
    final stored = await service.toStoredPath(saved);

    await service.deleteFile(stored);
    expect(await File(saved).exists(), isFalse);

    // 이미 지워진 경로를 다시 지워도 예외를 던지지 않는다.
    await service.deleteFile(stored);

    await root.delete(recursive: true);
  });
}
