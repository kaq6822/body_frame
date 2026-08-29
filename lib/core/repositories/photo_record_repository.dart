import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/photo_record.dart';
import '../services/app_logger.dart';
import '../services/photo_storage_service.dart';

/// 촬영 기록 CRUD.
///
/// 촬영 기록 삭제 시 소속 사진 DB 행은 외래 키 CASCADE로 정리되지만
/// 사진 파일은 이 리포지토리가 명시적으로 지운다.
abstract class PhotoRecordRepository {
  /// 전체 촬영 기록 목록(최신 촬영일 먼저).
  Future<List<PhotoRecord>> listAll();

  Future<PhotoRecord?> getById(String id);

  Future<void> insert(PhotoRecord record);

  Future<void> update(PhotoRecord record);

  /// 촬영 기록과 소속 사진(행+파일)을 삭제한다.
  Future<void> delete(String id);
}

class PhotoRecordRepositoryImpl implements PhotoRecordRepository {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppLogger _logger;

  PhotoRecordRepositoryImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    AppLogger? logger,
  }) : _db = database,
       _storage = storage,
       _logger = logger ?? AppLogger.instance;

  @override
  Future<List<PhotoRecord>> listAll() async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tablePhotoRecords,
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
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _logger.phase('record.insert', LogPhase.success, context: {'id': record.id});
  }

  @override
  Future<void> update(PhotoRecord record) async {
    final db = await _db.database;
    final updated = await db.update(
      AppDatabase.tablePhotoRecords,
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
    if (updated != 1) {
      throw StateError('수정할 촬영 기록을 찾을 수 없습니다.');
    }
    _logger.phase('record.update', LogPhase.success, context: {'id': record.id});
  }

  @override
  Future<void> delete(String id) async {
    _logger.phase('record.delete', LogPhase.start, context: {'id': id});
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path'],
      where: 'record_id = ?',
      whereArgs: [id],
    );

    // 행을 먼저 지운다. 파일 삭제가 실패해 고아 파일이 남는 편이,
    // 파일이 사라진 행이 남아 깨진 썸네일을 보여주는 것보다 낫다.
    await db.delete(
      AppDatabase.tablePhotoRecords,
      where: 'id = ?',
      whereArgs: [id],
    );

    for (final row in rows) {
      try {
        await _storage.deleteFile(row['file_path'] as String);
      } catch (_) {
        _logger.warn('storage.delete.failure');
      }
    }
    _logger.phase('record.delete', LogPhase.success, context: {'id': id});
  }
}
