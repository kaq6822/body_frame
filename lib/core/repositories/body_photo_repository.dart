import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/body_direction.dart';
import '../models/body_photo.dart';
import '../services/app_logger.dart';
import '../services/photo_storage_service.dart';

/// 체형 사진 CRUD.
///
/// 사진 삭제 시 DB 행과 저장소 파일을 함께 제거한다. 원본 파일은 절대
/// 수정하거나 덮어쓰지 않으며 메타데이터만 갱신한다.
abstract class BodyPhotoRepository {
  Future<List<BodyPhoto>> listByRecord(String recordId);

  /// 특정 방향의 사진 전체(비교 화면에서 날짜별 선택에 사용). 최신 촬영일 먼저.
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction);

  /// 모든 촬영 기록에 속한 사진 전체(방향 무관). 홈 타임라인에서 기록마다
  /// [listByRecord]를 개별 호출하면 N+1 쿼리가 발생하므로, 한 번에 조회한 뒤
  /// recordId로 그룹핑해 쓰기 위한 배치 조회 메서드.
  Future<List<BodyPhoto>> listAll();

  Future<BodyPhoto?> getById(String id);

  Future<void> insert(BodyPhoto photo);

  /// 메타데이터(방향/메모/회전 등) 갱신. 원본 파일은 건드리지 않는다.
  Future<void> update(BodyPhoto photo);

  /// 단일 사진 삭제(DB 행 + 파일).
  Future<void> delete(String id);
}

class BodyPhotoRepositoryImpl implements BodyPhotoRepository {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppLogger _logger;

  BodyPhotoRepositoryImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    AppLogger? logger,
  }) : _db = database,
       _storage = storage,
       _logger = logger ?? AppLogger.instance;

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableBodyPhotos,
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'created_at ASC',
    );
    return Future.wait(rows.map(_photoFromRow));
  }

  @override
  Future<List<BodyPhoto>> listByDirection(BodyDirection direction) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT bp.*
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      WHERE bp.direction = ?
      ORDER BY r.shot_at DESC, bp.created_at DESC, bp.id DESC
    ''',
      [direction.key],
    );
    return Future.wait(rows.map(_photoFromRow));
  }

  @override
  Future<List<BodyPhoto>> listAll() async {
    final db = await _db.database;
    // 기록별 그룹핑을 쉽게 하도록 최신 촬영일 순으로 정렬하고,
    // 같은 기록 안에서는 등록순을 유지한다.
    final rows = await db.rawQuery('''
      SELECT bp.*
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      ORDER BY r.shot_at DESC, bp.created_at ASC
    ''');
    return Future.wait(rows.map(_photoFromRow));
  }

  @override
  Future<BodyPhoto?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableBodyPhotos,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _photoFromRow(rows.first);
  }

  @override
  Future<void> insert(BodyPhoto photo) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableBodyPhotos,
      await _storedPhotoMap(photo),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _logger.phase('photo.insert', LogPhase.success, context: {'id': photo.id});
  }

  @override
  Future<void> update(BodyPhoto photo) async {
    final db = await _db.database;
    final existingRows = await db.query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path', 'record_id', 'capture_grid_settings'],
      where: 'id = ?',
      whereArgs: [photo.id],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      throw StateError('수정할 사진을 찾을 수 없습니다.');
    }
    if (existingRows.single['record_id'] != photo.recordId) {
      throw StateError('사진을 다른 촬영 기록으로 이동할 수 없습니다.');
    }

    final map = await _storedPhotoMap(photo);

    // 촬영 당시 격자 설정은 되돌리기의 기준점이다. 모델이 무엇을 들고 왔든
    // 저장된 값을 그대로 유지해, 수정 경로에서 기준점이 밀리지 않게 한다.
    final storedCaptureGrid = existingRows.single['capture_grid_settings'];
    if (storedCaptureGrid != null) {
      map['capture_grid_settings'] = storedCaptureGrid;
    }
    final oldPath = existingRows.single['file_path'] as String;
    final newPath = map['file_path'] as String;

    final updated = await db.update(
      AppDatabase.tableBodyPhotos,
      map,
      where: 'id = ?',
      whereArgs: [photo.id],
    );
    if (updated != 1) {
      throw StateError('사진 수정 결과가 올바르지 않습니다.');
    }
    if (oldPath != newPath) {
      await _deleteBestEffort(oldPath);
    }
    _logger.phase('photo.update', LogPhase.success, context: {'id': photo.id});
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    await db.delete(
      AppDatabase.tableBodyPhotos,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _deleteBestEffort(rows.single['file_path'] as String);
    _logger.phase('photo.delete', LogPhase.success, context: {'id': id});
  }

  Future<BodyPhoto> _photoFromRow(Map<String, Object?> row) async {
    final map = Map<String, dynamic>.from(row);
    map['file_path'] = await _storage.resolvePath(map['file_path'] as String);
    return BodyPhoto.fromMap(map);
  }

  Future<Map<String, dynamic>> _storedPhotoMap(BodyPhoto photo) async {
    final map = photo.toMap();
    final storedPath = await _storage.toStoredPath(photo.filePath);
    final segments = p.posix.split(storedPath);
    if (segments.length < 3 ||
        segments[0] != PhotoStorageServiceImpl.rootDirName) {
      throw StateError('사진 파일이 앱 사진 저장소 안에 있지 않습니다.');
    }
    map['file_path'] = storedPath;
    return map;
  }

  Future<void> _deleteBestEffort(String storedPath) async {
    try {
      await _storage.deleteFile(storedPath);
    } catch (_) {
      _logger.warn('storage.delete.failure');
    }
  }
}
