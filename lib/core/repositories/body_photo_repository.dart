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

  /// 회원의 특정 방향 사진 전체(비교 화면에서 날짜별 선택에 사용).
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  );

  /// 회원의 모든 촬영 기록에 속한 사진 전체(방향 무관). 회원 상세 화면에서
  /// 기록마다 [listByRecord]를 개별 호출하면 N+1 쿼리가 발생하므로, 한 번에
  /// 조회한 뒤 recordId로 그룹핑해 쓰기 위한 배치 조회 메서드.
  Future<List<BodyPhoto>> listByMember(String memberId);

  Future<BodyPhoto?> getById(String id);

  Future<void> insert(BodyPhoto photo);

  /// 메타데이터(방향/메모/회전 등) 갱신. 원본 파일은 건드리지 않는다.
  Future<void> update(BodyPhoto photo);

  /// 단일 사진 삭제(DB 행 + 파일).
  Future<void> delete(String id);

  /// 촬영 기록에 속한 모든 사진의 파일을 삭제한다(행은 CASCADE로 정리).
  Future<void> deleteByRecord(String recordId);
}

class BodyPhotoRepositoryImpl implements BodyPhotoRepository {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppLogger _logger;

  BodyPhotoRepositoryImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    AppLogger? logger,
  })  : _db = database,
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
    return rows.map(BodyPhoto.fromMap).toList();
  }

  @override
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async {
    final db = await _db.database;
    // 회원 → 촬영 기록 → 사진 조인. 최신 촬영일 먼저.
    final sql = '''
      SELECT bp.*, r.shot_at AS r_shot_at
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      WHERE r.member_id = ? AND bp.direction = ?
      ORDER BY r.shot_at DESC
    ''';
    final rows = await db.rawQuery(sql, [memberId, direction.key]);
    return rows.map(BodyPhoto.fromMap).toList();
  }

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async {
    final db = await _db.database;
    // 회원 → 촬영 기록 → 사진 조인. 기록별 그룹핑을 쉽게 하도록 최신 촬영일
    // 순으로 정렬하고, 같은 기록 내에서는 등록순을 유지한다.
    final sql = '''
      SELECT bp.*
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      WHERE r.member_id = ?
      ORDER BY r.shot_at DESC, bp.created_at ASC
    ''';
    final rows = await db.rawQuery(sql, [memberId]);
    return rows.map(BodyPhoto.fromMap).toList();
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
    return BodyPhoto.fromMap(rows.first);
  }

  @override
  Future<void> insert(BodyPhoto photo) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableBodyPhotos,
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _logger.phase('photo.insert', LogPhase.success, context: {'id': photo.id});
  }

  @override
  Future<void> update(BodyPhoto photo) async {
    final db = await _db.database;
    await db.update(
      AppDatabase.tableBodyPhotos,
      photo.toMap(),
      where: 'id = ?',
      whereArgs: [photo.id],
    );
    _logger.phase('photo.update', LogPhase.success, context: {'id': photo.id});
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db.database;
    final photo = await getById(id);
    await db.delete(
      AppDatabase.tableBodyPhotos,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (photo != null) {
      await _storage.deleteFile(photo.filePath);
    }
    _logger.phase('photo.delete', LogPhase.success, context: {'id': id});
  }

  @override
  Future<void> deleteByRecord(String recordId) async {
    final photos = await listByRecord(recordId);
    for (final photo in photos) {
      await _storage.deleteFile(photo.filePath);
    }
    // DB 행은 촬영 기록 삭제 시 CASCADE로 정리되지만, 단독 호출 대비 함께 삭제.
    final db = await _db.database;
    await db.delete(
      AppDatabase.tableBodyPhotos,
      where: 'record_id = ?',
      whereArgs: [recordId],
    );
    _logger.info('photo.deleteByRecord', context: {'count': photos.length});
  }
}
