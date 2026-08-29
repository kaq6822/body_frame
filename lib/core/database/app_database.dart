import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../services/app_logger.dart';

/// sqflite 데이터베이스 관리자.
///
/// 스키마 정의를 담당한다. 사진 파일 자체는 저장하지 않고
/// body_photos.file_path에는 앱 저장소 기준 상대경로만 저장한다.
///
/// **마이그레이션은 두지 않는다.** 아직 출시하지 않은 앱이라 지켜야 할 사용자
/// 데이터가 없다. 스키마가 바뀌면 [schemaVersion]을 올리는 대신 이 파일의
/// [_onCreate]를 고치고 앱을 재설치한다. 다른 스키마로 만들어진 DB 파일이
/// 남아 있으면 [onDatabaseDowngradeDelete]가 지우고 새로 만든다 — 재설치와 같은
/// 결과를 자동으로 얻어, 옛 스키마가 남아 조회가 전부 실패하는 상태를 막는다.
///
/// 테스트에서는 [AppDatabase.forTesting]으로 인메모리 DB를 주입한다.
class AppDatabase {
  static const String dbName = 'body_frame.db';

  /// 스키마 버전. 마이그레이션이 없으므로 항상 1이며 올리지 않는다.
  static const int schemaVersion = 1;

  static const String tablePhotoRecords = 'photo_records';
  static const String tableBodyPhotos = 'body_photos';

  final AppLogger _logger;

  /// 테스트 등에서 직접 경로를 주입할 때 사용. null이면 문서 디렉터리 사용.
  final String? _overridePath;

  Database? _db;

  AppDatabase({AppLogger? logger, String? path})
    : _logger = logger ?? AppLogger.instance,
      _overridePath = path;

  /// 인메모리 DB를 사용하는 테스트 전용 인스턴스.
  factory AppDatabase.forTesting({AppLogger? logger}) {
    return AppDatabase(logger: logger, path: inMemoryDatabasePath);
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final String path;
    if (_overridePath != null) {
      path = _overridePath;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, dbName);
    }
    _logger.info('database.open', context: {'version': schemaVersion});
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      // 더 높은 버전으로 만들어진 DB가 남아 있으면 지우고 새로 만든다.
      // 없으면 sqflite는 아무 일도 하지 않은 채 버전만 덮어써서, 옛 스키마가
      // 그대로 남아 모든 조회가 실패하는 상태로 굳는다.
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // 기록 삭제 시 사진 행이 연쇄 삭제되도록 외래 키 활성화.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    _logger.info('database.create', context: {'version': version});
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE $tablePhotoRecords (
        id TEXT PRIMARY KEY,
        shot_at INTEGER NOT NULL,
        label TEXT,
        memo TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE $tableBodyPhotos (
        id TEXT PRIMARY KEY,
        record_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        direction TEXT NOT NULL DEFAULT 'etc',
        width INTEGER NOT NULL DEFAULT 0,
        height INTEGER NOT NULL DEFAULT 0,
        orientation INTEGER NOT NULL DEFAULT 1,
        grid_settings TEXT,
        capture_grid_settings TEXT,
        memo TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (record_id) REFERENCES $tablePhotoRecords (id) ON DELETE CASCADE
      )
    ''');

    batch.execute(
      'CREATE INDEX idx_records_shot_at ON $tablePhotoRecords (shot_at)',
    );
    batch.execute(
      'CREATE INDEX idx_photos_record ON $tableBodyPhotos (record_id)',
    );

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
