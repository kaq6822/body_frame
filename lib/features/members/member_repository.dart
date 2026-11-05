import '../../core/services/app_logger.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/database/app_database.dart';
import '../../core/models/models.dart';
import '../../core/services/photo_storage_service.dart';
import 'member.dart';

abstract class MemberRepository {
  Future<List<Member>> list();
  Future<void> save(Member member);
  Future<void> delete(String id);
  Future<void> saveLesson(PhotoRecord record, List<BodyPhoto> addedPhotos);
  Future<void> linkRecord(String recordId, String memberId, DateTime lessonAt);
}

class SqliteMemberRepository implements MemberRepository {
  final AppDatabase database;
  final PhotoStorageService storage;
  SqliteMemberRepository(this.database, this.storage);

  @override
  Future<List<Member>> list() async => (await (await database.database).query(
    'members',
    orderBy: 'updated_at DESC, name ASC',
  )).map(Member.fromMap).toList();

  @override
  Future<void> save(Member member) async {
    if (member.name.trim().isEmpty) throw ArgumentError('회원 이름이 필요합니다.');
    final db = await database.database;
    await db.transaction((tx) async {
      final found = await tx.query(
        'members',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [member.id],
      );
      if (found.isEmpty) {
        await tx.insert('members', member.toMap());
      } else {
        await tx.update(
          'members',
          member.toMap(),
          where: 'id = ?',
          whereArgs: [member.id],
        );
      }
    });
  }

  @override
  Future<void> saveLesson(
    PhotoRecord record,
    List<BodyPhoto> addedPhotos,
  ) async {
    if (record.memberId == null) throw ArgumentError('회원이 필요합니다.');
    final maps = <Map<String, Object?>>[];
    for (final p in addedPhotos) {
      if (p.recordId != record.id) throw ArgumentError('사진 소속이 다릅니다.');
      final path = await storage.toStoredPath(p.filePath);
      if (!RegExp(r'^photos/\d{6}/[^/]+$').hasMatch(path)) {
        throw ArgumentError('앱 사진 저장소 경로가 아닙니다.');
      }
      maps.add({...p.toMap(), 'file_path': path});
    }
    final db = await database.database;
    await db.transaction((tx) async {
      final member = await tx.query(
        'members',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [record.memberId],
      );
      if (member.isEmpty) throw StateError('회원을 찾을 수 없습니다.');
      final current = await tx.query(
        'photo_records',
        where: 'id = ?',
        whereArgs: [record.id],
      );
      if (current.isNotEmpty && current.first['member_id'] != record.memberId) {
        throw StateError('다른 회원의 레슨은 수정할 수 없습니다.');
      }
      final existing =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              'SELECT COUNT(*) FROM body_photos WHERE record_id = ?',
              [record.id],
            ),
          ) ??
          0;
      if ((record.memo ?? '').trim().isEmpty &&
          (record.condition ?? '').trim().isEmpty &&
          existing == 0 &&
          maps.isEmpty) {
        throw ArgumentError('일지 또는 사진을 추가해주세요.');
      }
      if (current.isEmpty) {
        await tx.insert('photo_records', record.toMap());
      } else {
        await tx.update(
          'photo_records',
          record.toMap(),
          where: 'id = ?',
          whereArgs: [record.id],
        );
      }
      for (final photo in maps) {
        await tx.insert('body_photos', photo);
      }
    });
  }

  @override
  Future<void> linkRecord(
    String recordId,
    String memberId,
    DateTime lessonAt,
  ) async {
    final db = await database.database;
    final count = await db.update(
      'photo_records',
      {'member_id': memberId, 'shot_at': lessonAt.millisecondsSinceEpoch},
      where: 'id = ? AND member_id IS NULL',
      whereArgs: [recordId],
    );
    if (count != 1) throw StateError('이미 연결되었거나 없는 기록입니다.');
  }

  @override
  Future<void> delete(String id) async {
    final db = await database.database;
    final paths = await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        'SELECT p.file_path FROM body_photos p JOIN photo_records r ON r.id = p.record_id WHERE r.member_id = ?',
        [id],
      );
      await tx.delete('photo_records', where: 'member_id = ?', whereArgs: [id]);
      await tx.delete('members', where: 'id = ?', whereArgs: [id]);
      return rows.map((r) => r['file_path'] as String).toList();
    });
    // Same deletion contract as record repository: no broken live DB references.
    for (final path in paths) {
      try {
        await storage.deleteFile(path);
      } catch (_) {
        AppLogger.instance.warn('member.photo.cleanup.failure');
      }
    }
  }
}
