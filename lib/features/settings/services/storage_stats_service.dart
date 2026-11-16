import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/services/video_storage_service.dart';

/// 촬영 월별 저장 공간 사용량.
class MonthStorageUsage {
  /// `yyyyMM` 형식의 촬영 월.
  final String month;
  final int photoCount;
  final int videoCount;
  final int totalBytes;

  const MonthStorageUsage({
    required this.month,
    required this.photoCount,
    this.videoCount = 0,
    required this.totalBytes,
  });
}

/// 전체 저장 공간 사용량 리포트.
class StorageUsageReport {
  final int totalBytes;
  final int totalPhotoCount;
  final int totalVideoCount;

  /// [totalBytes] 중 동영상이 차지하는 용량.
  final int videoBytes;

  /// 최근 월 먼저.
  final List<MonthStorageUsage> byMonth;

  const StorageUsageReport({
    required this.totalBytes,
    required this.totalPhotoCount,
    this.totalVideoCount = 0,
    this.videoBytes = 0,
    required this.byMonth,
  });

  static const empty = StorageUsageReport(
    totalBytes: 0,
    totalPhotoCount: 0,
    byMonth: [],
  );
}

abstract class StorageStatsService {
  Future<StorageUsageReport> collect();
}

class StorageStatsServiceImpl implements StorageStatsService {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final VideoStorageService _videoStorage;

  StorageStatsServiceImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    VideoStorageService? videoStorage,
  }) : _db = database,
       _storage = storage,
       _videoStorage = videoStorage ?? VideoStorageServiceImpl();

  @override
  Future<StorageUsageReport> collect() async {
    final db = await _db.database;

    final photoRows = await db.rawQuery('''
      SELECT r.shot_at AS shot_at, p.file_path AS file_path
      FROM ${AppDatabase.tableBodyPhotos} p
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = p.record_id
    ''');

    final countByMonth = <String, int>{};
    final bytesByMonth = <String, int>{};
    var totalBytes = 0;
    var totalCount = 0;

    for (final row in photoRows) {
      final shotAt = DateTime.fromMillisecondsSinceEpoch(row['shot_at'] as int);
      final month = PhotoStorageServiceImpl.bucketName(shotAt);
      final filePath = await _storage.resolvePath(row['file_path'] as String);
      final file = File(filePath);
      final size = await file.exists() ? await file.length() : 0;
      totalBytes += size;
      totalCount += 1;
      countByMonth[month] = (countByMonth[month] ?? 0) + 1;
      bytesByMonth[month] = (bytesByMonth[month] ?? 0) + size;
    }

    final videoRows = await db.rawQuery('''
      SELECT r.shot_at AS shot_at, v.file_path AS file_path
      FROM ${AppDatabase.tableLessonVideos} v
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = v.record_id
    ''');
    final videosByMonth = <String, int>{};
    var videoBytes = 0;
    for (final row in videoRows) {
      final shotAt = DateTime.fromMillisecondsSinceEpoch(row['shot_at'] as int);
      final month = PhotoStorageServiceImpl.bucketName(shotAt);
      // 개수는 경로 해석과 무관하게 센다. 해석할 수 없는 행은 용량만 0으로 둔다.
      var size = 0;
      try {
        final file = File(
          await _videoStorage.resolvePath(row['file_path'] as String),
        );
        if (await file.exists()) size = await file.length();
      } catch (_) {
        AppLogger.instance.warn('storage.video.row.invalid');
      }
      videoBytes += size;
      totalBytes += size;
      videosByMonth[month] = (videosByMonth[month] ?? 0) + 1;
      bytesByMonth[month] = (bytesByMonth[month] ?? 0) + size;
    }

    final byMonth =
        {...countByMonth.keys, ...videosByMonth.keys}
            .map(
              (month) => MonthStorageUsage(
                month: month,
                photoCount: countByMonth[month] ?? 0,
                videoCount: videosByMonth[month] ?? 0,
                totalBytes: bytesByMonth[month] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.month.compareTo(a.month));

    return StorageUsageReport(
      totalBytes: totalBytes,
      totalPhotoCount: totalCount,
      totalVideoCount: videoRows.length,
      videoBytes: videoBytes,
      byMonth: byMonth,
    );
  }
}
