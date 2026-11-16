import '../database/app_database.dart';
import '../models/lesson_video.dart';
import '../services/app_logger.dart';
import '../services/video_storage_service.dart';

/// 레슨 동영상 조회·삭제.
///
/// 저장은 레슨 기록과 한 transaction으로 묶어야 해서
/// `MemberRepository.saveLesson`이 맡는다.
abstract class LessonVideoRepository {
  Future<List<LessonVideo>> listByRecord(String recordId);

  /// 모든 기록의 동영상(타임라인 일괄 조회용). 같은 기록 안에서는 등록순.
  Future<List<LessonVideo>> listAll();

  Future<LessonVideo?> getById(String id);

  /// 단일 동영상 삭제. DB 행을 먼저 지우고 파일을 지운다.
  Future<void> delete(String id);
}

class LessonVideoRepositoryImpl implements LessonVideoRepository {
  final AppDatabase _db;
  final VideoStorageService _storage;
  final AppLogger _logger;

  LessonVideoRepositoryImpl({
    required AppDatabase database,
    required VideoStorageService storage,
    AppLogger? logger,
  }) : _db = database,
       _storage = storage,
       _logger = logger ?? AppLogger.instance;

  @override
  Future<List<LessonVideo>> listByRecord(String recordId) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableLessonVideos,
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'created_at ASC, id ASC',
    );
    return _fromRows(rows);
  }

  @override
  Future<List<LessonVideo>> listAll() async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableLessonVideos,
      orderBy: 'created_at ASC, id ASC',
    );
    return _fromRows(rows);
  }

  @override
  Future<LessonVideo?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableLessonVideos,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : (await _fromRows(rows)).firstOrNull;
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableLessonVideos,
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.delete(
      AppDatabase.tableLessonVideos,
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await _storage.deleteFile(rows.single['file_path'] as String);
    } catch (_) {
      _logger.warn('video.delete.cleanup.failure');
    }
    _logger.phase('video.delete', LogPhase.success, context: {'id': id});
  }

  /// 경로가 망가진 행 하나 때문에 목록 전체(타임라인·상세)가 실패하지 않게
  /// 해석할 수 없는 행은 건너뛰고 기록만 남긴다. 행은 지우지 않는다.
  Future<List<LessonVideo>> _fromRows(List<Map<String, Object?>> rows) async {
    final videos = <LessonVideo>[];
    for (final row in rows) {
      try {
        final map = Map<String, dynamic>.from(row);
        map['file_path'] = await _storage.resolvePath(
          map['file_path'] as String,
        );
        videos.add(LessonVideo.fromMap(map));
      } catch (_) {
        _logger.warn('video.row.invalid', context: {'id': row['id']});
      }
    }
    return videos;
  }
}
