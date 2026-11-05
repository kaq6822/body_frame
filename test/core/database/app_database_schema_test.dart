import 'dart:io';

import 'package:bodymark/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 다른 스키마로 만들어진 옛 DB. 마이그레이션을 두지 않으므로 이런 파일이 남아
/// 있으면 지우고 새로 만들어야 한다(회원 시절 스키마를 그대로 재현한다).
const _legacyPhotoRecords = '''
  CREATE TABLE photo_records (
    id TEXT PRIMARY KEY,
    member_id TEXT NOT NULL,
    shot_at INTEGER NOT NULL,
    memo TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
''';

void main() {
  late Directory root;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('body_frame_schema_');
    dbPath = '${root.path}/body_frame.db';
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('새로 만든 DB에 현재 스키마의 컬럼이 모두 있다', () async {
    final appDatabase = AppDatabase(path: dbPath);
    addTearDown(appDatabase.close);
    final db = await appDatabase.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final recordColumns = await db.rawQuery(
      'PRAGMA table_info(${AppDatabase.tablePhotoRecords})',
    );
    expect(
      recordColumns.map((c) => c['name']),
      containsAll([
        'id',
        'shot_at',
        'label',
        'memo',
        'created_at',
        'updated_at',
      ]),
    );

    final photoColumns = await db.rawQuery(
      'PRAGMA table_info(${AppDatabase.tableBodyPhotos})',
    );
    expect(
      photoColumns.map((c) => c['name']),
      containsAll([
        'id',
        'record_id',
        'file_path',
        'direction',
        'width',
        'height',
        'orientation',
        'grid_settings',
        'capture_grid_settings',
        'memo',
        'created_at',
      ]),
    );
  });

  test('더 높은 버전의 DB는 삭제하지 않고 열기를 거부한다', () async {
    final legacy = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, _) async => db.execute(_legacyPhotoRecords),
    );
    await legacy.insert('photo_records', {
      'id': 'r1',
      'member_id': 'm1',
      'shot_at': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    await legacy.close();
    final appDatabase = AppDatabase(path: dbPath);
    await expectLater(appDatabase.database, throwsStateError);
    final untouched = await openDatabase(dbPath, readOnly: true);
    expect((await untouched.query('photo_records')).single['id'], 'r1');
    expect(await untouched.getVersion(), 3);
    await untouched.close();
  });

  test('버전 1의 사진·메모·상대경로를 보존하고 회원 미연결로 이전한다', () async {
    final old = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE photo_records(id TEXT PRIMARY KEY, shot_at INTEGER NOT NULL, label TEXT, memo TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
        );
        await db.execute(
          "CREATE TABLE body_photos(id TEXT PRIMARY KEY, record_id TEXT NOT NULL, file_path TEXT NOT NULL, direction TEXT NOT NULL DEFAULT 'etc', width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0, orientation INTEGER NOT NULL DEFAULT 1, grid_settings TEXT, capture_grid_settings TEXT, memo TEXT, created_at INTEGER NOT NULL, FOREIGN KEY(record_id) REFERENCES photo_records(id) ON DELETE CASCADE)",
        );
      },
    );
    await old.insert('photo_records', {
      'id': 'r',
      'shot_at': 123,
      'label': '기존 라벨',
      'memo': '기존 메모',
      'created_at': 456,
      'updated_at': 789,
    });
    await old.insert('body_photos', {
      'id': 'p',
      'record_id': 'r',
      'file_path': 'photos/202611/original.jpg',
      'direction': 'front',
      'created_at': 456,
    });
    await old.close();
    final migrated = AppDatabase(path: dbPath);
    addTearDown(migrated.close);
    final db = await migrated.database;
    final record = (await db.query('photo_records')).single;
    final photo = (await db.query('body_photos')).single;
    expect(record['member_id'], isNull);
    expect(record['memo'], '기존 메모');
    expect(record['shot_at'], 123);
    expect(record['created_at'], 456);
    expect(photo['file_path'], 'photos/202611/original.jpg');
    expect(photo['phase'], 'regular');
    expect(photo['captured_at'], isNull);
    expect(await db.query('members'), isEmpty);
    expect(await db.getVersion(), 2);
  });

  test('같은 DB를 두 번 열어도 스키마가 그대로 유지된다', () async {
    final first = AppDatabase(path: dbPath);
    final firstDb = await first.database;
    await firstDb.insert(AppDatabase.tablePhotoRecords, {
      'id': 'r1',
      'shot_at': 0,
      'created_at': 0,
      'updated_at': 0,
    });
    await first.close();

    final second = AppDatabase(path: dbPath);
    addTearDown(second.close);
    final db = await second.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(await db.query(AppDatabase.tablePhotoRecords), hasLength(1));
  });
}
