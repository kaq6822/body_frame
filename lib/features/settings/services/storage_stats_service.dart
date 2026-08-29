import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/services/photo_storage_service.dart';

/// 촬영 월별 저장 공간 사용량.
class MonthStorageUsage {
  /// `yyyyMM` 형식의 촬영 월.
  final String month;
  final int photoCount;
  final int totalBytes;

  const MonthStorageUsage({
    required this.month,
    required this.photoCount,
    required this.totalBytes,
  });
}

/// 전체 저장 공간 사용량 리포트.
class StorageUsageReport {
  final int totalBytes;
  final int totalPhotoCount;

  /// 최근 월 먼저.
  final List<MonthStorageUsage> byMonth;

  const StorageUsageReport({
    required this.totalBytes,
    required this.totalPhotoCount,
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

  StorageStatsServiceImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
  }) : _db = database,
       _storage = storage;

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

    final byMonth =
        countByMonth.keys
            .map(
              (month) => MonthStorageUsage(
                month: month,
                photoCount: countByMonth[month] ?? 0,
                totalBytes: bytesByMonth[month] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.month.compareTo(a.month));

    return StorageUsageReport(
      totalBytes: totalBytes,
      totalPhotoCount: totalCount,
      byMonth: byMonth,
    );
  }
}
