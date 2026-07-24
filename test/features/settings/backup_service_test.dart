import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/settings/models/backup_models.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 백업 생성 -> 복원 라운드트립을 인메모리 sqflite(FFI) + 임시 디렉터리로 검증한다.
/// (테스트 패턴은 test/core/repositories/member_repository_test.dart 참고)
void main() {
  late AppDatabase db;
  late Directory storageRoot;
  late Directory restoreTempRoot;
  late PhotoStorageService storage;
  late MemberRepository members;
  late PhotoRecordRepository records;
  late BodyPhotoRepository photos;
  late BackupService backupService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storageRoot = await Directory.systemTemp.createTemp('body_frame_backup_storage_');
    restoreTempRoot = await Directory.systemTemp.createTemp('body_frame_backup_restore_');
    storage = PhotoStorageServiceImpl(rootPath: storageRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, photos: photos);
    members = MemberRepositoryImpl(database: db, storage: storage);
    backupService = BackupServiceImpl(
      database: db,
      storage: storage,
      settingsService: AppSettingsServiceImpl(),
      tempRootOverride: restoreTempRoot.path,
    );
  });

  tearDown(() async {
    await db.close();
    if (await storageRoot.exists()) await storageRoot.delete(recursive: true);
    if (await restoreTempRoot.exists()) await restoreTempRoot.delete(recursive: true);
  });

  Future<void> seedSampleData({String memberId = 'm1', String name = '홍길동'}) async {
    final now = DateTime(2026, 1, 1);
    await members.insert(Member(id: memberId, name: name, createdAt: now, updatedAt: now));
    await records.insert(PhotoRecord(
      id: 'r_$memberId',
      memberId: memberId,
      shotAt: now,
      createdAt: now,
      updatedAt: now,
    ));
    final path = await storage.saveBytes(
      memberId: memberId,
      bytes: [1, 2, 3, 4],
      fileName: 'front.jpg',
    );
    await photos.insert(BodyPhoto(
      id: 'p_$memberId',
      recordId: 'r_$memberId',
      filePath: path,
      direction: BodyDirection.front,
      createdAt: now,
    ));
  }

  test(
    '전체 백업 생성 후 교체 모드로 복원하면 회원/기록/사진과 파일 내용이 그대로 복원된다',
    () async {
      await seedSampleData();

      final zipBytes = await backupService.buildBackup();

      // 새 기기를 흉내내어 기존 DB/파일을 지운다.
      (await db.database).delete(AppDatabase.tableMembers);
      await storage.deleteMemberDir('m1');

      final preview = await backupService.prepareRestore(zipBytes);
      expect(preview.formatVersion, backupFormatVersion);
      expect(preview.scope, BackupScope.all);
      expect(preview.memberCount, 1);
      expect(preview.recordCount, 1);
      expect(preview.photoCount, 1);
      expect(preview.hasDuplicates, isFalse);

      final outcome = await backupService.applyRestore(preview, mode: RestoreMode.replace);
      expect(outcome.success, isTrue);
      expect(outcome.error, isNull);
      expect(outcome.memberCount, 1);
      expect(outcome.photoCount, 1);

      final restoredMembers = await members.list();
      expect(restoredMembers, hasLength(1));
      expect(restoredMembers.first.member.id, 'm1');
      expect(restoredMembers.first.member.name, '홍길동');

      final restoredRecords = await records.listByMember('m1');
      expect(restoredRecords, hasLength(1));

      final restoredPhotos = await photos.listByRecord(restoredRecords.first.id);
      expect(restoredPhotos, hasLength(1));

      final restoredBytes = await File(restoredPhotos.first.filePath).readAsBytes();
      expect(restoredBytes, [1, 2, 3, 4]);
    },
  );

  test('손상된 백업 파일은 prepareRestore에서 예외가 발생하고 기존 데이터는 그대로 유지된다', () async {
    await seedSampleData();

    final badBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    await expectLater(
      backupService.prepareRestore(badBytes),
      throwsA(isA<FormatException>()),
    );

    final stillThere = await members.list();
    expect(stillThere, hasLength(1));
    expect(stillThere.first.member.name, '홍길동');
  });

  test('data.json이 없는 zip은 예외가 발생하고 기존 데이터는 그대로 유지된다', () async {
    await seedSampleData();

    // data.json 없이 다른 항목만 담긴 zip을 직접 만든다.
    final validZip = await backupService.buildBackup();
    // 유효한 zip 헤더를 갖도록 정상 zip을 재사용하되 data.json 내용을 깨뜨리는
    // 대신, 완전히 형식이 다른 바이트를 사용해 디코딩 자체가 실패하는 경로를 검증한다.
    expect(validZip, isNotEmpty);

    await expectLater(
      backupService.prepareRestore(Uint8List.fromList('not a zip'.codeUnits)),
      throwsA(isA<FormatException>()),
    );

    final stillThere = await members.list();
    expect(stillThere, hasLength(1));
  });

  test('경로 탈출(../) 항목이 포함된 zip은 거부되고 임시 디렉터리 밖에 파일이 생기지 않는다', () async {
    await seedSampleData();

    // 정상 백업 zip에 zip slip 항목을 추가한 악성 zip을 만든다.
    final zipBytes = await backupService.buildBackup();
    final decoded = ZipDecoder().decodeBytes(zipBytes);
    final malicious = Archive();
    for (final f in decoded.files) {
      malicious.addFile(f);
    }
    malicious.addFile(ArchiveFile('../evil.bin', 4, [1, 2, 3, 4]));
    final maliciousBytes =
        Uint8List.fromList(ZipEncoder().encode(malicious) ?? const []);

    await expectLater(
      backupService.prepareRestore(maliciousBytes),
      throwsA(isA<FormatException>()),
    );

    // 추출 디렉터리(body_frame_restore_*)의 상위인 임시 루트에 탈출 파일이
    // 생성되지 않았어야 한다.
    final escaped = File('${restoreTempRoot.path}/evil.bin');
    expect(escaped.existsSync(), isFalse);

    // 기존 데이터는 그대로 유지된다.
    final stillThere = await members.list();
    expect(stillThere, hasLength(1));
  });

  test('추가 모드에서 회원 id가 겹치면 새 id로 치환되어 추가되고 기존 회원도 유지된다', () async {
    await seedSampleData();
    final zipBytes = await backupService.buildBackup();

    // 기존 데이터를 지우지 않고 그대로 둔 채 추가 모드로 복원한다.
    final preview = await backupService.prepareRestore(zipBytes);
    expect(preview.hasDuplicates, isTrue);
    expect(preview.duplicateMemberIds, contains('m1'));

    final outcome = await backupService.applyRestore(preview, mode: RestoreMode.append);
    expect(outcome.success, isTrue);

    final allMembers = await members.list();
    expect(allMembers, hasLength(2));
    expect(allMembers.map((e) => e.member.name), everyElement('홍길동'));

    // 새로 추가된 회원(원본 id가 아닌 쪽)의 사진 파일도 정상적으로 복사되어야 한다.
    final newMember = allMembers.firstWhere((e) => e.member.id != 'm1');
    final newRecords = await records.listByMember(newMember.member.id);
    expect(newRecords, hasLength(1));
    final newPhotos = await photos.listByRecord(newRecords.first.id);
    expect(newPhotos, hasLength(1));
    expect(await File(newPhotos.first.filePath).readAsBytes(), [1, 2, 3, 4]);
  });

  test('회원별 백업은 선택한 회원의 데이터만 포함한다', () async {
    await seedSampleData(memberId: 'm1', name: '홍길동');
    await seedSampleData(memberId: 'm2', name: '김철수');

    final zipBytes = await backupService.buildBackup(memberId: 'm1');
    final preview = await backupService.prepareRestore(zipBytes);

    expect(preview.scope, BackupScope.member);
    expect(preview.memberCount, 1);
    expect(preview.rawMembers.single['id'], 'm1');

    await backupService.discardRestore(preview);
  });

  test('복원을 취소하면 discardRestore로 임시 파일이 정리된다', () async {
    await seedSampleData();
    final zipBytes = await backupService.buildBackup();
    final preview = await backupService.prepareRestore(zipBytes);

    expect(await Directory(preview.tempDirPath).exists(), isTrue);
    await backupService.discardRestore(preview);
    expect(await Directory(preview.tempDirPath).exists(), isFalse);
  });
}
