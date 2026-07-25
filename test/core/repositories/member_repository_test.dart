import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 인메모리 sqflite(FFI) + 임시 저장소로 리포지토리를 테스트하는 패턴.
void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late PhotoStorageService storage;
  late MemberRepository members;
  late BodyPhotoRepository photos;
  late PhotoRecordRepository records;

  setUpAll(() {
    // 호스트에서 sqflite를 실행하기 위한 FFI 백엔드 등록.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp('body_frame_test_');
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, storage: storage);
    members = MemberRepositoryImpl(database: db, storage: storage);
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Member sampleMember(String id, String name) {
    final now = DateTime(2026, 1, 1);
    return Member(id: id, name: name, createdAt: now, updatedAt: now);
  }

  Future<StorageQuarantineReferences> loadQuarantineReferences() async {
    final rawDb = await db.database;
    return rawDb.transaction((txn) async {
      final memberRows = await txn.query(
        AppDatabase.tableMembers,
        columns: ['id', 'avatar_path'],
      );
      final photoRows = await txn.query(
        AppDatabase.tableBodyPhotos,
        columns: ['file_path'],
      );
      return StorageQuarantineReferences(
        memberIds: memberRows.map((row) => row['id'] as String),
        storedFilePaths: [
          ...memberRows
              .map((row) => row['avatar_path'] as String?)
              .whereType<String>()
              .where((path) => path.isNotEmpty),
          ...photoRows.map((row) => row['file_path'] as String),
        ],
      );
    });
  }

  test('회원 등록 후 목록/조회가 동작한다', () async {
    await members.insert(sampleMember('m1', '홍길동'));

    final list = await members.list();
    expect(list, hasLength(1));
    expect(list.first.member.name, '홍길동');
    expect(list.first.recordCount, 0);
    expect(list.first.lastShotAt, isNull);

    final fetched = await members.getById('m1');
    expect(fetched?.name, '홍길동');
  });

  test('이름 검색과 이름순 정렬이 동작한다', () async {
    await members.insert(sampleMember('m1', '가나'));
    await members.insert(sampleMember('m2', '다라'));

    final searched = await members.list(query: '다');
    expect(searched, hasLength(1));
    expect(searched.first.member.id, 'm2');

    final sorted = await members.list(sort: MemberSort.name);
    expect(sorted.map((e) => e.member.id), ['m1', 'm2']);
  });

  test('중복 id insert는 기존 회원을 REPLACE하지 않고 실패한다', () async {
    await members.insert(sampleMember('m1', '기존 회원'));

    await expectLater(
      members.insert(sampleMember('m1', '덮어쓰기 시도')),
      throwsA(anything),
    );

    expect((await members.getById('m1'))?.name, '기존 회원');
  });

  test('존재하지 않는 촬영 기록 update는 성공한 것처럼 처리하지 않는다', () async {
    final now = DateTime(2026, 1, 1);
    await expectLater(
      records.update(
        PhotoRecord(
          id: 'missing-record',
          memberId: 'missing-member',
          shotAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('회원 삭제 시 촬영 기록/사진 행과 파일이 연쇄 삭제된다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final now = DateTime(2026, 2, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 저장소에 더미 원본 파일을 만들고 사진 행을 등록한다.
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: List<int>.filled(8, 0),
      fileName: 'front.jpg',
    );
    await photos.insert(
      BodyPhoto(
        id: 'p1',
        recordId: 'r1',
        filePath: saved,
        direction: BodyDirection.front,
        createdAt: now,
      ),
    );

    final storedRows = await (await db.database).query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: ['p1'],
    );
    expect(storedRows.single['file_path'], 'photos/m1/front.jpg');

    expect(await File(saved).exists(), isTrue);
    expect(await records.listByMember('m1'), hasLength(1));

    await members.delete('m1');

    expect(await members.getById('m1'), isNull);
    expect(await records.listByMember('m1'), isEmpty);
    expect(await photos.getById('p1'), isNull);
    expect(await File(saved).exists(), isFalse);
  });

  test('회원 삭제 DB가 실패하면 격리한 사진 파일과 행을 복구한다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [9, 8, 7],
      fileName: 'avatar.jpg',
    );
    await members.update(
      (await members.getById('m1'))!.copyWith(avatarPath: saved),
    );
    final rawDb = await db.database;
    await rawDb.execute('''
      CREATE TRIGGER prevent_member_delete
      BEFORE DELETE ON ${AppDatabase.tableMembers}
      BEGIN
        SELECT RAISE(ABORT, 'forced delete failure');
      END
    ''');

    await expectLater(members.delete('m1'), throwsA(anything));

    expect(await members.getById('m1'), isNotNull);
    expect(await File(saved).readAsBytes(), const [9, 8, 7]);
  });

  test('사진 삭제 DB가 실패하면 격리한 원본을 복구한다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final now = DateTime(2026, 2, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [4, 5, 6],
      fileName: 'front.jpg',
    );
    await photos.insert(
      BodyPhoto(
        id: 'p1',
        recordId: 'r1',
        filePath: saved,
        direction: BodyDirection.front,
        createdAt: now,
      ),
    );
    final rawDb = await db.database;
    await rawDb.execute('''
      CREATE TRIGGER prevent_photo_delete
      BEFORE DELETE ON ${AppDatabase.tableBodyPhotos}
      BEGIN
        SELECT RAISE(ABORT, 'forced delete failure');
      END
    ''');

    await expectLater(photos.delete('p1'), throwsA(anything));

    expect(await photos.getById('p1'), isNotNull);
    expect(await File(saved).readAsBytes(), const [4, 5, 6]);
  });

  test('격리 payload 이동 직후 프로세스가 중단돼도 DB 행과 원본을 첫 접근에서 복구한다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final now = DateTime(2026, 2, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [6, 7, 8],
      fileName: 'crash.jpg',
    );
    await photos.insert(
      BodyPhoto(
        id: 'p1',
        recordId: 'r1',
        filePath: saved,
        direction: BodyDirection.front,
        createdAt: now,
      ),
    );

    late StorageQuarantine interrupted;
    final crashingStorage = PhotoStorageServiceImpl(
      rootPath: tempRoot.path,
      quarantinePhaseHook: (quarantine, phase) async {
        if (phase == StorageQuarantinePhase.payloadMoved) {
          interrupted = quarantine;
          throw const _SimulatedCrash();
        }
      },
    );
    final crashingPhotos = BodyPhotoRepositoryImpl(
      database: db,
      storage: crashingStorage,
    );

    await expectLater(
      crashingPhotos.delete('p1'),
      throwsA(isA<_SimulatedCrash>()),
    );
    final rows = await (await db.database).query(
      AppDatabase.tableBodyPhotos,
      where: 'id = ?',
      whereArgs: ['p1'],
    );
    expect(rows, hasLength(1));
    expect(await File(saved).exists(), isFalse);
    expect(await File(interrupted.quarantinedPath).exists(), isTrue);
    expect(await File(interrupted.journalPath).exists(), isTrue);

    final restartedStorage = PhotoStorageServiceImpl(
      rootPath: tempRoot.path,
      quarantineReferencesLoader: loadQuarantineReferences,
    );
    final restartedPhotos = BodyPhotoRepositoryImpl(
      database: db,
      storage: restartedStorage,
    );
    final recovered = await restartedPhotos.getById('p1');
    expect(recovered, isNotNull);
    expect(await File(recovered!.filePath).readAsBytes(), const [6, 7, 8]);
    expect(await File(interrupted.quarantinedPath).exists(), isFalse);
    expect(await File(interrupted.journalPath).exists(), isFalse);
  });

  test('DB commit 후 discard 전에 중단된 사진 payload는 다시 노출하지 않는다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final now = DateTime(2026, 2, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [9, 9, 1],
      fileName: 'committed-crash.jpg',
    );
    await photos.insert(
      BodyPhoto(
        id: 'p1',
        recordId: 'r1',
        filePath: saved,
        direction: BodyDirection.front,
        createdAt: now,
      ),
    );

    final quarantine = (await storage.quarantineFile(saved))!;
    await (await db.database).transaction((txn) async {
      await txn.delete(
        AppDatabase.tableBodyPhotos,
        where: 'id = ?',
        whereArgs: ['p1'],
      );
    });
    expect(await photos.getById('p1'), isNull);
    expect(await File(quarantine.quarantinedPath).exists(), isTrue);

    final restartedStorage = PhotoStorageServiceImpl(
      rootPath: tempRoot.path,
      quarantineReferencesLoader: loadQuarantineReferences,
    );
    final restartedMembers = MemberRepositoryImpl(
      database: db,
      storage: restartedStorage,
    );
    await restartedMembers.list();

    expect(await File(saved).exists(), isFalse);
    expect(await File(quarantine.quarantinedPath).exists(), isFalse);
    expect(await File(quarantine.journalPath).exists(), isFalse);
  });

  test('사진과 대표 사진은 실제 소유 회원 디렉터리 경로만 저장한다', () async {
    await members.insert(sampleMember('m1', '회원 1'));
    await members.insert(sampleMember('m2', '회원 2'));
    final now = DateTime(2026, 2, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm1',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final m1Path = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [1],
      fileName: 'owned.jpg',
    );
    final m2Path = await storage.saveBytes(
      memberId: 'm2',
      bytes: const [2],
      fileName: 'foreign.jpg',
    );

    await expectLater(
      photos.insert(
        BodyPhoto(
          id: 'foreign-photo',
          recordId: 'r1',
          filePath: m2Path,
          direction: BodyDirection.front,
          createdAt: now,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    await photos.insert(
      BodyPhoto(
        id: 'p1',
        recordId: 'r1',
        filePath: m1Path,
        direction: BodyDirection.front,
        createdAt: now,
      ),
    );
    await expectLater(
      records.update((await records.getById('r1'))!.copyWith(memberId: 'm2')),
      throwsA(isA<StateError>()),
    );
    expect((await records.getById('r1'))!.memberId, 'm1');
    await expectLater(
      photos.update((await photos.getById('p1'))!.copyWith(filePath: m2Path)),
      throwsA(isA<StateError>()),
    );
    expect((await photos.getById('p1'))!.filePath, m1Path);

    await expectLater(
      members.update(
        (await members.getById('m1'))!.copyWith(avatarPath: m2Path),
      ),
      throwsA(isA<StateError>()),
    );
    expect((await members.getById('m1'))!.avatarPath, isNull);
  });

  test('최근 촬영순 정렬은 촬영 기록이 있는 회원을 먼저 둔다', () async {
    await members.insert(sampleMember('m1', '먼저등록'));
    await members.insert(sampleMember('m2', '나중촬영'));
    final now = DateTime(2026, 3, 1);
    await records.insert(
      PhotoRecord(
        id: 'r1',
        memberId: 'm2',
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final list = await members.list(sort: MemberSort.recentShot);
    expect(list.first.member.id, 'm2');
    expect(list.first.recordCount, 1);
    expect(list.first.lastShotAt, now);
  });
}

class _SimulatedCrash implements Exception {
  const _SimulatedCrash();
}
