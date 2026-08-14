import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../services/app_logger.dart';

/// sqflite 데이터베이스 관리자.
///
/// 스키마 정의와 마이그레이션을 담당한다. 사진 파일 자체는 저장하지 않고
/// body_photos.file_path에는 앱 저장소 기준 상대경로만 저장한다.
///
/// 테스트에서는 [AppDatabase.forTesting]으로 인메모리 DB를 주입한다.
class AppDatabase {
  static const String dbName = 'body_frame.db';

  /// 2: body_photos.capture_grid_settings 추가. 격자를 촬영 후에도 수정할 수
  /// 있게 되면서 "촬영 당시 설정"을 되돌리기 기준점으로 따로 보존한다.
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

  /// 마이그레이션 훅. 스키마 버전이 오르면 여기에 단계별 변경을 누적한다.
  ///
  /// 각 단계는 이전 버전에서 올라오는 모든 경로에서 한 번씩 실행되도록
  /// `oldVersion < N` 조건으로 쌓는다.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.info(
      'database.upgrade',
      context: {'from': oldVersion, 'to': newVersion},
    );

    if (oldVersion < 2) {
      // 격자를 촬영 후에도 수정할 수 있게 되면서 촬영 당시 설정을 따로 보존한다.
      // 기존 행은 아직 수정된 적이 없으므로 현재 값이 곧 촬영 당시 값이다.
      await db.execute(
        'ALTER TABLE $tableBodyPhotos ADD COLUMN capture_grid_settings TEXT',
      );
      await db.execute(
        'UPDATE $tableBodyPhotos SET capture_grid_settings = grid_settings',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
