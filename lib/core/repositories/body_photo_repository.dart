import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

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
  }) : _db = database,
       _storage = storage,
       _logger = logger ?? AppLogger.instance;

  @override
  Future<List<BodyPhoto>> listByRecord(String recordId) async {
    await _storage.reconcilePendingQuarantines();
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
  Future<List<BodyPhoto>> listByMemberDirection(
    String memberId,
    BodyDirection direction,
  ) async {
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    // 회원 → 촬영 기록 → 사진 조인. 최신 촬영일 먼저.
    final sql =
        '''
      SELECT bp.*, r.shot_at AS r_shot_at
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      WHERE r.member_id = ? AND bp.direction = ?
      ORDER BY r.shot_at DESC
    ''';
    final rows = await db.rawQuery(sql, [memberId, direction.key]);
    return Future.wait(rows.map(_photoFromRow));
  }

  @override
  Future<List<BodyPhoto>> listByMember(String memberId) async {
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    // 회원 → 촬영 기록 → 사진 조인. 기록별 그룹핑을 쉽게 하도록 최신 촬영일
    // 순으로 정렬하고, 같은 기록 내에서는 등록순을 유지한다.
    final sql =
        '''
      SELECT bp.*
      FROM ${AppDatabase.tableBodyPhotos} bp
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = bp.record_id
      WHERE r.member_id = ?
      ORDER BY r.shot_at DESC, bp.created_at ASC
    ''';
    final rows = await db.rawQuery(sql, [memberId]);
    return Future.wait(rows.map(_photoFromRow));
  }

  @override
  Future<BodyPhoto?> getById(String id) async {
    await _storage.reconcilePendingQuarantines();
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
    await _storage.reconcilePendingQuarantines();
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
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    final existingRows = await db.query(
      AppDatabase.tableBodyPhotos,
      columns: ['file_path', 'record_id'],
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
    final oldPath = existingRows.single['file_path'] as String;
    final newPath = map['file_path'] as String;
    StorageQuarantine? quarantine;
    if (oldPath != newPath) {
      quarantine = await _storage.quarantineFile(oldPath);
    }
    try {
      final updated = await db.update(
        AppDatabase.tableBodyPhotos,
        map,
        where: 'id = ?',
        whereArgs: [photo.id],
      );
      if (updated != 1) {
        throw StateError('사진 수정 결과가 올바르지 않습니다.');
      }
    } catch (_) {
      if (quarantine != null) {
        await _storage.restoreQuarantine(quarantine);
      }
      rethrow;
    }
    await _discardBestEffort(quarantine);
    _logger.phase('photo.update', LogPhase.success, context: {'id': photo.id});
  }

  @override
  Future<void> delete(String id) async {
    await _storage.reconcilePendingQuarantines();
    final db = await _db.database;
    final photo = await getById(id);
    final quarantine = photo == null
        ? null
        : await _storage.quarantineFile(photo.filePath);
    try {
      await db.transaction((txn) async {
        await txn.delete(
          AppDatabase.tableBodyPhotos,
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } catch (_) {
      if (quarantine != null) {
        await _storage.restoreQuarantine(quarantine);
      }
      rethrow;
    }
    await _discardBestEffort(quarantine);
    _logger.phase('photo.delete', LogPhase.success, context: {'id': id});
  }

  @override
  Future<void> deleteByRecord(String recordId) async {
    await _storage.reconcilePendingQuarantines();
    final photos = await listByRecord(recordId);
    final quarantines = <StorageQuarantine>[];
    try {
      for (final photo in photos) {
        final quarantine = await _storage.quarantineFile(photo.filePath);
        if (quarantine != null) quarantines.add(quarantine);
      }
    } catch (_) {
      await _restoreAll(quarantines);
      rethrow;
    }
    final db = await _db.database;
    try {
      await db.transaction((txn) async {
        await txn.delete(
          AppDatabase.tableBodyPhotos,
          where: 'record_id = ?',
          whereArgs: [recordId],
        );
      });
    } catch (_) {
      await _restoreAll(quarantines);
      rethrow;
    }
    for (final quarantine in quarantines) {
      await _discardBestEffort(quarantine);
    }
    _logger.info('photo.deleteByRecord', context: {'count': photos.length});
  }

  Future<BodyPhoto> _photoFromRow(Map<String, Object?> row) async {
    final map = Map<String, dynamic>.from(row);
    map['file_path'] = await _storage.resolvePath(map['file_path'] as String);
    return BodyPhoto.fromMap(map);
  }

  Future<Map<String, dynamic>> _storedPhotoMap(BodyPhoto photo) async {
    final db = await _db.database;
    final ownerRows = await db.query(
      AppDatabase.tablePhotoRecords,
      columns: ['member_id'],
      where: 'id = ?',
      whereArgs: [photo.recordId],
      limit: 1,
    );
    if (ownerRows.isEmpty) {
      throw StateError('사진의 촬영 기록을 찾을 수 없습니다.');
    }
    final memberId = ownerRows.single['member_id'] as String;
    final map = photo.toMap();
    final storedPath = await _storage.toStoredPath(photo.filePath);
    final segments = p.posix.split(storedPath);
    if (segments.length < 3 ||
        segments[0] != PhotoStorageServiceImpl.rootDirName ||
        segments[1] != memberId) {
      throw StateError('사진 파일이 촬영 기록 소유자의 저장소에 있지 않습니다.');
    }
    map['file_path'] = storedPath;
    return map;
  }

  Future<void> _restoreAll(List<StorageQuarantine> quarantines) async {
    for (final quarantine in quarantines.reversed) {
      await _storage.restoreQuarantine(quarantine);
    }
  }

  Future<void> _discardBestEffort(StorageQuarantine? quarantine) async {
    if (quarantine == null) return;
    try {
      await _storage.discardQuarantine(quarantine);
    } catch (_) {
      _logger.warn('storage.quarantine.cleanup.failure');
    }
  }
}
