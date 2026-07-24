import 'dart:io';

import '../../../core/database/app_database.dart';

/// 회원별 저장 공간 사용량.
class MemberStorageUsage {
  final String memberId;
  final String memberName;
  final int photoCount;
  final int totalBytes;

  const MemberStorageUsage({
    required this.memberId,
    required this.memberName,
    required this.photoCount,
    required this.totalBytes,
  });
}

/// 전체 저장 공간 사용량 리포트.
class StorageUsageReport {
  final int totalBytes;
  final int totalPhotoCount;
  final List<MemberStorageUsage> byMember;

  const StorageUsageReport({
    required this.totalBytes,
    required this.totalPhotoCount,
    required this.byMember,
  });

  static const empty =
      StorageUsageReport(totalBytes: 0, totalPhotoCount: 0, byMember: []);
}

abstract class StorageStatsService {
  Future<StorageUsageReport> collect();
}

class StorageStatsServiceImpl implements StorageStatsService {
  final AppDatabase _db;

  StorageStatsServiceImpl({required AppDatabase database}) : _db = database;

  @override
  Future<StorageUsageReport> collect() async {
    final db = await _db.database;

    final memberRows = await db.query(
      AppDatabase.tableMembers,
      columns: ['id', 'name'],
    );

    final photoRows = await db.rawQuery('''
      SELECT r.member_id AS member_id, p.file_path AS file_path
      FROM ${AppDatabase.tableBodyPhotos} p
      JOIN ${AppDatabase.tablePhotoRecords} r ON r.id = p.record_id
    ''');

    final countByMember = <String, int>{};
    final bytesByMember = <String, int>{};
    var totalBytes = 0;
    var totalCount = 0;

    for (final row in photoRows) {
      final memberId = row['member_id'] as String;
      final filePath = row['file_path'] as String;
      final file = File(filePath);
      final size = await file.exists() ? await file.length() : 0;
      totalBytes += size;
      totalCount += 1;
      countByMember[memberId] = (countByMember[memberId] ?? 0) + 1;
      bytesByMember[memberId] = (bytesByMember[memberId] ?? 0) + size;
    }

    final byMember = memberRows.map((m) {
      final id = m['id'] as String;
      return MemberStorageUsage(
        memberId: id,
        memberName: m['name'] as String,
        photoCount: countByMember[id] ?? 0,
        totalBytes: bytesByMember[id] ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    return StorageUsageReport(
      totalBytes: totalBytes,
      totalPhotoCount: totalCount,
      byMember: byMember,
    );
  }
}
