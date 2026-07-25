import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:body_frame/core/database/app_database.dart';
import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/repositories/body_photo_repository.dart';
import 'package:body_frame/core/repositories/member_repository.dart';
import 'package:body_frame/core/repositories/photo_record_repository.dart';
import 'package:body_frame/core/services/grid_settings_service.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/features/settings/models/backup_models.dart';
import 'package:body_frame/features/settings/services/app_settings_service.dart';
import 'package:body_frame/features/settings/services/backup_archive_cipher.dart';
import 'package:body_frame/features/settings/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _memberA = '11111111-1111-4111-8111-111111111111';
const _recordA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _photoA = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _memberB = '22222222-2222-4222-8222-222222222222';
const _recordB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _photoB = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _unknownId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _studioAssetOwner = 'studio-assets';
const _backupPassword = 'correct horse battery staple';

void main() {
  late AppDatabase db;
  late Directory storageRoot;
  late Directory restoreTempRoot;
  late PhotoStorageService storage;
  late MemberRepository members;
  late PhotoRecordRepository records;
  late BodyPhotoRepository photos;
  late AppSettingsService settingsService;
  late GridSettingsService gridSettingsService;
  late BackupArchiveCipher archiveCipher;
  late BackupServiceImpl backupService;

  BackupServiceImpl makeService({
    BackupArchiveLimits limits = const BackupArchiveLimits(),
    RestoreFileCopier? restoreFileCopier,
    RestoreInterruptionHook? restoreInterruptionHook,
    PhotoStorageService? storageOverride,
    AppSettingsService? settingsServiceOverride,
    GridSettingsService? gridSettingsServiceOverride,
  }) {
    return BackupServiceImpl(
      database: db,
      storage: storageOverride ?? storage,
      settingsService: settingsServiceOverride ?? settingsService,
      gridSettingsService: gridSettingsServiceOverride ?? gridSettingsService,
      limits: limits,
      restoreFileCopier: restoreFileCopier,
      restoreInterruptionHook: restoreInterruptionHook,
      archiveCipher: archiveCipher,
      tempRootOverride: restoreTempRoot.path,
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storageRoot = await Directory.systemTemp.createTemp(
      'body_frame_backup_storage_',
    );
    restoreTempRoot = await Directory.systemTemp.createTemp(
      'body_frame_backup_restore_',
    );
    storage = PhotoStorageServiceImpl(rootPath: storageRoot.path);
    photos = BodyPhotoRepositoryImpl(database: db, storage: storage);
    records = PhotoRecordRepositoryImpl(database: db, storage: storage);
    members = MemberRepositoryImpl(database: db, storage: storage);
    settingsService = AppSettingsServiceImpl();
    gridSettingsService = GridSettingsServiceImpl();
    archiveCipher = BackupArchiveCipherImpl(
      kdfPolicy: const BackupKdfPolicy(
        memoryKiB: 32,
        iterations: 1,
        minimumAcceptedMemoryKiB: 8,
        maximumAcceptedMemoryKiB: 1024,
        minimumAcceptedIterations: 1,
        maximumAcceptedIterations: 2,
      ),
      runInBackground: false,
    );
    backupService = makeService();
  });

  tearDown(() async {
    await db.close();
    if (await storageRoot.exists()) {
      await storageRoot.delete(recursive: true);
    }
    if (await restoreTempRoot.exists()) {
      await restoreTempRoot.delete(recursive: true);
    }
  });

  Future<BodyPhoto> seedSampleData({
    String memberId = _memberA,
    String recordId = _recordA,
    String photoId = _photoA,
    String name = '홍길동',
    List<int> bytes = const [1, 2, 3, 4],
    bool withAvatar = false,
  }) async {
    final now = DateTime(2026, 1, 1);
    final avatarPath = withAvatar
        ? await storage.saveBytes(
            memberId: memberId,
            bytes: const [8, 7, 6],
            fileName: 'avatar.jpg',
          )
        : null;
    await members.insert(
      Member(
        id: memberId,
        name: name,
        avatarPath: avatarPath,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await records.insert(
      PhotoRecord(
        id: recordId,
        memberId: memberId,
        shotAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final path = await storage.saveBytes(
      memberId: memberId,
      bytes: bytes,
      fileName: 'front.jpg',
    );
    final photo = BodyPhoto(
      id: photoId,
      recordId: recordId,
      filePath: path,
      direction: BodyDirection.front,
      width: 1200,
      height: 1600,
      orientation: 1,
      createdAt: now,
    );
    await photos.insert(photo);
    return photo;
  }

  Future<Uint8List> buildEncryptedBackup({String? memberId}) {
    return backupService.buildBackup(
      memberId: memberId,
      password: _backupPassword,
    );
  }

  Future<Uint8List> buildPlaintextBackup({String? memberId}) async {
    return archiveCipher.decrypt(
      await buildEncryptedBackup(memberId: memberId),
      password: _backupPassword,
    );
  }

  Future<_ReplaceCrashScenario> prepareReplaceCrashScenario() async {
    const backupGrid = GridSettings(opacity: 0.2, spacing: 84);
    final backupLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [4, 4, 4],
      fileName: 'backup-logo.png',
    );
    final backupLogoStored = await storage.toStoredPath(backupLogoAbsolute);
    await settingsService.save(
      AppSettings(
        lockMode: LockMode.password,
        studioName: '복원 설정',
        studioLogoPath: backupLogoStored,
        dataNoticeAcknowledged: true,
      ),
    );
    await gridSettingsService.save(backupGrid);
    await seedSampleData();
    final backupBytes = await buildEncryptedBackup();
    await members.delete(_memberA);
    await storage.deleteFile(backupLogoStored);

    const currentGrid = GridSettings(opacity: 0.8, spacing: 26);
    final currentLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [9, 9, 9],
      fileName: 'current-logo.png',
    );
    final currentLogoStored = await storage.toStoredPath(currentLogoAbsolute);
    final currentSettings = AppSettings(
      lockMode: LockMode.pin,
      biometricEnabled: true,
      autoLockSeconds: 60,
      studioName: '기존 설정',
      studioLogoPath: currentLogoStored,
    );
    await settingsService.save(currentSettings);
    await gridSettingsService.save(currentGrid);
    final currentPhoto = await seedSampleData(
      memberId: _memberB,
      recordId: _recordB,
      photoId: _photoB,
      name: '기존 회원',
      bytes: const [8, 8, 8],
    );
    final preview = await backupService.prepareRestore(
      backupBytes,
      password: _backupPassword,
    );
    return _ReplaceCrashScenario(
      preview: preview,
      backupGrid: backupGrid,
      currentGrid: currentGrid,
      currentSettings: currentSettings,
      currentLogoAbsolute: currentLogoAbsolute,
      currentPhotoAbsolute: currentPhoto.filePath,
    );
  }

  PhotoStorageService createRestartedStorage() {
    return PhotoStorageServiceImpl(
      rootPath: storageRoot.path,
      quarantineReferencesLoader: () async {
        final currentSettings = await settingsService.load();
        final database = await db.database;
        return database.transaction((txn) async {
          final memberRows = await txn.query(
            AppDatabase.tableMembers,
            columns: ['id', 'avatar_path'],
          );
          final photoRows = await txn.query(
            AppDatabase.tableBodyPhotos,
            columns: ['file_path'],
          );
          return StorageQuarantineReferences(
            memberIds: memberRows.map((row) => row['id'] as String),
            storedFilePaths: [
              ...memberRows
                  .map((row) => row['avatar_path'] as String?)
                  .whereType<String>()
                  .where((path) => path.isNotEmpty),
              ...photoRows.map((row) => row['file_path'] as String),
              if (currentSettings.studioLogoPath != null &&
                  currentSettings.studioLogoPath!.isNotEmpty)
                currentSettings.studioLogoPath!,
            ],
          );
        });
      },
    );
  }

  test('복원 입력의 legacy ZIP과 암호화 컨테이너 사전 상한을 정책에서 노출한다', () {
    const limits = BackupArchiveLimits(maxCompressedBytes: 1234);
    final service = makeService(limits: limits);

    expect(
      service.restoreInputLimits.maximumLegacyZipBytes,
      limits.maxCompressedBytes,
    );
    expect(
      service.restoreInputLimits.maximumEncryptedContainerBytes,
      archiveCipher.maximumContainerBytesForPlaintextLimit(
        limits.maxCompressedBytes,
      ),
    );
  });

  test('전체 백업은 데이터와 실제 격자를 복원하고 현재 기기의 잠금 상태는 보존한다', () async {
    const backupGrid = GridSettings(
      visible: false,
      opacity: 0.25,
      lineWidth: 2,
      spacing: 72,
      colorValue: 0xFF123456,
    );
    final backupLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [4, 3, 2, 1],
      fileName: 'backup-logo.png',
    );
    final backupLogoStored = await storage.toStoredPath(backupLogoAbsolute);
    final backupSettings = AppSettings(
      lockMode: LockMode.password,
      biometricEnabled: true,
      autoLockSeconds: 300,
      defaultExportOptions: ExportImageOptions(
        includeMemberName: true,
        includeMemo: true,
        includeGrid: true,
      ),
      studioName: '백업 스튜디오',
      studioLogoPath: backupLogoStored,
      dataNoticeAcknowledged: true,
    );
    await settingsService.save(backupSettings);
    await gridSettingsService.save(backupGrid);
    await seedSampleData(withAvatar: true);

    final zipBytes = await buildEncryptedBackup();
    await members.delete(_memberA);
    await storage.deleteFile(backupLogoStored);

    const currentGrid = GridSettings(opacity: 0.9, spacing: 24);
    final currentLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [9, 9],
      fileName: 'current-logo.png',
    );
    final currentLogoStored = await storage.toStoredPath(currentLogoAbsolute);
    final currentDeviceSettings = AppSettings(
      lockMode: LockMode.pin,
      biometricEnabled: true,
      autoLockSeconds: 30,
      studioName: '현재 기기 값',
      studioLogoPath: currentLogoStored,
    );
    await settingsService.save(currentDeviceSettings);
    await gridSettingsService.save(currentGrid);

    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );
    expect(preview.formatVersion, backupFormatVersion);
    expect(preview.scope, BackupScope.all);
    expect(preview.memberCount, 1);
    expect(preview.recordCount, 1);
    expect(preview.photoCount, 1);
    expect(preview.hasDuplicates, isFalse);
    expect(preview.rawSettings!['lockMode'], LockMode.none.key);
    expect(preview.rawSettings!['biometricEnabled'], isFalse);
    expect(
      preview.rawSettings!['studioLogoPath'],
      'assets/studio/backup-logo.png',
    );

    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );
    expect(outcome.success, isTrue);
    expect(outcome.error, isNull);

    final restoredMember = await members.getById(_memberA);
    expect(restoredMember, isNotNull);
    expect(restoredMember!.name, '홍길동');
    expect(await File(restoredMember.avatarPath!).readAsBytes(), [8, 7, 6]);

    final restoredRecords = await records.listByMember(_memberA);
    expect(restoredRecords, hasLength(1));
    final restoredPhotos = await photos.listByRecord(restoredRecords.single.id);
    expect(restoredPhotos, hasLength(1));
    expect(await File(restoredPhotos.single.filePath).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);

    final rawPhotoRows = await (await db.database).query(
      AppDatabase.tableBodyPhotos,
    );
    expect(rawPhotoRows.single['file_path'], startsWith('photos/'));

    final restoredSettings = await settingsService.load();
    expect(restoredSettings.lockMode, LockMode.pin);
    expect(restoredSettings.biometricEnabled, isTrue);
    expect(restoredSettings.autoLockSeconds, 30);
    expect(
      restoredSettings.studioLogoPath,
      startsWith('photos/studio-assets/'),
    );
    expect(restoredSettings.studioLogoPath, isNot(currentLogoStored));
    expect(
      await File(
        await storage.resolvePath(restoredSettings.studioLogoPath!),
      ).readAsBytes(),
      [4, 3, 2, 1],
    );
    expect(await File(currentLogoAbsolute).exists(), isFalse);
    expect(restoredSettings.studioName, '백업 스튜디오');
    expect(restoredSettings.defaultExportOptions.includeMemberName, isTrue);
    expect(restoredSettings.defaultExportOptions.includeMemo, isTrue);
    expect(restoredSettings.defaultGrid, backupGrid);
    expect(restoredSettings.dataNoticeAcknowledged, isTrue);
    expect(await gridSettingsService.load(), backupGrid);
  });

  test('손상되거나 data.json이 없는 ZIP은 거부하고 기존 데이터를 유지한다', () async {
    await seedSampleData();

    await expectLater(
      backupService.prepareRestore(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<FormatException>()),
    );

    final validZip = await buildPlaintextBackup();
    final missingData = _rewriteZip(validZip, removeNames: const {'data.json'});
    await expectLater(
      backupService.prepareRestore(missingData),
      throwsA(isA<FormatException>()),
    );

    expect(await members.getById(_memberA), isNotNull);
  });

  test('암호화 백업은 비밀번호 누락, 오류, 파일 변조 시 ZIP 검증 전에 거부한다', () async {
    await seedSampleData();
    final encrypted = await buildEncryptedBackup();
    expect(backupService.isEncryptedBackup(encrypted), isTrue);

    await expectLater(
      backupService.prepareRestore(encrypted),
      throwsA(isA<BackupPasswordRequiredException>()),
    );
    await expectLater(
      backupService.prepareRestore(
        encrypted,
        password: 'this password is definitely wrong',
      ),
      throwsA(isA<BackupAuthenticationException>()),
    );

    final tampered = Uint8List.fromList(encrypted);
    tampered[tampered.length - 1] ^= 0x01;
    await expectLater(
      backupService.prepareRestore(tampered, password: _backupPassword),
      throwsA(isA<BackupAuthenticationException>()),
    );
    expect(await members.getById(_memberA), isNotNull);
  });

  test('비어 있거나 짧은 비밀번호로는 백업 생성을 시작하지 않는다', () async {
    await expectLater(
      backupService.buildBackup(password: ''),
      throwsA(isA<WeakBackupPasswordException>()),
    );
    await expectLater(
      backupService.buildBackup(password: 'too-short'),
      throwsA(isA<WeakBackupPasswordException>()),
    );
  });

  test('기존 평문 ZIP 백업은 비밀번호 없이 하위 호환 복원한다', () async {
    await seedSampleData();
    final legacyPlaintext = await buildPlaintextBackup();
    expect(backupService.isEncryptedBackup(legacyPlaintext), isFalse);
    await members.delete(_memberA);

    final preview = await backupService.prepareRestore(legacyPlaintext);
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );
    expect(outcome.success, isTrue);
    expect(await members.getById(_memberA), isNotNull);
  });

  test('경로 탈출 및 대소문자 중복 ZIP 항목을 추출 전에 거부한다', () async {
    await seedSampleData();
    final zipBytes = await buildPlaintextBackup();

    final escapedZip = _rewriteZip(
      zipBytes,
      extraFiles: [
        ArchiveFile('../evil.bin', 4, [1, 2, 3, 4]),
      ],
    );
    await expectLater(
      backupService.prepareRestore(escapedZip),
      throwsA(isA<FormatException>()),
    );
    expect(File('${restoreTempRoot.path}/evil.bin').existsSync(), isFalse);

    final duplicateData = _rewriteZip(
      zipBytes,
      extraFiles: [
        ArchiveFile('DATA.JSON', 2, [1, 2]),
      ],
    );
    await expectLater(
      backupService.prepareRestore(duplicateData),
      throwsA(isA<FormatException>()),
    );
    expect(await members.getById(_memberA), isNotNull);
  });

  test('신뢰되지 않은 JSON의 UUID, 중복, FK, 사진 소유 경로를 엄격히 검증한다', () async {
    await seedSampleData();
    final zipBytes = await buildPlaintextBackup();

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'invalid member UUID': (data) {
        _firstMap(data, 'members')['id'] = '..';
      },
      'duplicate member ID': (data) {
        final list = data['members'] as List<dynamic>;
        list.add(Map<String, dynamic>.from(list.single as Map));
      },
      'duplicate record ID': (data) {
        final list = data['photoRecords'] as List<dynamic>;
        list.add(Map<String, dynamic>.from(list.single as Map));
      },
      'duplicate photo ID': (data) {
        final list = data['bodyPhotos'] as List<dynamic>;
        list.add(Map<String, dynamic>.from(list.single as Map));
      },
      'record FK outside graph': (data) {
        _firstMap(data, 'photoRecords')['member_id'] = _unknownId;
      },
      'photo path traversal': (data) {
        _firstMap(data, 'bodyPhotos')['file_path'] =
            'photos/$_memberA/../evil.jpg';
      },
      'photo path owner mismatch': (data) {
        _firstMap(data, 'bodyPhotos')['file_path'] =
            'photos/$_memberB/front.jpg';
      },
      'studio logo path traversal': (data) {
        (data['settings'] as Map<String, dynamic>)['studioLogoPath'] =
            'assets/studio/../evil.png';
      },
    };

    for (final mutation in mutations.entries) {
      final malicious = _rewriteZip(zipBytes, mutateData: mutation.value);
      await expectLater(
        backupService.prepareRestore(malicious),
        throwsA(isA<FormatException>()),
        reason: mutation.key,
      );
    }
    expect(await members.getById(_memberA), isNotNull);
  });

  test('ZIP 항목 수, 개별 파일, 전체 해제 크기 상한을 각각 적용한다', () async {
    await seedSampleData();
    final zipBytes = await buildEncryptedBackup();

    final limitedServices = [
      makeService(limits: const BackupArchiveLimits(maxEntryCount: 1)),
      makeService(limits: const BackupArchiveLimits(maxSingleFileBytes: 3)),
      makeService(
        limits: const BackupArchiveLimits(maxTotalUncompressedBytes: 32),
      ),
    ];
    for (final service in limitedServices) {
      await expectLater(
        service.prepareRestore(zipBytes, password: _backupPassword),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('원본 사진이나 대표 사진이 누락되면 불완전한 백업을 만들지 않는다', () async {
    final photo = await seedSampleData(withAvatar: true);
    await File(photo.filePath).delete();

    await expectLater(buildEncryptedBackup(), throwsA(isA<StateError>()));
  });

  test('추가 모드에서 회원, 기록, 사진 ID 충돌을 모두 독립적으로 remap한다', () async {
    await seedSampleData();
    final zipBytes = await buildEncryptedBackup();

    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );
    expect(preview.duplicateMemberIds, contains(_memberA));
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.append,
    );
    expect(outcome.success, isTrue);

    final allMembers = await members.list();
    expect(allMembers, hasLength(2));
    final restored = allMembers.singleWhere(
      (item) => item.member.id != _memberA,
    );
    final restoredRecords = await records.listByMember(restored.member.id);
    expect(restoredRecords.single.id, isNot(_recordA));
    final restoredPhotos = await photos.listByRecord(restoredRecords.single.id);
    expect(restoredPhotos.single.id, isNot(_photoA));
    expect(await File(restoredPhotos.single.filePath).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);

    expect((await records.getById(_recordA))!.memberId, _memberA);
    expect(
      await File((await photos.getById(_photoA))!.filePath).readAsBytes(),
      [1, 2, 3, 4],
    );
  });

  test('전체 백업 추가 모드는 현재 기기의 설정, 격자와 로고를 그대로 유지한다', () async {
    const backupGrid = GridSettings(opacity: 0.2, spacing: 80);
    final backupLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [1, 2, 3],
      fileName: 'backup-logo.png',
    );
    await settingsService.save(
      AppSettings(
        studioName: '백업 설정',
        studioLogoPath: await storage.toStoredPath(backupLogoAbsolute),
      ),
    );
    await gridSettingsService.save(backupGrid);
    await seedSampleData();
    final backupBytes = await buildEncryptedBackup();

    const currentGrid = GridSettings(opacity: 0.85, spacing: 28);
    final currentLogoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [9, 8, 7, 6],
      fileName: 'current-logo.png',
    );
    final currentLogoStored = await storage.toStoredPath(currentLogoAbsolute);
    final currentSettings = AppSettings(
      lockMode: LockMode.pin,
      biometricEnabled: true,
      autoLockSeconds: 60,
      studioName: '현재 기기 설정',
      studioLogoPath: currentLogoStored,
      dataNoticeAcknowledged: true,
    );
    await settingsService.save(currentSettings);
    await gridSettingsService.save(currentGrid);

    final preview = await backupService.prepareRestore(
      backupBytes,
      password: _backupPassword,
    );
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.append,
    );

    expect(outcome.success, isTrue);
    expect((await settingsService.load()).toMap(), currentSettings.toMap());
    expect(await gridSettingsService.load(), currentGrid);
    expect(await File(currentLogoAbsolute).readAsBytes(), const [9, 8, 7, 6]);
    expect((await members.list()), hasLength(2));
  });

  test('스튜디오 로고 원본이 누락되면 전체 백업을 만들지 않는다', () async {
    final logoAbsolute = await storage.saveBytes(
      memberId: _studioAssetOwner,
      bytes: const [1, 3, 5, 7],
      fileName: 'logo.png',
    );
    await settingsService.save(
      AppSettings(studioLogoPath: await storage.toStoredPath(logoAbsolute)),
    );
    await File(logoAbsolute).delete();

    await expectLater(buildEncryptedBackup(), throwsA(isA<StateError>()));
  });

  test('회원 ID가 겹치지 않아도 기록과 사진 ID 충돌은 기존 행을 덮어쓰지 않는다', () async {
    await seedSampleData();
    final zipBytes = await buildEncryptedBackup(memberId: _memberA);
    await members.delete(_memberA);

    await seedSampleData(
      memberId: _memberB,
      recordId: _recordA,
      photoId: _photoA,
      name: '기존 회원',
      bytes: const [9, 9, 9],
    );

    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );
    expect(preview.hasDuplicates, isFalse);
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.append,
    );
    expect(outcome.success, isTrue);

    expect((await records.getById(_recordA))!.memberId, _memberB);
    expect(
      await File((await photos.getById(_photoA))!.filePath).readAsBytes(),
      [9, 9, 9],
    );

    final importedRecords = await records.listByMember(_memberA);
    expect(importedRecords.single.id, isNot(_recordA));
    final importedPhotos = await photos.listByRecord(importedRecords.single.id);
    expect(importedPhotos.single.id, isNot(_photoA));
    expect(await File(importedPhotos.single.filePath).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);
  });

  test('파일 staging 실패 시 기존 DB, 파일, 설정을 그대로 보존한다', () async {
    await seedSampleData();
    final zipBytes = await buildEncryptedBackup();
    await members.delete(_memberA);
    await seedSampleData(
      memberId: _memberB,
      recordId: _recordB,
      photoId: _photoB,
      name: '기존 회원',
      bytes: const [9, 8, 7],
    );
    const currentSettings = AppSettings(
      lockMode: LockMode.pin,
      studioName: '현재 설정',
    );
    await settingsService.save(currentSettings);

    final existingPhoto = await photos.getById(_photoB);
    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );
    final failingService = makeService(
      restoreFileCopier: (sourcePath, destinationPath) async {
        await File(sourcePath).copy('$destinationPath.partial');
        throw const FileSystemException('injected copy failure');
      },
    );
    final outcome = await failingService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );

    expect(outcome.success, isFalse);
    expect(await members.getById(_memberA), isNull);
    expect((await members.getById(_memberB))!.name, '기존 회원');
    expect(await File(existingPhoto!.filePath).readAsBytes(), [9, 8, 7]);
    expect((await settingsService.load()).toMap(), currentSettings.toMap());
    expect(await _allFiles(storageRoot), [existingPhoto.filePath]);
  });

  test('DB 반영 실패 시 transaction, 설정, staging 파일을 모두 rollback한다', () async {
    const backupGrid = GridSettings(opacity: 0.2, spacing: 88);
    const backupSettings = AppSettings(
      studioName: '복원될 설정',
      dataNoticeAcknowledged: true,
    );
    await settingsService.save(backupSettings);
    await gridSettingsService.save(backupGrid);
    await seedSampleData();
    final zipBytes = await buildEncryptedBackup();
    await members.delete(_memberA);

    await seedSampleData(
      memberId: _memberB,
      recordId: _recordB,
      photoId: _photoB,
      name: '기존 회원',
      bytes: const [5, 5, 5],
    );
    const currentGrid = GridSettings(opacity: 0.8, spacing: 22);
    const currentSettings = AppSettings(
      lockMode: LockMode.pin,
      biometricEnabled: true,
      autoLockSeconds: 60,
      studioName: '현재 설정',
    );
    await settingsService.save(currentSettings);
    await gridSettingsService.save(currentGrid);
    final existingPhoto = await photos.getById(_photoB);

    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );
    await (await db.database).execute('''
      CREATE TRIGGER fail_backup_restore
      BEFORE INSERT ON ${AppDatabase.tableMembers}
      BEGIN
        SELECT RAISE(ABORT, 'injected restore failure');
      END
    ''');
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );

    expect(outcome.success, isFalse);
    expect(await members.getById(_memberA), isNull);
    expect((await members.getById(_memberB))!.name, '기존 회원');
    expect(await File(existingPhoto!.filePath).readAsBytes(), [5, 5, 5]);
    expect((await settingsService.load()).toMap(), currentSettings.toMap());
    expect(await gridSettingsService.load(), currentGrid);
    expect(await _allFiles(storageRoot), [existingPhoto.filePath]);
  });

  test('설정 적용 후 DB commit 전 종료는 다음 시작에서 기존 상태로 rollback한다', () async {
    final scenario = await prepareReplaceCrashScenario();
    final interruptedService = makeService(
      restoreInterruptionHook: (point) async {
        if (point ==
            RestoreInterruptionPoint.settingsAppliedBeforeDatabaseCommit) {
          throw StateError('simulate process termination');
        }
      },
    );

    await expectLater(
      interruptedService.applyRestore(
        scenario.preview,
        mode: RestoreMode.replace,
      ),
      throwsA(isA<RestoreProcessInterruptedException>()),
    );

    expect(await members.getById(_memberA), isNull);
    expect((await members.getById(_memberB))!.name, '기존 회원');
    expect((await settingsService.load()).studioName, '복원 설정');
    expect(await gridSettingsService.load(), scenario.backupGrid);

    final journalFiles = restoreTempRoot
        .listSync(followLinks: false)
        .whereType<File>()
        .toList();
    expect(journalFiles, hasLength(1));
    final journalText = await journalFiles.single.readAsString();
    expect(journalText, isNot(contains(_backupPassword)));
    expect(journalText, isNot(contains(storageRoot.path)));
    expect(journalText, isNot(contains(restoreTempRoot.path)));
    expect(journalText, isNot(contains('기존 회원')));
    expect(journalText, isNot(contains('복원 설정')));
    expect(await File(scenario.currentLogoAbsolute).exists(), isTrue);

    final restartedService = makeService(
      storageOverride: createRestartedStorage(),
    );
    await restartedService.cleanupStaleRestoreDirectories();

    expect(await members.getById(_memberA), isNull);
    expect((await members.getById(_memberB))!.name, '기존 회원');
    expect(
      (await settingsService.load()).toMap(),
      scenario.currentSettings.toMap(),
    );
    expect(await gridSettingsService.load(), scenario.currentGrid);
    expect(await File(scenario.currentLogoAbsolute).readAsBytes(), [9, 9, 9]);
    expect(await File(scenario.currentPhotoAbsolute).readAsBytes(), [8, 8, 8]);
    expect(await restoreTempRoot.list().toList(), isEmpty);
    expect(
      await (await db.database).query(AppDatabase.tableRestoreOperations),
      isEmpty,
    );
  });

  for (final failureTarget in ['app settings', 'grid settings']) {
    test('$failureTarget rollback 실패 시 파일과 저널을 보존하고 다음 시작에서 재시도한다', () async {
      final scenario = await prepareReplaceCrashScenario();
      final interruptedService = makeService(
        restoreInterruptionHook: (point) async {
          if (point ==
              RestoreInterruptionPoint.settingsAppliedBeforeDatabaseCommit) {
            throw StateError('simulate process termination');
          }
        },
      );
      await expectLater(
        interruptedService.applyRestore(
          scenario.preview,
          mode: RestoreMode.replace,
        ),
        throwsA(isA<RestoreProcessInterruptedException>()),
      );

      final filesBeforeFailedRecovery = await _allFiles(storageRoot);
      expect(filesBeforeFailedRecovery, hasLength(4));
      final journalFile = restoreTempRoot
          .listSync(followLinks: false)
          .whereType<File>()
          .single;
      expect(await journalFile.exists(), isTrue);
      expect(await Directory(scenario.preview.tempDirPath).exists(), isTrue);

      final failingService = makeService(
        storageOverride: createRestartedStorage(),
        settingsServiceOverride: failureTarget == 'app settings'
            ? _FailingSaveAppSettingsService(settingsService)
            : null,
        gridSettingsServiceOverride: failureTarget == 'grid settings'
            ? _FailingSaveGridSettingsService(gridSettingsService)
            : null,
      );
      await expectLater(
        failingService.cleanupStaleRestoreDirectories(),
        throwsA(isA<StateError>()),
      );

      expect(await _allFiles(storageRoot), filesBeforeFailedRecovery);
      expect(await journalFile.exists(), isTrue);
      expect(await Directory(scenario.preview.tempDirPath).exists(), isTrue);
      expect(await File(scenario.currentLogoAbsolute).readAsBytes(), [9, 9, 9]);
      expect(await File(scenario.currentPhotoAbsolute).readAsBytes(), [
        8,
        8,
        8,
      ]);

      final retryService = makeService(
        storageOverride: createRestartedStorage(),
      );
      await retryService.cleanupStaleRestoreDirectories();

      final expectedRemainingFiles = [
        scenario.currentLogoAbsolute,
        scenario.currentPhotoAbsolute,
      ]..sort();
      expect(await _allFiles(storageRoot), expectedRemainingFiles);
      expect(
        (await settingsService.load()).toMap(),
        scenario.currentSettings.toMap(),
      );
      expect(await gridSettingsService.load(), scenario.currentGrid);
      expect(await restoreTempRoot.list().toList(), isEmpty);
    });
  }

  test('DB commit 후 저널 정리 전 종료는 다음 시작에서 복원 상태를 확정한다', () async {
    final scenario = await prepareReplaceCrashScenario();
    final interruptedService = makeService(
      restoreInterruptionHook: (point) async {
        if (point ==
            RestoreInterruptionPoint.databaseCommittedBeforeJournalCleanup) {
          throw StateError('simulate process termination');
        }
      },
    );

    await expectLater(
      interruptedService.applyRestore(
        scenario.preview,
        mode: RestoreMode.replace,
      ),
      throwsA(isA<RestoreProcessInterruptedException>()),
    );

    expect((await members.getById(_memberA))!.name, '홍길동');
    expect(await members.getById(_memberB), isNull);
    expect((await settingsService.load()).studioName, '복원 설정');
    expect(await gridSettingsService.load(), scenario.backupGrid);
    expect(await File(scenario.currentLogoAbsolute).exists(), isTrue);
    expect(await File(scenario.currentPhotoAbsolute).exists(), isTrue);
    expect(
      await (await db.database).query(AppDatabase.tableRestoreOperations),
      hasLength(1),
    );

    final restartedService = makeService();
    await restartedService.cleanupStaleRestoreDirectories();

    expect((await members.getById(_memberA))!.name, '홍길동');
    expect(await members.getById(_memberB), isNull);
    expect((await settingsService.load()).studioName, '복원 설정');
    expect(await gridSettingsService.load(), scenario.backupGrid);
    expect(await File(scenario.currentLogoAbsolute).exists(), isFalse);
    expect(await File(scenario.currentPhotoAbsolute).exists(), isFalse);
    final restoredPhoto = (await photos.listByRecord(_recordA)).single;
    expect(await File(restoredPhoto.filePath).readAsBytes(), [1, 2, 3, 4]);
    final restoredLogo = (await settingsService.load()).studioLogoPath!;
    expect(await File(await storage.resolvePath(restoredLogo)).readAsBytes(), [
      4,
      4,
      4,
    ]);
    expect(await restoreTempRoot.list().toList(), isEmpty);
    expect(
      await (await db.database).query(AppDatabase.tableRestoreOperations),
      isEmpty,
    );
  });

  test('v1 전체 백업도 설정의 기본 격자를 이용해 호환 복원한다', () async {
    const legacyGrid = GridSettings(
      visible: false,
      opacity: 0.35,
      lineWidth: 3,
      spacing: 64,
      colorValue: 0xFFABCDEF,
    );
    await gridSettingsService.save(legacyGrid);
    await seedSampleData();
    final currentZip = await buildPlaintextBackup();
    final legacyZip = _rewriteZip(
      currentZip,
      mutateData: (data) {
        data['formatVersion'] = legacyBackupFormatVersion;
        data.remove('gridSettings');
      },
    );

    final preview = await backupService.prepareRestore(legacyZip);
    expect(preview.formatVersion, legacyBackupFormatVersion);
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );
    expect(outcome.success, isTrue);
    expect(await gridSettingsService.load(), legacyGrid);
  });

  test('회원별 백업은 선택 회원만 포함하며 전역 설정을 포함하지 않는다', () async {
    await seedSampleData();
    await seedSampleData(
      memberId: _memberB,
      recordId: _recordB,
      photoId: _photoB,
      name: '김철수',
    );

    final zipBytes = await buildEncryptedBackup(memberId: _memberA);
    final preview = await backupService.prepareRestore(
      zipBytes,
      password: _backupPassword,
    );

    expect(preview.scope, BackupScope.member);
    expect(preview.memberCount, 1);
    expect(preview.rawMembers.single['id'], _memberA);
    expect(preview.rawSettings, isNull);
    expect(preview.rawGridSettings, isNull);
    await backupService.discardRestore(preview);
  });

  test('회원별 백업은 교체 모드를 거부하고 다른 회원과 파일을 보존한다', () async {
    await seedSampleData();
    final memberBackup = await buildEncryptedBackup(memberId: _memberA);
    await seedSampleData(
      memberId: _memberB,
      recordId: _recordB,
      photoId: _photoB,
      name: '보존할 회원',
      bytes: const [9, 9, 9],
    );
    final memberAPhoto = await photos.getById(_photoA);
    final memberBPhoto = await photos.getById(_photoB);

    final preview = await backupService.prepareRestore(
      memberBackup,
      password: _backupPassword,
    );
    final outcome = await backupService.applyRestore(
      preview,
      mode: RestoreMode.replace,
    );

    expect(outcome.success, isFalse);
    expect((await members.getById(_memberA))!.name, '홍길동');
    expect((await members.getById(_memberB))!.name, '보존할 회원');
    expect(await File(memberAPhoto!.filePath).readAsBytes(), const [
      1,
      2,
      3,
      4,
    ]);
    expect(await File(memberBPhoto!.filePath).readAsBytes(), const [9, 9, 9]);
    expect(await Directory(preview.tempDirPath).exists(), isFalse);
  });

  test('복원 취소와 시작 전 stale 정리는 알려진 임시 디렉터리만 삭제한다', () async {
    final stale = Directory(
      '${restoreTempRoot.path}/body_frame_restore_abandoned',
    );
    final unrelated = Directory('${restoreTempRoot.path}/keep_me');
    await stale.create();
    await unrelated.create();

    await backupService.cleanupStaleRestoreDirectories();
    expect(await stale.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);

    await seedSampleData();
    final preview = await backupService.prepareRestore(
      await buildEncryptedBackup(),
      password: _backupPassword,
    );
    expect(await Directory(preview.tempDirPath).exists(), isTrue);
    await backupService.discardRestore(preview);
    expect(await Directory(preview.tempDirPath).exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });
}

Map<String, dynamic> _firstMap(Map<String, dynamic> data, String key) {
  return (data[key] as List<dynamic>).first as Map<String, dynamic>;
}

Uint8List _rewriteZip(
  Uint8List source, {
  void Function(Map<String, dynamic> data)? mutateData,
  Set<String> removeNames = const {},
  List<ArchiveFile> extraFiles = const [],
}) {
  final decoded = ZipDecoder().decodeBytes(source);
  final rewritten = Archive();
  for (final entry in decoded.files) {
    if (removeNames.contains(entry.name)) continue;
    var content = List<int>.from(entry.content as List<int>);
    if (entry.name == 'data.json' && mutateData != null) {
      final data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      mutateData(data);
      content = utf8.encode(jsonEncode(data));
    }
    rewritten.addFile(ArchiveFile(entry.name, content.length, content));
  }
  for (final entry in extraFiles) {
    rewritten.addFile(entry);
  }
  return Uint8List.fromList(ZipEncoder().encode(rewritten) ?? const []);
}

Future<List<String>> _allFiles(Directory root) async {
  final paths = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) paths.add(entity.path);
  }
  paths.sort();
  return paths;
}

class _ReplaceCrashScenario {
  final RestorePreview preview;
  final GridSettings backupGrid;
  final GridSettings currentGrid;
  final AppSettings currentSettings;
  final String currentLogoAbsolute;
  final String currentPhotoAbsolute;

  const _ReplaceCrashScenario({
    required this.preview,
    required this.backupGrid,
    required this.currentGrid,
    required this.currentSettings,
    required this.currentLogoAbsolute,
    required this.currentPhotoAbsolute,
  });
}

class _FailingSaveAppSettingsService implements AppSettingsService {
  final AppSettingsService delegate;

  const _FailingSaveAppSettingsService(this.delegate);

  @override
  Future<AppSettings> load() => delegate.load();

  @override
  Future<void> save(AppSettings settings) {
    throw StateError('injected app settings save failure');
  }
}

class _FailingSaveGridSettingsService implements GridSettingsService {
  final GridSettingsService delegate;

  const _FailingSaveGridSettingsService(this.delegate);

  @override
  Future<GridSettings> load() => delegate.load();

  @override
  Future<void> reset() => delegate.reset();

  @override
  Future<void> save(GridSettings settings) {
    throw StateError('injected grid settings save failure');
  }
}
