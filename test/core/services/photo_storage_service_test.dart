import 'dart:convert';
import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DB용 경로는 상대경로이며 컨테이너 위치가 바뀌어도 해석된다', () async {
    final parent = await Directory.systemTemp.createTemp(
      'body_frame_storage_move_',
    );
    final oldRoot = Directory(p.join(parent.path, 'old'))..createSync();
    final service = PhotoStorageServiceImpl(rootPath: oldRoot.path);

    final absolute = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [1, 2, 3],
      fileName: 'front.jpg',
    );
    final stored = await service.toStoredPath(absolute);
    expect(stored, 'photos/member-1/front.jpg');

    final newRootPath = p.join(parent.path, 'new');
    await oldRoot.rename(newRootPath);
    final movedService = PhotoStorageServiceImpl(rootPath: newRootPath);

    final resolved = await movedService.resolvePath(stored);
    expect(await File(resolved).readAsBytes(), const [1, 2, 3]);

    // v1 DB에 남아 있을 수 있는 이전 컨테이너 절대경로도 현재 root로 옮겨
    // 해석하며, 이전 절대경로 자체에는 접근하지 않는다.
    final legacyResolved = await movedService.resolvePath(absolute);
    expect(legacyResolved, resolved);

    await parent.delete(recursive: true);
  });

  test('회원 id와 저장 경로가 photos root를 벗어나지 못한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_boundary_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);

    for (final memberId in ['', '.', '..', '../outside', '/outside', r'..\x']) {
      await expectLater(
        service.memberDir(memberId),
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );
    }
    for (final storedPath in [
      '',
      '.',
      '..',
      '../outside.jpg',
      'photos/../outside.jpg',
      'photos/member-a/../member-b/outside.jpg',
      'photos/.quarantine/payloads/internal',
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

  test('완성 파일만 원자적으로 게시하고 재시작 시 DB 미참조 파일을 정리한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_orphan_',
    );
    final writer = PhotoStorageServiceImpl(rootPath: root.path);
    final referenced = await writer.saveBytes(
      memberId: 'member-1',
      bytes: const [1, 2, 3],
      fileName: 'referenced.jpg',
    );
    final orphan = await writer.saveBytes(
      memberId: 'member-1',
      bytes: const [4, 5, 6],
      fileName: 'orphan.jpg',
    );
    final staging = File(
      p.join(root.path, 'photos', '.staging', 'interrupted.partial'),
    );
    await staging.parent.create(recursive: true);
    await staging.writeAsBytes(const [9]);

    final restarted = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantineReferencesLoader: () async => StorageQuarantineReferences(
        storedFilePaths: const ['photos/member-1/referenced.jpg'],
        memberIds: const ['member-1'],
      ),
    );
    await restarted.reconcilePendingQuarantines();

    expect(await File(referenced).readAsBytes(), const [1, 2, 3]);
    expect(await File(orphan).exists(), isFalse);
    expect(await staging.exists(), isFalse);
    expect(
      Directory(
        p.join(root.path, 'photos', '.staging'),
      ).listSync(followLinks: false),
      isEmpty,
    );

    await root.delete(recursive: true);
  });

  test('격리한 파일과 회원 디렉터리는 복구하거나 안전하게 폐기할 수 있다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_quarantine_',
    );
    final service = PhotoStorageServiceImpl(rootPath: root.path);
    final first = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [1],
      fileName: 'first.jpg',
    );

    final fileQuarantine = await service.quarantineFile(first);
    expect(fileQuarantine, isNotNull);
    expect(await File(first).exists(), isFalse);
    expect(await File(fileQuarantine!.journalPath).exists(), isTrue);
    await service.restoreQuarantine(fileQuarantine);
    expect(await File(first).readAsBytes(), const [1]);
    expect(await File(fileQuarantine.journalPath).exists(), isFalse);

    final directoryQuarantine = await service.quarantineMemberDir('member-1');
    expect(directoryQuarantine, isNotNull);
    expect(await File(first).exists(), isFalse);
    await service.discardQuarantine(directoryQuarantine!);
    expect(await File(first).exists(), isFalse);
    expect(await File(directoryQuarantine.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('journal 게시 직후 중단되면 원본을 유지하고 첫 접근에서 journal을 정리한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_journal_only_',
    );
    late StorageQuarantine interrupted;
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.journalPublished) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [1, 2, 3],
      fileName: 'front.jpg',
    );

    await expectLater(
      service.quarantineFile(original),
      throwsA(isA<_SimulatedCrash>()),
    );

    expect(await File(original).readAsBytes(), const [1, 2, 3]);
    expect(await File(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isTrue);
    final journal =
        jsonDecode(await File(interrupted.journalPath).readAsString())
            as Map<String, dynamic>;
    expect(journal['originalRelativePath'], 'member-1/front.jpg');
    expect(journal['payloadName'], p.basename(interrupted.quarantinedPath));
    expect(
      await File(interrupted.journalPath).readAsString(),
      isNot(contains(root.path)),
    );

    final restarted = PhotoStorageServiceImpl(rootPath: root.path);
    expect(await restarted.resolvePath('photos/member-1/front.jpg'), original);
    expect(await File(original).readAsBytes(), const [1, 2, 3]);
    expect(await File(interrupted.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('payload 이동 직후 중단되면 첫 접근에서 파일을 원래 경로로 복구한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_payload_moved_',
    );
    late StorageQuarantine interrupted;
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadMoved) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [4, 5, 6],
      fileName: 'side.jpg',
    );

    await expectLater(
      service.quarantineFile(original),
      throwsA(isA<_SimulatedCrash>()),
    );
    expect(await File(original).exists(), isFalse);
    expect(await File(interrupted.quarantinedPath).readAsBytes(), const [
      4,
      5,
      6,
    ]);
    expect(await File(interrupted.journalPath).exists(), isTrue);

    final restarted = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantineReferencesLoader: () async => StorageQuarantineReferences(
        storedFilePaths: const ['photos/member-1/side.jpg'],
        memberIds: const ['member-1'],
      ),
    );
    await restarted.resolvePath('photos/member-1/side.jpg');
    expect(await File(original).readAsBytes(), const [4, 5, 6]);
    expect(await File(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('DB commit 후 남은 파일 payload는 원본으로 되살리지 않고 폐기한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_committed_file_',
    );
    late StorageQuarantine interrupted;
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadMoved) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [13, 14],
      fileName: 'committed.jpg',
    );
    await expectLater(
      service.quarantineFile(original),
      throwsA(isA<_SimulatedCrash>()),
    );

    final restarted = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantineReferencesLoader: () async => StorageQuarantineReferences(
        storedFilePaths: const [],
        memberIds: const ['member-1'],
      ),
    );
    await restarted.memberDir('member-1');

    expect(await File(original).exists(), isFalse);
    expect(await File(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('DB commit 후 삭제된 회원의 디렉터리 payload도 폐기한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_committed_member_',
    );
    late StorageQuarantine interrupted;
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadMoved) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [15],
      fileName: 'member.jpg',
    );
    await expectLater(
      service.quarantineMemberDir('member-1'),
      throwsA(isA<_SimulatedCrash>()),
    );

    final restarted = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantineReferencesLoader: () async => StorageQuarantineReferences(
        storedFilePaths: const [],
        memberIds: const [],
      ),
    );
    await restarted.memberDir('member-2');

    expect(await File(original).exists(), isFalse);
    expect(await Directory(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('회원 디렉터리 payload도 중단 후 첫 접근에서 하위 파일과 함께 복구한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_member_payload_',
    );
    late StorageQuarantine interrupted;
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadMoved) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [7, 8, 9],
      fileName: 'nested.jpg',
    );

    await expectLater(
      service.quarantineMemberDir('member-1'),
      throwsA(isA<_SimulatedCrash>()),
    );
    expect(await File(original).exists(), isFalse);
    expect(await Directory(interrupted.quarantinedPath).exists(), isTrue);

    final restarted = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantineReferencesLoader: () async => StorageQuarantineReferences(
        storedFilePaths: const ['photos/member-1/nested.jpg'],
        memberIds: const ['member-1'],
      ),
    );
    await restarted.memberDir('member-1');
    expect(await File(original).readAsBytes(), const [7, 8, 9]);
    expect(await Directory(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('restore 이동 후 journal 삭제 전 중단된 상태를 멱등 복구한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_restore_crash_',
    );
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadRestored) {
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [10, 11],
      fileName: 'back.jpg',
    );
    final quarantine = (await service.quarantineFile(original))!;

    await expectLater(
      service.restoreQuarantine(quarantine),
      throwsA(isA<_SimulatedCrash>()),
    );
    expect(await File(original).readAsBytes(), const [10, 11]);
    expect(await File(quarantine.quarantinedPath).exists(), isFalse);
    expect(await File(quarantine.journalPath).exists(), isTrue);

    final restarted = PhotoStorageServiceImpl(rootPath: root.path);
    await restarted.resolvePath('photos/member-1/back.jpg');
    expect(await File(original).readAsBytes(), const [10, 11]);
    expect(await File(quarantine.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('discard 후 journal 삭제 전 중단된 상태는 삭제를 되살리지 않고 정리한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_storage_discard_crash_',
    );
    final service = PhotoStorageServiceImpl(
      rootPath: root.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadDiscarded) {
          throw const _SimulatedCrash();
        }
      },
    );
    final original = await service.saveBytes(
      memberId: 'member-1',
      bytes: const [12],
      fileName: 'delete.jpg',
    );
    final quarantine = (await service.quarantineFile(original))!;

    await expectLater(
      service.discardQuarantine(quarantine),
      throwsA(isA<_SimulatedCrash>()),
    );
    expect(await File(original).exists(), isFalse);
    expect(await File(quarantine.quarantinedPath).exists(), isFalse);
    expect(await File(quarantine.journalPath).exists(), isTrue);

    final restarted = PhotoStorageServiceImpl(rootPath: root.path);
    await restarted.memberDir('member-2');
    expect(await File(original).exists(), isFalse);
    expect(await File(quarantine.journalPath).exists(), isFalse);

    await root.delete(recursive: true);
  });

  test('v1 절대경로와 복원 marker table은 최신 schema로 마이그레이션된다', () async {
    final root = await Directory.systemTemp.createTemp(
      'body_frame_db_migration_',
    );
    final dbPath = p.join(root.path, 'legacy.db');
    final legacy = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE members (avatar_path TEXT)');
        await db.execute('CREATE TABLE body_photos (file_path TEXT NOT NULL)');
        await db.insert('members', {
          'avatar_path': '/old/container/Documents/photos/member-1/avatar.jpg',
        });
        await db.insert('body_photos', {
          'file_path': '/old/container/Documents/photos/member-1/front.jpg',
        });
      },
    );
    await legacy.close();

    final appDatabase = AppDatabase(path: dbPath);
    final migrated = await appDatabase.database;
    final member = (await migrated.query('members')).single;
    final photo = (await migrated.query('body_photos')).single;
    expect(member['avatar_path'], 'photos/member-1/avatar.jpg');
    expect(photo['file_path'], 'photos/member-1/front.jpg');
    expect(await migrated.query(AppDatabase.tableRestoreOperations), isEmpty);

    await appDatabase.close();
    await root.delete(recursive: true);
  });
}

class _SimulatedCrash implements Exception {
  const _SimulatedCrash();
}
