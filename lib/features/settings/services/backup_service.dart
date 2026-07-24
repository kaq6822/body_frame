import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/photo_storage_service.dart';
import '../models/backup_models.dart';
import 'app_settings_service.dart';

/// 전체/회원별 데이터 백업 생성과 복원을 담당한다.
///
/// 1) [prepareRestore]: zip을 임시 디렉터리에 풀어 검증하고 미리보기(회원/기록/사진 수,
///    중복 회원 여부)를 반환한다. 이 단계는 실제 DB나 사진 저장소를 전혀 건드리지
///    않으므로, 잘못된 백업 파일이어도 기존 데이터는 항상 그대로 유지된다.
/// 2) [applyRestore]: 사용자가 모드(교체/추가)를 확인한 뒤에만 실제로 적용한다.
///    DB 행 변경은 단일 트랜잭션으로 처리해 중간 실패 시 sqflite가 자동으로
///    롤백한다. 사진 파일 복사는 커밋 뒤 수행하며 실패 개수를 결과로 보고한다.
abstract class BackupService {
  /// [memberId]가 null이면 전체 백업, 아니면 해당 회원만 백업한다.
  Future<Uint8List> buildBackup({String? memberId});

  Future<RestorePreview> prepareRestore(Uint8List zipBytes);

  Future<BackupOutcome> applyRestore(
    RestorePreview preview, {
    required RestoreMode mode,
  });

  /// 사용자가 복원을 취소했을 때 임시 파일을 정리한다.
  Future<void> discardRestore(RestorePreview preview);
}

class BackupServiceImpl implements BackupService {
  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppSettingsService _settingsService;
  final AppLogger _logger;
  final Uuid _uuid;

  /// 복원 임시 추출 디렉터리의 부모 경로 재정의(테스트용). null이면
  /// path_provider의 시스템 임시 디렉터리를 사용한다.
  final String? _tempRootOverride;

  BackupServiceImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    required AppSettingsService settingsService,
    AppLogger? logger,
    Uuid? uuid,
    String? tempRootOverride,
  })  : _db = database,
        _storage = storage,
        _settingsService = settingsService,
        _logger = logger ?? AppLogger.instance,
        _uuid = uuid ?? const Uuid(),
        _tempRootOverride = tempRootOverride;

  Future<Directory> _tempRoot() async {
    if (_tempRootOverride != null) {
      final dir = Directory(_tempRootOverride);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    return getTemporaryDirectory();
  }

  // ---------------------------------------------------------------------
  // 백업 생성
  // ---------------------------------------------------------------------

  @override
  Future<Uint8List> buildBackup({String? memberId}) async {
    _logger.phase(
      'backup.create',
      LogPhase.start,
      context: {'scope': memberId == null ? 'all' : 'member'},
    );

    final db = await _db.database;

    final memberRows = await db.query(
      AppDatabase.tableMembers,
      where: memberId == null ? null : 'id = ?',
      whereArgs: memberId == null ? null : [memberId],
    );
    if (memberRows.isEmpty && memberId != null) {
      throw StateError('백업할 회원을 찾을 수 없습니다');
    }
    final memberIds = memberRows.map((m) => m['id'] as String).toSet();

    final recordRows = <Map<String, Object?>>[];
    final recordIdToMemberId = <String, String>{};
    for (final mid in memberIds) {
      final rs = await db.query(
        AppDatabase.tablePhotoRecords,
        where: 'member_id = ?',
        whereArgs: [mid],
      );
      for (final r in rs) {
        recordRows.add(Map<String, Object?>.from(r));
        recordIdToMemberId[r['id'] as String] = mid;
      }
    }

    final archive = Archive();
    final photoJsonList = <Map<String, dynamic>>[];
    var missingFileCount = 0;

    for (final record in recordRows) {
      final recordId = record['id'] as String;
      final ownerMemberId = recordIdToMemberId[recordId]!;
      final photoRows = await db.query(
        AppDatabase.tableBodyPhotos,
        where: 'record_id = ?',
        whereArgs: [recordId],
      );
      for (final row in photoRows) {
        final map = Map<String, Object?>.from(row);
        final absPath = map['file_path'] as String;
        final file = File(absPath);
        final entryName = 'photos/$ownerMemberId/${p.basename(absPath)}';
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
          map['file_path'] = entryName;
        } else {
          missingFileCount += 1;
          map['file_path'] = null;
        }
        photoJsonList.add(map);
      }
    }
    if (missingFileCount > 0) {
      _logger.warn('backup.photo.missingFile', context: {'count': missingFileCount});
    }

    final memberJsonList = <Map<String, dynamic>>[];
    for (final row in memberRows) {
      final map = Map<String, Object?>.from(row);
      final avatar = map['avatar_path'] as String?;
      if (avatar != null && avatar.isNotEmpty) {
        final file = File(avatar);
        if (await file.exists()) {
          final entryName = 'avatars/${map['id']}/${p.basename(avatar)}';
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
          map['avatar_path'] = entryName;
        } else {
          map['avatar_path'] = null;
        }
      }
      memberJsonList.add(map);
    }

    final data = <String, dynamic>{
      'formatVersion': backupFormatVersion,
      'scope': memberId == null ? 'all' : 'member',
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'settings': memberId == null ? (await _settingsService.load()).toMap() : null,
      'members': memberJsonList,
      'photoRecords': recordRows,
      'bodyPhotos': photoJsonList,
    };
    archive.addFile(_jsonFile('data.json', data));

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('백업 zip 인코딩에 실패했습니다');
    }
    _logger.phase('backup.create', LogPhase.success, context: {
      'members': memberJsonList.length,
      'records': recordRows.length,
      'photos': photoJsonList.length,
    });
    return Uint8List.fromList(encoded);
  }

  ArchiveFile _jsonFile(String name, Object data) {
    final bytes = utf8.encode(jsonEncode(data));
    return ArchiveFile(name, bytes.length, bytes);
  }

  // ---------------------------------------------------------------------
  // 복원 1단계: 검증 + 미리보기 (실제 데이터 미변경)
  // ---------------------------------------------------------------------

  @override
  Future<RestorePreview> prepareRestore(Uint8List zipBytes) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw const FormatException('올바른 백업 파일이 아닙니다');
    }

    ArchiveFile? dataEntry;
    for (final f in archive.files) {
      if (f.name == 'data.json') {
        dataEntry = f;
        break;
      }
    }
    if (dataEntry == null) {
      throw const FormatException('백업 데이터가 없습니다(data.json 누락)');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(dataEntry.content as List<int>))
          as Map<String, dynamic>;
    } catch (e) {
      throw const FormatException('백업 데이터 형식이 올바르지 않습니다');
    }

    final formatVersion = data['formatVersion'] as int? ?? 0;
    if (formatVersion != backupFormatVersion) {
      throw FormatException('지원하지 않는 백업 형식 버전입니다: $formatVersion');
    }

    final members = ((data['members'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final records = ((data['photoRecords'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final photos = ((data['bodyPhotos'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final scope = (data['scope'] as String?) == 'member'
        ? BackupScope.member
        : BackupScope.all;
    final rawSettings = data['settings'] as Map<String, dynamic>?;

    // zip을 임시 디렉터리에 추출한다. 여기서 실패해도 실제 저장소는 전혀
    // 건드리지 않으므로 기존 데이터는 그대로 유지된다.
    final tempRoot = await _tempRoot();
    final tempDir = Directory(
      p.join(tempRoot.path, 'body_frame_restore_${_uuid.v4()}'),
    );
    await tempDir.create(recursive: true);

    try {
      for (final file in archive.files) {
        if (!file.isFile || file.name == 'data.json') continue;
        // zip slip 방어: 항목 이름이 절대경로이거나 ../로 임시 디렉터리를
        // 벗어나는 백업 파일은 신뢰할 수 없는 입력으로 보고 거부한다.
        final outPath = p.normalize(p.join(tempDir.path, file.name));
        if (!p.isWithin(tempDir.path, outPath)) {
          throw FormatException(
            '백업 파일에 허용되지 않는 경로가 포함되어 있습니다: ${file.name}',
          );
        }
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }

      for (final photo in photos) {
        final rel = photo['file_path'] as String?;
        if (rel == null) continue;
        final f = File(p.join(tempDir.path, rel));
        if (!await f.exists()) {
          throw FormatException('백업 파일에 사진 데이터가 누락되었습니다: $rel');
        }
      }
    } catch (e) {
      await _safeDeleteDir(tempDir.path);
      rethrow;
    }

    final existingMemberRows = await (await _db.database).query(
      AppDatabase.tableMembers,
      columns: ['id'],
    );
    final existingIds = existingMemberRows.map((r) => r['id'] as String).toSet();
    final duplicates = members
        .map((m) => m['id'] as String)
        .where(existingIds.contains)
        .toSet();

    final preview = RestorePreview(
      tempDirPath: tempDir.path,
      formatVersion: formatVersion,
      scope: scope,
      memberCount: members.length,
      recordCount: records.length,
      photoCount: photos.length,
      duplicateMemberIds: duplicates,
      rawMembers: members,
      rawRecords: records,
      rawPhotos: photos,
      rawSettings: rawSettings,
    );
    _logger.phase('backup.restore.prepare', LogPhase.success, context: {
      'members': members.length,
      'records': records.length,
      'photos': photos.length,
      'duplicates': duplicates.length,
    });
    return preview;
  }

  // ---------------------------------------------------------------------
  // 복원 2단계: 적용 (DB는 단일 트랜잭션, 파일 복사는 커밋 이후)
  // ---------------------------------------------------------------------

  @override
  Future<BackupOutcome> applyRestore(
    RestorePreview preview, {
    required RestoreMode mode,
  }) async {
    _logger.phase('backup.restore.apply', LogPhase.start, context: {'mode': mode.name});
    final db = await _db.database;

    List<String> previousMemberIds = const [];
    if (mode == RestoreMode.replace) {
      final rows = await db.query(AppDatabase.tableMembers, columns: ['id']);
      previousMemberIds = rows.map((r) => r['id'] as String).toList();
    }

    final memberIdRemap = <String, String>{};
    if (mode == RestoreMode.append) {
      final existing = (await db.query(AppDatabase.tableMembers, columns: ['id']))
          .map((r) => r['id'] as String)
          .toSet();
      for (final m in preview.rawMembers) {
        final id = m['id'] as String;
        if (existing.contains(id)) {
          memberIdRemap[id] = _uuid.v4();
        }
      }
    }

    final recordIdRemap = <String, String>{};
    // 사진 id -> (새 member id, zip 내부 상대 file_path). 커밋 이후 파일 복사에 사용.
    final pendingPhotoFiles = <String, ({String memberId, String relPath})>{};
    final pendingAvatarFiles = <String, String>{}; // memberId(신규) -> zip 상대경로

    try {
      await db.transaction((txn) async {
        if (mode == RestoreMode.replace) {
          // ON DELETE CASCADE로 photo_records/body_photos 행도 함께 삭제된다.
          await txn.delete(AppDatabase.tableMembers);
        }

        for (final m in preview.rawMembers) {
          final map = Map<String, Object?>.from(m);
          final originalId = map['id'] as String;
          final newId = memberIdRemap[originalId] ?? originalId;
          map['id'] = newId;
          final avatarRel = map['avatar_path'] as String?;
          map['avatar_path'] = null; // 파일 복사 후 별도로 채운다.
          if (avatarRel != null && avatarRel.isNotEmpty) {
            pendingAvatarFiles[newId] = avatarRel;
          }
          await txn.insert(
            AppDatabase.tableMembers,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        for (final r in preview.rawRecords) {
          final map = Map<String, Object?>.from(r);
          final originalId = map['id'] as String;
          final originalMemberId = map['member_id'] as String;
          final ownerRemapped = memberIdRemap.containsKey(originalMemberId);
          final newRecordId = ownerRemapped ? _uuid.v4() : originalId;
          recordIdRemap[originalId] = newRecordId;
          map['id'] = newRecordId;
          map['member_id'] = memberIdRemap[originalMemberId] ?? originalMemberId;
          await txn.insert(
            AppDatabase.tablePhotoRecords,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        for (final ph in preview.rawPhotos) {
          final map = Map<String, Object?>.from(ph);
          final originalId = map['id'] as String;
          final originalRecordId = map['record_id'] as String;
          final newRecordId = recordIdRemap[originalRecordId] ?? originalRecordId;
          final ownerRemapped = newRecordId != originalRecordId;
          final newPhotoId = ownerRemapped ? _uuid.v4() : originalId;
          map['id'] = newPhotoId;
          map['record_id'] = newRecordId;
          final rel = map['file_path'] as String?;
          map['file_path'] = ''; // 파일 복사 후 실제 경로로 갱신
          if (rel != null && rel.isNotEmpty) {
            // 이 사진이 속한 최종 member id를 photos/<memberId>/... 경로에서 추출.
            final segments = p.split(rel);
            final memberIdInPath = segments.length >= 2 ? segments[1] : '';
            final finalMemberId = memberIdRemap[memberIdInPath] ?? memberIdInPath;
            pendingPhotoFiles[newPhotoId] = (memberId: finalMemberId, relPath: rel);
          }
          await txn.insert(
            AppDatabase.tableBodyPhotos,
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      _logger.error('backup.restore.apply.failure', err: e);
      await discardRestore(preview);
      return BackupOutcome(success: false, error: '복원 중 오류가 발생했습니다: $e');
    }

    // 여기부터는 DB 트랜잭션이 이미 커밋된 이후다. 교체 모드에서는 기존 사진
    // 디렉터리를 정리한 뒤 새 사진 파일을 실제 저장소로 복사한다.
    if (mode == RestoreMode.replace) {
      for (final oldId in previousMemberIds) {
        await _storage.deleteMemberDir(oldId);
      }
    }

    var copyFailures = 0;
    for (final entry in pendingPhotoFiles.entries) {
      final photoId = entry.key;
      final memberId = entry.value.memberId;
      final relPath = entry.value.relPath;
      try {
        final srcFile = File(p.join(preview.tempDirPath, relPath));
        final destDir = await _storage.memberDir(memberId);
        final destPath = p.join(destDir.path, p.basename(relPath));
        await srcFile.copy(destPath);
        await db.update(
          AppDatabase.tableBodyPhotos,
          {'file_path': destPath},
          where: 'id = ?',
          whereArgs: [photoId],
        );
      } catch (e) {
        copyFailures += 1;
        _logger.warn('backup.restore.photoCopy.failure', context: {'photoId': photoId});
      }
    }

    for (final entry in pendingAvatarFiles.entries) {
      final memberId = entry.key;
      final relPath = entry.value;
      try {
        final srcFile = File(p.join(preview.tempDirPath, relPath));
        final destDir = await _storage.memberDir(memberId);
        final destPath = p.join(destDir.path, 'avatar_${p.basename(relPath)}');
        await srcFile.copy(destPath);
        await db.update(
          AppDatabase.tableMembers,
          {'avatar_path': destPath},
          where: 'id = ?',
          whereArgs: [memberId],
        );
      } catch (e) {
        _logger.warn('backup.restore.avatarCopy.failure', context: {'memberId': memberId});
      }
    }

    await _safeDeleteDir(preview.tempDirPath);

    _logger.phase('backup.restore.apply', LogPhase.success, context: {
      'members': preview.memberCount,
      'records': preview.recordCount,
      'photos': preview.photoCount,
      'copyFailures': copyFailures,
    });

    return BackupOutcome(
      success: true,
      memberCount: preview.memberCount,
      recordCount: preview.recordCount,
      photoCount: preview.photoCount,
      error: copyFailures > 0 ? '$copyFailures개의 사진 파일 복사에 실패했습니다' : null,
    );
  }

  @override
  Future<void> discardRestore(RestorePreview preview) async {
    await _safeDeleteDir(preview.tempDirPath);
  }

  Future<void> _safeDeleteDir(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 임시 파일 정리 실패는 치명적이지 않으므로 무시한다.
    }
  }
}
