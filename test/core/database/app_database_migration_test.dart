import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 스키마 v1 시절의 body_photos 정의. 마이그레이션이 실제 구버전 DB에서
/// 동작하는지 보려면 그때의 테이블을 그대로 만들어야 한다.
const _v1BodyPhotos = '''
  CREATE TABLE body_photos (
    id TEXT PRIMARY KEY,
    record_id TEXT NOT NULL,
    file_path TEXT NOT NULL,
    direction TEXT NOT NULL DEFAULT 'etc',
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    orientation INTEGER NOT NULL DEFAULT 1,
    grid_settings TEXT,
    memo TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (record_id) REFERENCES photo_records (id) ON DELETE CASCADE
  )
''';

const _v1PhotoRecords = '''
  CREATE TABLE photo_records (
    id TEXT PRIMARY KEY,
    shot_at INTEGER NOT NULL,
    label TEXT,
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
    root = await Directory.systemTemp.createTemp('body_frame_migration_');
    dbPath = '${root.path}/body_frame.db';
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// v1 스키마 DB를 만들고 사진 1건을 넣는다.
  Future<void> seedV1({required String gridJson}) async {
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(_v1PhotoRecords);
        await db.execute(_v1BodyPhotos);
      },
    );
    await db.insert('photo_records', {
      'id': 'r1',
      'shot_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('body_photos', {
      'id': 'p1',
      'record_id': 'r1',
      'file_path': 'photos/202601/p1.jpg',
      'direction': 'front',
      'grid_settings': gridJson,
      'created_at': 0,
    });
    await db.close();
  }

  test('v1 DB를 열면 촬영 당시 격자 설정 컬럼이 추가되고 기존 값으로 채워진다', () async {
    const captured = GridSettings(
      visible: true,
      opacity: 0.42,
      lineWidth: 2.5,
      spacing: 55,
      colorValue: 0xFFFFEB3B,
    );
    await seedV1(gridJson: captured.toJson());

    final appDatabase = AppDatabase(path: dbPath);
    addTearDown(appDatabase.close);
    final db = await appDatabase.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final rows = await db.query(AppDatabase.tableBodyPhotos);
    expect(rows, hasLength(1));

    final photo = BodyPhoto.fromMap(Map<String, dynamic>.from(rows.single));
    // 기존 행은 아직 수정된 적이 없으므로 촬영 당시 값 = 현재 값이다.
    expect(photo.gridSettings, captured);
    expect(photo.captureGridSettings, captured);
    expect(photo.isGridEdited, isFalse);
  });

  test('마이그레이션이 기존 사진 데이터를 잃지 않는다', () async {
    await seedV1(gridJson: GridSettings.defaults.toJson());

    final appDatabase = AppDatabase(path: dbPath);
    addTearDown(appDatabase.close);
    final db = await appDatabase.database;

    final rows = await db.query(AppDatabase.tableBodyPhotos);
    final row = rows.single;
    expect(row['id'], 'p1');
    expect(row['record_id'], 'r1');
    expect(row['file_path'], 'photos/202601/p1.jpg');
    expect(row['direction'], 'front');
  });

  test('두 번 열어도 마이그레이션이 다시 실행되지 않는다', () async {
    await seedV1(gridJson: GridSettings.defaults.toJson());

    final first = AppDatabase(path: dbPath);
    await first.database;
    await first.close();

    // ALTER TABLE을 다시 실행하면 중복 컬럼 오류가 난다. 재실행되지 않아야 한다.
    final second = AppDatabase(path: dbPath);
    addTearDown(second.close);
    final db = await second.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(await db.query(AppDatabase.tableBodyPhotos), hasLength(1));
  });

  test('새로 만든 DB에도 촬영 당시 격자 설정 컬럼이 있다', () async {
    final appDatabase = AppDatabase(path: dbPath);
    addTearDown(appDatabase.close);
    final db = await appDatabase.database;

    final columns = await db.rawQuery(
      'PRAGMA table_info(${AppDatabase.tableBodyPhotos})',
    );
    expect(
      columns.map((c) => c['name']),
      contains('capture_grid_settings'),
    );
  });
}
