import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/body_photo.dart';
import '../models/photo_record.dart';
import '../services/app_logger.dart';
import '../services/photo_storage_service.dart';

/// 앱 저장소에 준비를 마친 사진과 새 촬영 기록을 한 번에 영속화한다.
///
/// 파일 복사와 메타데이터 판독은 호출자가 먼저 끝낸다. 이 리포지토리는 새
/// [PhotoRecord]와 모든 [BodyPhoto] 행을 하나의 SQLite transaction에서
/// 반영하므로, 프로세스가 중단돼도 빈 기록이나 부분 등록이 남지 않는다.
abstract class PhotoIngestRepository {
  Future<void> insertPrepared({
    required List<PhotoRecord> newRecords,
    required List<BodyPhoto> photos,
  });
}

class PhotoIngestRepositoryImpl implements PhotoIngestRepository {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppLogger _logger;

  PhotoIngestRepositoryImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    AppLogger? logger,
  }) : _db = database,
       _storage = storage,
       _logger = logger ?? AppLogger.instance;

  @override
  Future<void> insertPrepared({
    required List<PhotoRecord> newRecords,
    required List<BodyPhoto> photos,
  }) async {
    if (photos.isEmpty) {
      throw ArgumentError.value(photos, 'photos', '등록할 사진이 필요합니다.');
    }

    final newRecordIds = <String>{};
    for (final record in newRecords) {
      if (!newRecordIds.add(record.id)) {
        throw StateError('새 촬영 기록 식별자가 중복됩니다.');
      }
    }

    final photoRecordIds = photos.map((photo) => photo.recordId).toSet();
    if (!photoRecordIds.containsAll(newRecordIds)) {
      throw StateError('사진이 없는 새 촬영 기록은 등록할 수 없습니다.');
    }

    final photoIds = <String>{};
    final storedPhotoMaps = <Map<String, Object?>>[];
    for (final photo in photos) {
      if (!photoIds.add(photo.id)) {
        throw StateError('사진 식별자가 중복됩니다.');
      }
      final storedPath = await _storage.toStoredPath(photo.filePath);
      final segments = p.posix.split(storedPath);
      if (segments.length < 3 ||
          segments[0] != PhotoStorageServiceImpl.rootDirName) {
        throw StateError('사진 파일이 앱 사진 저장소 안에 있지 않습니다.');
      }
      storedPhotoMaps.add(<String, Object?>{
        ...photo.toMap(),
        'file_path': storedPath,
      });
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      for (final recordId in photoRecordIds) {
        if (newRecordIds.contains(recordId)) continue;
        final rows = await txn.query(
          AppDatabase.tablePhotoRecords,
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [recordId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('사진의 촬영 기록을 찾을 수 없습니다.');
        }
      }

      for (final record in newRecords) {
        await txn.insert(
          AppDatabase.tablePhotoRecords,
          record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final map in storedPhotoMaps) {
        await txn.insert(
          AppDatabase.tableBodyPhotos,
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
    _logger.info(
      'photo.ingest',
      context: {
        'recordCount': newRecords.length,
        'photoCount': photos.length,
      },
    );
  }
}
