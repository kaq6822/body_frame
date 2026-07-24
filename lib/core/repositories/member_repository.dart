import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/member.dart';
import '../services/app_logger.dart';
import '../services/photo_storage_service.dart';

/// 회원 목록 정렬 기준.
enum MemberSort {
  /// 최근 촬영순(촬영 기록이 없으면 뒤로).
  recentShot,

  /// 이름순(가나다).
  name,

  /// 등록일순(최신 먼저).
  registeredAt,
}

/// 회원 목록 표시용 값 객체.
class MemberListItem {
  final Member member;

  /// 저장된 촬영 기록 수.
  final int recordCount;

  /// 최근 촬영일(기록이 없으면 null).
  final DateTime? lastShotAt;

  const MemberListItem({
    required this.member,
    required this.recordCount,
    required this.lastShotAt,
  });
}

/// 회원 CRUD + 검색/정렬. 회원 삭제 시 촬영 기록/사진/파일을 연쇄 삭제한다.
///
/// 테스트에서 Riverpod override로 대체할 수 있도록 인터페이스를 분리한다.
abstract class MemberRepository {
  Future<List<MemberListItem>> list({
    String? query,
    MemberSort sort = MemberSort.recentShot,
  });

  Future<Member?> getById(String id);

  Future<void> insert(Member member);

  Future<void> update(Member member);

  /// 회원과 그에 속한 촬영 기록/사진(DB 행) 및 저장소 파일을 모두 삭제한다.
  /// 삭제 확인은 UI 계층에서 처리한다.
  Future<void> delete(String id);
}

class MemberRepositoryImpl implements MemberRepository {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppLogger _logger;

  MemberRepositoryImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    AppLogger? logger,
  })  : _db = database,
        _storage = storage,
        _logger = logger ?? AppLogger.instance;

  @override
  Future<List<MemberListItem>> list({
    String? query,
    MemberSort sort = MemberSort.recentShot,
  }) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('m.name LIKE ?');
      args.add('%${query.trim()}%');
    }

    // 촬영 기록 수와 최근 촬영일을 LEFT JOIN 집계로 함께 구한다.
    final orderBy = switch (sort) {
      // (last_shot_at IS NULL)로 NULL을 뒤로 보낸다(NULLS LAST 미지원 SQLite 대비).
      MemberSort.recentShot =>
        '(last_shot_at IS NULL), last_shot_at DESC, m.created_at DESC',
      MemberSort.name => 'm.name COLLATE NOCASE ASC',
      MemberSort.registeredAt => 'm.created_at DESC',
    };

    final sql = '''
      SELECT m.*,
             COUNT(r.id) AS record_count,
             MAX(r.shot_at) AS last_shot_at
      FROM ${AppDatabase.tableMembers} m
      LEFT JOIN ${AppDatabase.tablePhotoRecords} r ON r.member_id = m.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY m.id
      ORDER BY $orderBy
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map((row) {
      final lastShot = row['last_shot_at'] as int?;
      return MemberListItem(
        member: Member.fromMap(row),
        recordCount: (row['record_count'] as int?) ?? 0,
        lastShotAt: lastShot == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastShot),
      );
    }).toList();
  }

  @override
  Future<Member?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      AppDatabase.tableMembers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  @override
  Future<void> insert(Member member) async {
    final db = await _db.database;
    await db.insert(
      AppDatabase.tableMembers,
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _logger.phase('member.insert', LogPhase.success, context: {'id': member.id});
  }

  @override
  Future<void> update(Member member) async {
    final db = await _db.database;
    await db.update(
      AppDatabase.tableMembers,
      member.toMap(),
      where: 'id = ?',
      whereArgs: [member.id],
    );
    _logger.phase('member.update', LogPhase.success, context: {'id': member.id});
  }

  @override
  Future<void> delete(String id) async {
    _logger.phase('member.delete', LogPhase.start, context: {'id': id});
    final db = await _db.database;
    // 외래 키 ON DELETE CASCADE로 photo_records/body_photos 행이 함께 삭제된다.
    // 파일은 DB 밖이므로 회원 저장소 디렉터리를 명시적으로 정리한다.
    await db.delete(
      AppDatabase.tableMembers,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _storage.deleteMemberDir(id);
    _logger.phase('member.delete', LogPhase.success, context: {'id': id});
  }
}
