import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/photo_record.dart';
import '../services/app_logger.dart';
import 'body_photo_repository.dart';

/// 촬영 기록 CRUD. MVP.md 6장.
///
/// 촬영 기록 삭제 시 소속 사진(DB 행)은 외래 키 CASCADE로 정리되지만
/// 사진 파일은 [BodyPhotoRepository]를 통해 명시적으로 삭제해야 한다.
abstract class PhotoRecordRepository {
  /// 회원의 촬영 기록 목록. MVP.md 6.2: 최신 촬영일 먼저.
  Future<List<PhotoRecord>> listByMember(String memberId);

  Future<PhotoRecord?> getById(String id);

  Future<void> insert(PhotoRecord record);

  Future<void> update(PhotoRecord record);

  /// 촬영 기록과 소속 사진(행+파일)을 삭제한다.
  Future<void> delete(String id);
}

class PhotoRecordRepositoryImpl implements PhotoRecordRepository {
  final AppDatabase _db;
  final BodyPhotoRepository _photos;
  final AppLogger _logger;

  PhotoRecordRepositoryImpl({
    required AppDatabase database,
    required BodyPhotoRepository photos,
    AppLogger? logger,
  })  : _db = database,
        _photos = photos,
        _logger = logger ?? AppLogger.instance;

  @override
  Future<List<PhotoRecord>> listByMember(String memberId) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tablePhotoRecords,
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'shot_at DESC, created_at DESC',
    );
    return rows.map(PhotoRecord.fromMap).toList();
  }

  @override
  Future<PhotoRecord?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tablePhotoRecords,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PhotoRecord.fromMap(rows.first);
  }

  @override
  Future<void> insert(PhotoRecord record) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tablePhotoRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _logger.phase('record.insert', LogPhase.success, context: {'id': record.id});
  }

  @override
  Future<void> update(PhotoRecord record) async {
    final db = await _db.database;
    await db.update(
      AppDatabase.tablePhotoRecords,
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
    _logger.phase('record.update', LogPhase.success, context: {'id': record.id});
  }

  @override
  Future<void> delete(String id) async {
    _logger.phase('record.delete', LogPhase.start, context: {'id': id});
    // 먼저 소속 사진 파일을 정리(DB 행은 이후 CASCADE로 삭제).
    await _photos.deleteByRecord(id);
    final db = await _db.database;
    await db.delete(
      AppDatabase.tablePhotoRecords,
      where: 'id = ?',
      whereArgs: [id],
    );
    _logger.phase('record.delete', LogPhase.success, context: {'id': id});
  }
}
