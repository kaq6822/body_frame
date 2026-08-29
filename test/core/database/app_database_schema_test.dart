import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
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

  test('더 높은 버전으로 만들어진 옛 DB는 지우고 현재 스키마로 새로 만든다', () async {
    // 마이그레이션이 없으므로 옛 스키마가 남으면 모든 조회가 실패한다.
    // onDowngrade가 없을 때 sqflite는 버전만 덮어써 그 상태를 굳혀 버린다.
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
    addTearDown(appDatabase.close);
    final db = await appDatabase.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    // 옛 데이터는 남지 않고, 현재 스키마의 컬럼으로 다시 만들어진다.
    expect(await db.query(AppDatabase.tablePhotoRecords), isEmpty);
    final columns = await db.rawQuery(
      'PRAGMA table_info(${AppDatabase.tablePhotoRecords})',
    );
    final names = columns.map((c) => c['name']).toList();
    expect(names, contains('label'));
    expect(names, isNot(contains('member_id')));
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
