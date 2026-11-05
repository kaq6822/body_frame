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
/// 이전 버전의 사진과 메모를 보존하는 누적 마이그레이션을 수행한다.
class AppDatabase {
  static const String dbName = 'body_frame.db';

  /// 회원·레슨 정보와 촬영 목적/시각을 추가한 버전.
  static const int schemaVersion = 2;

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
      onUpgrade: _onUpgrade,
      onDowngrade: (db, oldVersion, newVersion) async {
        throw StateError('더 새로운 앱에서 만든 데이터입니다. 앱을 업데이트해주세요.');
      },
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
    await _addMemberSchema(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _addMemberSchema(db);
  }

  Future<void> _addMemberSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE members (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, reason TEXT NOT NULL DEFAULT '',
      goal TEXT NOT NULL DEFAULT '', precautions TEXT NOT NULL DEFAULT '',
      report TEXT NOT NULL DEFAULT '', observation TEXT NOT NULL DEFAULT '',
      memo TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )''');
    await db.execute(
      'ALTER TABLE photo_records ADD COLUMN member_id TEXT REFERENCES members(id)',
    );
    await db.execute('ALTER TABLE photo_records ADD COLUMN condition TEXT');
    await db.execute(
      "ALTER TABLE body_photos ADD COLUMN phase TEXT NOT NULL DEFAULT 'regular'",
    );
    await db.execute('ALTER TABLE body_photos ADD COLUMN captured_at INTEGER');
    await db.execute(
      'CREATE INDEX idx_records_member ON photo_records(member_id, shot_at)',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
