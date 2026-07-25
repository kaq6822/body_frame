import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/photo_record.dart';
import '../services/app_logger.dart';
import '../services/photo_storage_service.dart';

/// 촬영 기록 CRUD.
///
/// 촬영 기록 삭제 시 소속 사진(DB 행)은 외래 키 CASCADE로 정리되지만
/// 사진 파일은 [BodyPhotoRepository]를 통해 명시적으로 삭제해야 한다.
abstract class PhotoRecordRepository {
  /// 회원의 촬영 기록 목록(최신 촬영일 먼저).
  Future<List<PhotoRecord>> listByMember(String memberId);

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
  Future<List<PhotoRecord>> listByMember(String memberId) async {
    await _storage.reconcilePendingQuarantines();
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
    await _storage.reconcilePendingQuarantines();
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
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    await db.insert(
      AppDatabase.tablePhotoRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    _logger.phase(
      'record.insert',
      LogPhase.success,
      context: {'id': record.id},
    );
  }

  @override
  Future<void> update(PhotoRecord record) async {
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tablePhotoRecords,
        columns: ['member_id'],
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (existing.isEmpty) {
        throw StateError('수정할 촬영 기록을 찾을 수 없습니다.');
      }
      if (existing.single['member_id'] != record.memberId) {
        throw StateError('촬영 기록을 다른 회원으로 이동할 수 없습니다.');
      }
      final updated = await txn.update(
        AppDatabase.tablePhotoRecords,
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      if (updated != 1) {
        throw StateError('촬영 기록 수정 결과가 올바르지 않습니다.');
      }
    });
    _logger.phase(
      'record.update',
      LogPhase.success,
      context: {'id': record.id},
    );
  }

  @override
  Future<void> delete(String id) async {
    await _storage.reconcilePendingQuarantines();
    _logger.phase('record.delete', LogPhase.start, context: {'id': id});
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path'],
      where: 'record_id = ?',
      whereArgs: [id],
    );
    final quarantines = <StorageQuarantine>[];
    try {
      for (final row in rows) {
        final quarantine = await _storage.quarantineFile(
          row['file_path'] as String,
        );
        if (quarantine != null) quarantines.add(quarantine);
      }
    } catch (_) {
      await _restoreAll(quarantines);
      rethrow;
    }
    try {
      await db.transaction((txn) async {
        await txn.delete(
          AppDatabase.tablePhotoRecords,
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } catch (_) {
      await _restoreAll(quarantines);
      rethrow;
    }
    for (final quarantine in quarantines) {
      try {
        await _storage.discardQuarantine(quarantine);
      } catch (_) {
        _logger.warn('storage.quarantine.cleanup.failure');
      }
    }
    _logger.phase('record.delete', LogPhase.success, context: {'id': id});
  }

  Future<void> _restoreAll(List<StorageQuarantine> quarantines) async {
    for (final quarantine in quarantines.reversed) {
      await _storage.restoreQuarantine(quarantine);
    }
  }
}
