import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/photo_ingest_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _shotAt = DateTime(2026, 1, 1);

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
  });

  tearDown(() async {
    await appDatabase.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('새 기록과 사진 전체를 한 transaction에 넣고 파일 경로는 상대경로로 저장한다', () async {
    final db = await appDatabase.database;
    final existing = _record('r-existing');
    await db.insert(AppDatabase.tablePhotoRecords, existing.toMap());
    final created = _record('r-new');
    final firstPath = await storage.saveBytes(
      shotAt: _shotAt,
      bytes: const [1],
      fileName: 'first.jpg',
    );
    final secondPath = await storage.saveBytes(
      shotAt: _shotAt,
      bytes: const [2],
      fileName: 'second.jpg',
    );

    await ingest.insertPrepared(
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
    final photoRows = await db.query(AppDatabase.tableBodyPhotos, orderBy: 'id');
    expect(recordRows, hasLength(1));
    expect(photoRows, hasLength(2));
    expect(
      photoRows.map((row) => row['file_path']),
      everyElement(startsWith('photos/202601/')),
    );
    expect(photoRows.map((row) => row['file_path']), isNot(contains(firstPath)));
  });

  test('두 번째 사진 conflict 시 앞선 새 기록과 사진도 실제 transaction에서 rollback한다', () async {
    final db = await appDatabase.database;
    final existing = _record('r-existing');
    await db.insert(AppDatabase.tablePhotoRecords, existing.toMap());
    final existingPath = await storage.saveBytes(
      shotAt: _shotAt,
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

    final created = _record('r-new');
    final firstPath = await storage.saveBytes(
      shotAt: _shotAt,
      bytes: const [1],
      fileName: 'first.jpg',
    );
    final conflictPath = await storage.saveBytes(
      shotAt: _shotAt,
      bytes: const [2],
      fileName: 'conflict.jpg',
    );

    await expectLater(
      ingest.insertPrepared(
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

  test('앱 저장소 밖의 파일과 존재하지 않는 촬영 기록은 거부한다', () async {
    final db = await appDatabase.database;
    final outside = File('${root.path}/outside.jpg');
    await outside.writeAsBytes(const [1]);
    final managed = await storage.saveBytes(
      shotAt: _shotAt,
      bytes: const [2],
      fileName: 'managed.jpg',
    );

    await expectLater(
      ingest.insertPrepared(
        newRecords: const [],
        photos: [_photo('p-outside', 'r-missing', outside.path)],
      ),
      throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
    );
    await expectLater(
      ingest.insertPrepared(
        newRecords: const [],
        photos: [_photo('p-orphan', 'r-missing', managed)],
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query(AppDatabase.tableBodyPhotos), isEmpty);
  });

  test('사진이 하나도 없으면 등록하지 않는다', () async {
    await expectLater(
      ingest.insertPrepared(
        newRecords: [_record('r-empty')],
        photos: const [],
      ),
      throwsArgumentError,
    );
  });
}

PhotoRecord _record(String id) {
  return PhotoRecord(
    id: id,
    shotAt: _shotAt,
    createdAt: _shotAt,
    updatedAt: _shotAt,
  );
}

BodyPhoto _photo(String id, String recordId, String path) {
  return BodyPhoto(
    id: id,
    recordId: recordId,
    filePath: path,
    direction: BodyDirection.front,
    createdAt: _shotAt,
  );
}
