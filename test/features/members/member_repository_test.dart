import 'dart:io';
import 'package:bodymark/core/database/app_database.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final at = DateTime(2026, 11, 4, 15);
Member member(String id) =>
    Member(id: id, name: id, createdAt: at, updatedAt: at);
PhotoRecord lesson(String id, {String? memo, String memberId = 'a'}) =>
    PhotoRecord(
      id: id,
      memberId: memberId,
      shotAt: at,
      memo: memo,
      createdAt: at.add(const Duration(hours: 1)),
      updatedAt: at.add(const Duration(hours: 1)),
    );
void main() {
  late Directory root;
  late AppDatabase database;
  late PhotoStorageService storage;
  late MemberRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bodymark_test_');
    database = AppDatabase.forTesting();
    storage = PhotoStorageServiceImpl(rootPath: root.path);
    repo = SqliteMemberRepository(database, storage);
    await repo.save(member('a'));
    await repo.save(member('b'));
  });
  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });
  test('사진 없는 일지는 실제 레슨 시각과 작성 시각을 따로 저장한다', () async {
    await repo.saveLesson(lesson('note', memo: '손목 부하를 줄임'), []);
    final row = (await (await database.database).query('photo_records')).single;
    final record = PhotoRecord.fromMap(row);
    expect(record.shotAt, at);
    expect(record.createdAt, at.add(const Duration(hours: 1)));
    expect(record.memberId, 'a');
    expect(await (await database.database).query('body_photos'), isEmpty);
  });
  test('빈 레슨은 거부하고 사진만 있는 레슨은 저장한다', () async {
    await expectLater(
      repo.saveLesson(lesson('empty'), []),
      throwsArgumentError,
    );
    final path = await storage.saveBytes(
      shotAt: at,
      bytes: [1, 2],
      fileName: 'photo.jpg',
    );
    await repo.saveLesson(lesson('photo'), [
      BodyPhoto(
        id: 'p',
        recordId: 'photo',
        filePath: path,
        direction: BodyDirection.front,
        phase: 'after',
        capturedAt: at.add(const Duration(minutes: 52)),
        createdAt: at,
      ),
    ]);
    final row = (await (await database.database).query('body_photos')).single;
    expect(row['file_path'], startsWith('photos/202611/'));
    expect(
      BodyPhoto.fromMap(row).capturedAt,
      at.add(const Duration(minutes: 52)),
    );
    expect(row['phase'], 'after');
  });
  test('사진 삽입 실패 시 레슨과 사진 전체를 롤백한다', () async {
    final path = await storage.saveBytes(
      shotAt: at,
      bytes: [1],
      fileName: 'photo.jpg',
    );
    final p = BodyPhoto(
      id: 'same',
      recordId: 'r',
      filePath: path,
      direction: BodyDirection.front,
      createdAt: at,
    );
    await expectLater(
      repo.saveLesson(lesson('r'), [p, p]),
      throwsA(isA<DatabaseException>()),
    );
    expect(await (await database.database).query('photo_records'), isEmpty);
    expect(await (await database.database).query('body_photos'), isEmpty);
  });
  test('회원 삭제는 소속 일지·사진 파일만 정리한다', () async {
    final path = await storage.saveBytes(
      shotAt: at,
      bytes: [1],
      fileName: 'a.jpg',
    );
    await repo.saveLesson(lesson('a-photo'), [
      BodyPhoto(
        id: 'p',
        recordId: 'a-photo',
        filePath: path,
        direction: BodyDirection.front,
        createdAt: at,
      ),
    ]);
    await repo.saveLesson(lesson('b-note', memberId: 'b', memo: '유지'), []);
    await repo.delete('a');
    expect(await File(path).exists(), isFalse);
    expect((await repo.list()).single.id, 'b');
    expect(
      (await (await database.database).query('photo_records')).single['id'],
      'b-note',
    );
  });
  test('다른 회원의 레슨 덮어쓰기를 거부한다', () async {
    await repo.saveLesson(lesson('r', memo: '원본'), []);
    await expectLater(
      repo.saveLesson(lesson('r', memberId: 'b', memo: '변조'), []),
      throwsStateError,
    );
    expect(
      (await (await database.database).query('photo_records')).single['memo'],
      '원본',
    );
  });
  test('미연결 기록만 명시적으로 회원에게 연결할 수 있다', () async {
    final db = await database.database;
    final r = PhotoRecord(
      id: 'old',
      shotAt: at,
      memo: '기존',
      createdAt: at,
      updatedAt: at,
    );
    await db.insert('photo_records', r.toMap());
    final actual = DateTime(2026, 10, 28, 15);
    await repo.linkRecord('old', 'a', actual);
    final linked = PhotoRecord.fromMap(
      (await db.query('photo_records')).single,
    );
    expect(linked.memberId, 'a');
    expect(linked.shotAt, actual);
    expect(linked.memo, '기존');
    await expectLater(repo.linkRecord('old', 'b', actual), throwsStateError);
  });
}
