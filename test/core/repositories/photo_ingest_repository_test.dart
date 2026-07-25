import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/photo_ingest_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late AppDatabase appDatabase;
  late PhotoStorageService storage;
  late PhotoIngestRepository ingest;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_frame_ingest_');
    appDatabase = AppDatabase.forTesting();
    storage = PhotoStorageServiceImpl(rootPath: root.path);
    ingest = PhotoIngestRepositoryImpl(database: appDatabase, storage: storage);
    final db = await appDatabase.database;
    await db.insert(
      AppDatabase.tableMembers,
      _member('m1').toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await db.insert(
      AppDatabase.tableMembers,
      _member('m2').toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('새 기록과 사진 전체를 한 transaction에 넣고 파일 경로는 상대경로로 저장한다', () async {
    final db = await appDatabase.database;
    final existing = _record('r-existing', 'm1');
    await db.insert(AppDatabase.tablePhotoRecords, existing.toMap());
    final created = _record('r-new', 'm1');
    final firstPath = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [1],
      fileName: 'first.jpg',
    );
    final secondPath = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [2],
      fileName: 'second.jpg',
    );

    await ingest.insertPrepared(
      memberId: 'm1',
      newRecords: [created],
      photos: [
        _photo('p-new', created.id, firstPath),
        _photo('p-existing', existing.id, secondPath),
      ],
    );

    final recordRows = await db.query(
      AppDatabase.tablePhotoRecords,
      where: 'id = ?',
      whereArgs: [created.id],
    );
    final photoRows = await db.query(
      AppDatabase.tableBodyPhotos,
      orderBy: 'id',
    );
    expect(recordRows, hasLength(1));
    expect(photoRows, hasLength(2));
    expect(
      photoRows.map((row) => row['file_path']),
      everyElement(startsWith('photos/m1/')),
    );
    expect(
      photoRows.map((row) => row['file_path']),
      isNot(contains(firstPath)),
    );
  });

  test('두 번째 사진 conflict 시 앞선 새 기록과 사진도 실제 transaction에서 rollback한다', () async {
    final db = await appDatabase.database;
    final existing = _record('r-existing', 'm1');
    await db.insert(AppDatabase.tablePhotoRecords, existing.toMap());
    final existingPath = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [9],
      fileName: 'existing.jpg',
    );
    await db.insert(AppDatabase.tableBodyPhotos, {
      ..._photo(
        'p-conflict',
        existing.id,
        await storage.toStoredPath(existingPath),
      ).toMap(),
    });

    final created = _record('r-new', 'm1');
    final firstPath = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [1],
      fileName: 'first.jpg',
    );
    final conflictPath = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [2],
      fileName: 'conflict.jpg',
    );

    await expectLater(
      ingest.insertPrepared(
        memberId: 'm1',
        newRecords: [created],
        photos: [
          _photo('p-first', created.id, firstPath),
          _photo('p-conflict', created.id, conflictPath),
        ],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      await db.query(
        AppDatabase.tablePhotoRecords,
        where: 'id = ?',
        whereArgs: [created.id],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        AppDatabase.tableBodyPhotos,
        where: 'id = ?',
        whereArgs: ['p-first'],
      ),
      isEmpty,
    );
    final conflictRows = await db.query(
      AppDatabase.tableBodyPhotos,
      where: 'id = ?',
      whereArgs: ['p-conflict'],
    );
    expect(conflictRows, hasLength(1));
    expect(conflictRows.single['record_id'], existing.id);
  });

  test('파일 경로와 기존 촬영 기록이 모두 대상 회원 소유인지 검증한다', () async {
    final db = await appDatabase.database;
    final m1Record = _record('r-m1', 'm1');
    final m2Record = _record('r-m2', 'm2');
    await db.insert(AppDatabase.tablePhotoRecords, m1Record.toMap());
    await db.insert(AppDatabase.tablePhotoRecords, m2Record.toMap());
    final m1Path = await storage.saveBytes(
      memberId: 'm1',
      bytes: const [1],
      fileName: 'm1.jpg',
    );
    final m2Path = await storage.saveBytes(
      memberId: 'm2',
      bytes: const [2],
      fileName: 'm2.jpg',
    );

    await expectLater(
      ingest.insertPrepared(
        memberId: 'm1',
        newRecords: const [],
        photos: [_photo('p-wrong-file', m1Record.id, m2Path)],
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      ingest.insertPrepared(
        memberId: 'm1',
        newRecords: const [],
        photos: [_photo('p-wrong-record', m2Record.id, m1Path)],
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query(AppDatabase.tableBodyPhotos), isEmpty);
  });
}

Member _member(String id) {
  final now = DateTime(2026, 1, 1);
  return Member(id: id, name: id, createdAt: now, updatedAt: now);
}

PhotoRecord _record(String id, String memberId) {
  final now = DateTime(2026, 1, 1);
  return PhotoRecord(
    id: id,
    memberId: memberId,
    shotAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

BodyPhoto _photo(String id, String recordId, String path) {
  return BodyPhoto(
    id: id,
    recordId: recordId,
    filePath: path,
    direction: BodyDirection.front,
    createdAt: DateTime(2026, 1, 1),
  );
}
