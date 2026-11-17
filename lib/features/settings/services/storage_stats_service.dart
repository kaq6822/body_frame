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

/// 회원 한 명(또는 회원 미연결 기록)이 차지하는 저장 공간.
class MemberStorageUsage {
  /// null이면 회원이 연결되지 않은 기록 묶음이다.
  final String? memberId;

  /// 회원 이름. 미연결 묶음은 빈 문자열이다.
  final String name;
  final int photoCount;
  final int videoCount;
  final int totalBytes;

  const MemberStorageUsage({
    required this.memberId,
    required this.name,
    required this.photoCount,
    required this.videoCount,
    required this.totalBytes,
  });

  bool get isUnlinked => memberId == null;
}

/// 집계 입력이 되는 파일 하나. [memberId]는 그 파일이 속한 레슨의 회원이다.
class StoredFileUsage {
  final String? memberId;
  final bool isVideo;
  final int bytes;

  const StoredFileUsage({
    required this.memberId,
    required this.isVideo,
    required this.bytes,
  });
}

/// 파일별 용량을 회원별로 묶어 큰 순서로 정렬한다.
///
/// - [memberNames]에 없는 회원 id의 파일은 회원 미연결 묶음에 더한다. 화면에
///   보여 줄 이름이 없고, 임의의 회원에게 붙여 보이면 안 되기 때문이다.
/// - 미연결 묶음은 용량이 0보다 클 때만 넣는다.
/// - 용량이 같으면 이름순, 미연결 묶음은 같은 용량의 회원 뒤에 둔다.
List<MemberStorageUsage> aggregateMemberStorage(
  Iterable<StoredFileUsage> files,
  Map<String, String> memberNames,
) {
  final photos = <String?, int>{};
  final videos = <String?, int>{};
  final bytes = <String?, int>{};
  for (final file in files) {
    final key = memberNames.containsKey(file.memberId) ? file.memberId : null;
    final counts = file.isVideo ? videos : photos;
    counts[key] = (counts[key] ?? 0) + 1;
    bytes[key] = (bytes[key] ?? 0) + file.bytes;
  }
  final result = [
    for (final key in bytes.keys)
      if (key != null || bytes[key]! > 0)
        MemberStorageUsage(
          memberId: key,
          name: key == null ? '' : memberNames[key]!,
          photoCount: photos[key] ?? 0,
          videoCount: videos[key] ?? 0,
          totalBytes: bytes[key]!,
        ),
  ];
  result.sort((a, b) {
    final bySize = b.totalBytes.compareTo(a.totalBytes);
    if (bySize != 0) return bySize;
    if (a.isUnlinked != b.isUnlinked) return a.isUnlinked ? 1 : -1;
    final byName = a.name.compareTo(b.name);
    return byName != 0
        ? byName
        : (a.memberId ?? '').compareTo(b.memberId ?? '');
  });
  return result;
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

  /// 큰 순서. [aggregateMemberStorage] 참고.
  final List<MemberStorageUsage> byMember;

  const StorageUsageReport({
    required this.totalBytes,
    required this.totalPhotoCount,
    this.totalVideoCount = 0,
    this.videoBytes = 0,
    required this.byMonth,
    this.byMember = const [],
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
      SELECT r.shot_at AS shot_at, r.member_id AS member_id,
        p.file_path AS file_path
      FROM ${AppDatabase.tableBodyPhotos} p
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = p.record_id
    ''');

    final countByMonth = <String, int>{};
    final bytesByMonth = <String, int>{};
    var totalBytes = 0;
    var totalCount = 0;
    final files = <StoredFileUsage>[];

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
      files.add(
        StoredFileUsage(
          memberId: row['member_id'] as String?,
          isVideo: false,
          bytes: size,
        ),
      );
    }

    final videoRows = await db.rawQuery('''
      SELECT r.shot_at AS shot_at, r.member_id AS member_id,
        v.file_path AS file_path
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
      files.add(
        StoredFileUsage(
          memberId: row['member_id'] as String?,
          isVideo: true,
          bytes: size,
        ),
      );
    }

    final memberRows = await db.rawQuery('SELECT id, name FROM members');
    final memberNames = {
      for (final row in memberRows) row['id'] as String: row['name'] as String,
    };

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
      byMember: aggregateMemberStorage(files, memberNames),
    );
  }
}
