import 'dart:io';

import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 인메모리 sqflite(FFI) + 임시 저장소로 리포지토리를 테스트하는 패턴.
void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late PhotoStorageService storage;
  late MemberRepository members;
  late BodyPhotoRepository photos;
  late PhotoRecordRepository records;

  setUpAll(() {
    // 호스트에서 sqflite를 실행하기 위한 FFI 백엔드 등록.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    tempRoot = await Directory.systemTemp.createTemp('body_frame_test_');
    storage = PhotoStorageServiceImpl(rootPath: tempRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, photos: photos);
    members = MemberRepositoryImpl(database: db, storage: storage);
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Member sampleMember(String id, String name) {
    final now = DateTime(2026, 1, 1);
    return Member(id: id, name: name, createdAt: now, updatedAt: now);
  }

  test('회원 등록 후 목록/조회가 동작한다', () async {
    await members.insert(sampleMember('m1', '홍길동'));

    final list = await members.list();
    expect(list, hasLength(1));
    expect(list.first.member.name, '홍길동');
    expect(list.first.recordCount, 0);
    expect(list.first.lastShotAt, isNull);

    final fetched = await members.getById('m1');
    expect(fetched?.name, '홍길동');
  });

  test('이름 검색과 이름순 정렬이 동작한다', () async {
    await members.insert(sampleMember('m1', '가나'));
    await members.insert(sampleMember('m2', '다라'));

    final searched = await members.list(query: '다');
    expect(searched, hasLength(1));
    expect(searched.first.member.id, 'm2');

    final sorted = await members.list(sort: MemberSort.name);
    expect(sorted.map((e) => e.member.id), ['m1', 'm2']);
  });

  test('회원 삭제 시 촬영 기록/사진 행과 파일이 연쇄 삭제된다', () async {
    await members.insert(sampleMember('m1', '홍길동'));
    final now = DateTime(2026, 2, 1);
    await records.insert(PhotoRecord(
      id: 'r1',
      memberId: 'm1',
      shotAt: now,
      createdAt: now,
      updatedAt: now,
    ));

    // 저장소에 더미 원본 파일을 만들고 사진 행을 등록한다.
    final saved = await storage.saveBytes(
      memberId: 'm1',
      bytes: List<int>.filled(8, 0),
      fileName: 'front.jpg',
    );
    await photos.insert(BodyPhoto(
      id: 'p1',
      recordId: 'r1',
      filePath: saved,
      direction: BodyDirection.front,
      createdAt: now,
    ));

    expect(await File(saved).exists(), isTrue);
    expect(await records.listByMember('m1'), hasLength(1));

    await members.delete('m1');

    expect(await members.getById('m1'), isNull);
    expect(await records.listByMember('m1'), isEmpty);
    expect(await photos.getById('p1'), isNull);
    expect(await File(saved).exists(), isFalse);
  });

  test('최근 촬영순 정렬은 촬영 기록이 있는 회원을 먼저 둔다', () async {
    await members.insert(sampleMember('m1', '먼저등록'));
    await members.insert(sampleMember('m2', '나중촬영'));
    final now = DateTime(2026, 3, 1);
    await records.insert(PhotoRecord(
      id: 'r1',
      memberId: 'm2',
      shotAt: now,
      createdAt: now,
      updatedAt: now,
    ));

    final list = await members.list(sort: MemberSort.recentShot);
    expect(list.first.member.id, 'm2');
    expect(list.first.recordCount, 1);
    expect(list.first.lastShotAt, now);
  });
}
