import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/models.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/grid_settings_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../models/backup_models.dart';
import 'app_settings_service.dart';
import 'backup_archive_cipher.dart';

typedef RestoreFileCopier =
    Future<void> Function(String sourcePath, String destinationPath);

enum RestoreInterruptionPoint {
  settingsAppliedBeforeDatabaseCommit,
  databaseCommittedBeforeJournalCleanup,
}

typedef RestoreInterruptionHook =
    Future<void> Function(RestoreInterruptionPoint point);

/// 테스트에서 프로세스 종료를 재현하기 위한 예외다.
///
/// 실제 프로세스 종료와 마찬가지로 [BackupServiceImpl.applyRestore]의 in-process
/// rollback을 우회하며, 다음 서비스 진입에서 durable journal을 조정한다.
class RestoreProcessInterruptedException implements Exception {
  const RestoreProcessInterruptedException();
}

/// 전체/회원별 데이터 백업 생성과 복원을 담당한다.
///
/// 복원 입력은 신뢰하지 않는다. [prepareRestore]에서 JSON 스키마, UUID,
/// 관계 그래프, 저장 파일 소유권과 ZIP 자원 상한을 모두 검증한다.
///
/// [applyRestore]는 새 파일을 고유 경로에 먼저 staging하고 모든 복사가 성공한
/// 뒤에만 DB를 변경한다. staging 또는 DB 적용이 실패하면 새 파일과 설정을
/// 정리하고 기존 DB/파일/설정을 그대로 유지한다.
abstract class BackupService {
  /// 선택 파일 전체를 메모리에 읽기 전에 적용해야 하는 복원 입력 크기 계약.
  BackupRestoreInputLimits get restoreInputLimits;

  /// [memberId]가 null이면 전체 백업, 아니면 해당 회원만 백업한다.
  Future<Uint8List> buildBackup({String? memberId, required String password});

  bool isEncryptedBackup(List<int> bytes);

  Future<RestorePreview> prepareRestore(
    Uint8List backupBytes, {
    String? password,
  });

  /// 이전 실행에서 남은 복원 임시 디렉터리를 안전한 범위 안에서 정리한다.
  Future<void> cleanupStaleRestoreDirectories();

  Future<BackupOutcome> applyRestore(
    RestorePreview preview, {
    required RestoreMode mode,
  });

  /// 사용자가 복원을 취소했을 때 임시 파일을 정리한다.
  Future<void> discardRestore(RestorePreview preview);
}

class BackupServiceImpl implements BackupService {
  static const _restoreDirPrefix = 'body_frame_restore_';
  static const _restoreJournalFileName = 'restore_journal.json';
  static const _restoreJournalVersion = 1;
  static const _studioAssetOwner = 'studio-assets';

  static const _dataV1Keys = {
    'formatVersion',
    'scope',
    'exportedAt',
    'settings',
    'members',
    'photoRecords',
    'bodyPhotos',
  };
  static const _dataV2Keys = {..._dataV1Keys, 'gridSettings'};
  static const _memberKeys = {
    'id',
    'name',
    'avatar_path',
    'gender',
    'birth',
    'contact',
    'memo',
    'created_at',
    'updated_at',
  };
  static const _recordKeys = {
    'id',
    'member_id',
    'shot_at',
    'memo',
    'created_at',
    'updated_at',
  };
  static const _photoKeys = {
    'id',
    'record_id',
    'file_path',
    'direction',
    'width',
    'height',
    'orientation',
    'grid_settings',
    'memo',
    'created_at',
  };
  static const _settingsKeys = {
    'lockMode',
    'biometricEnabled',
    'autoLockSeconds',
    'defaultGrid',
    'defaultExportOptions',
    'studioName',
    'studioLogoPath',
    'dataNoticeAcknowledged',
  };
  static const _exportOptionKeys = {
    'includeMemberName',
    'includeShotDate',
    'includeMemo',
    'includeGrid',
    'includeStudioName',
    'includeWatermark',
  };
  static const _gridKeys = {
    'visible',
    'opacity',
    'lineWidth',
    'spacing',
    'colorValue',
  };

  final AppDatabase _db;
  final PhotoStorageService _storage;
  final AppSettingsService _settingsService;
  final GridSettingsService _gridSettingsService;
  final AppLogger _logger;
  final Uuid _uuid;
  final BackupArchiveLimits _limits;
  final RestoreFileCopier? _restoreFileCopier;
  final RestoreInterruptionHook? _restoreInterruptionHook;
  final BackupArchiveCipher _archiveCipher;

  /// 복원 임시 추출 디렉터리의 부모 경로 재정의(테스트용). null이면
  /// path_provider의 시스템 임시 디렉터리를 사용한다.
  final String? _tempRootOverride;

  BackupServiceImpl({
    required AppDatabase database,
    required PhotoStorageService storage,
    required AppSettingsService settingsService,
    required GridSettingsService gridSettingsService,
    AppLogger? logger,
    Uuid? uuid,
    BackupArchiveLimits limits = const BackupArchiveLimits(),
    RestoreFileCopier? restoreFileCopier,
    RestoreInterruptionHook? restoreInterruptionHook,
    BackupArchiveCipher? archiveCipher,
    String? tempRootOverride,
  }) : _db = database,
       _storage = storage,
       _settingsService = settingsService,
       _gridSettingsService = gridSettingsService,
       _logger = logger ?? AppLogger.instance,
       _uuid = uuid ?? const Uuid(),
       _limits = limits,
       _restoreFileCopier = restoreFileCopier,
       _restoreInterruptionHook = restoreInterruptionHook,
       _archiveCipher =
           archiveCipher ??
           BackupArchiveCipherImpl(
             maxPlaintextBytes: limits.maxCompressedBytes,
           ),
       _tempRootOverride = tempRootOverride;

  @override
  BackupRestoreInputLimits get restoreInputLimits => BackupRestoreInputLimits(
    maximumLegacyZipBytes: _limits.maxCompressedBytes,
    maximumEncryptedContainerBytes: _archiveCipher
        .maximumContainerBytesForPlaintextLimit(_limits.maxCompressedBytes),
  );

  Future<Directory> _tempRoot() async {
    if (_tempRootOverride != null) {
      final dir = Directory(p.normalize(p.absolute(_tempRootOverride)));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    // 복호화된 사진 staging은 평문이므로 iOS에서 backup exclusion과
    // FileProtection.complete를 상속하는 Application Support 아래에 둔다.
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'body_frame_restore_staging'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------
  // 백업 생성
  // ---------------------------------------------------------------------

  @override
  Future<Uint8List> buildBackup({
    String? memberId,
    required String password,
  }) async {
    await _reconcileInterruptedRestore();
    _archiveCipher.validatePasswordForEncryption(password);
    _logger.phase(
      'backup.create',
      LogPhase.start,
      context: {'scope': memberId == null ? 'all' : 'member'},
    );

    try {
      final db = await _db.database;
      late List<Map<String, Object?>> memberRows;
      final recordRows = <Map<String, Object?>>[];
      final photoRows = <Map<String, Object?>>[];
      final recordOwner = <String, String>{};

      // DB 관계는 하나의 읽기 트랜잭션에서 스냅샷으로 가져온다.
      await db.transaction((txn) async {
        memberRows = await txn.query(
          AppDatabase.tableMembers,
          where: memberId == null ? null : 'id = ?',
          whereArgs: memberId == null ? null : [memberId],
        );
        if (memberRows.isEmpty && memberId != null) {
          throw StateError('백업할 회원을 찾을 수 없습니다');
        }

        for (final member in memberRows) {
          final id = member['id'] as String;
          final records = await txn.query(
            AppDatabase.tablePhotoRecords,
            where: 'member_id = ?',
            whereArgs: [id],
          );
          for (final record in records) {
            final recordMap = Map<String, Object?>.from(record);
            recordRows.add(recordMap);
            final recordId = recordMap['id'] as String;
            recordOwner[recordId] = id;
            final photos = await txn.query(
              AppDatabase.tableBodyPhotos,
              where: 'record_id = ?',
              whereArgs: [recordId],
            );
            photoRows.addAll(photos.map(Map<String, Object?>.from));
          }
        }
      });

      final archive = Archive();
      final archiveNames = <String>{};
      final photoJsonList = <Map<String, dynamic>>[];
      var totalUncompressedBytes = 0;

      for (final row in photoRows) {
        final map = Map<String, Object?>.from(row);
        final recordId = map['record_id'] as String;
        final ownerMemberId = recordOwner[recordId]!;
        final storedPath = map['file_path'] as String;
        final resolvedPath = await _storage.resolvePath(storedPath);
        final file = File(resolvedPath);
        final bytes = await _readRequiredBackupFile(
          file,
          label: '사진',
          totalSoFar: totalUncompressedBytes,
        );
        totalUncompressedBytes += bytes.length;
        final entryName = p.posix.join(
          'photos',
          ownerMemberId,
          p.basename(resolvedPath),
        );
        _addArchiveFile(archive, archiveNames, entryName, bytes);
        map['file_path'] = entryName;
        photoJsonList.add(Map<String, dynamic>.from(map));
      }

      final memberJsonList = <Map<String, dynamic>>[];
      for (final row in memberRows) {
        final map = Map<String, Object?>.from(row);
        final avatarStoredPath = map['avatar_path'] as String?;
        if (avatarStoredPath != null && avatarStoredPath.isNotEmpty) {
          final resolvedPath = await _storage.resolvePath(avatarStoredPath);
          final file = File(resolvedPath);
          final bytes = await _readRequiredBackupFile(
            file,
            label: '대표 사진',
            totalSoFar: totalUncompressedBytes,
          );
          totalUncompressedBytes += bytes.length;
          final entryName = p.posix.join(
            'avatars',
            map['id'] as String,
            p.basename(resolvedPath),
          );
          _addArchiveFile(archive, archiveNames, entryName, bytes);
          map['avatar_path'] = entryName;
        }
        memberJsonList.add(Map<String, dynamic>.from(map));
      }

      Map<String, dynamic>? settingsMap;
      Map<String, dynamic>? gridMap;
      if (memberId == null) {
        final grid = await _gridSettingsService.load();
        final settings = await _settingsService.load();
        String? archivedStudioLogoPath;
        final studioLogoPath = settings.studioLogoPath;
        if (studioLogoPath != null && studioLogoPath.isNotEmpty) {
          final resolvedPath = await _storage.resolvePath(studioLogoPath);
          final storedPath = await _storage.toStoredPath(resolvedPath);
          _validateStoredStudioLogoPath(storedPath);
          final bytes = await _readRequiredBackupFile(
            File(resolvedPath),
            label: '스튜디오 로고',
            totalSoFar: totalUncompressedBytes,
          );
          totalUncompressedBytes += bytes.length;
          archivedStudioLogoPath = p.posix.join(
            'assets',
            'studio',
            p.basename(resolvedPath),
          );
          _addArchiveFile(archive, archiveNames, archivedStudioLogoPath, bytes);
        }
        settingsMap = _portableSettings(
          settings,
          grid,
          archivedStudioLogoPath: archivedStudioLogoPath,
        ).toMap();
        gridMap = grid.toMap();
      }

      final data = <String, dynamic>{
        'formatVersion': backupFormatVersion,
        'scope': memberId == null ? 'all' : 'member',
        'exportedAt': DateTime.now().millisecondsSinceEpoch,
        'settings': settingsMap,
        'gridSettings': gridMap,
        'members': memberJsonList,
        'photoRecords': recordRows,
        'bodyPhotos': photoJsonList,
      };

      // 현재 DB가 손상되어 있어도 복원 불가능한 백업을 만들지 않는다.
      _validatePayload(data);
      final dataBytes = utf8.encode(jsonEncode(data));
      if (dataBytes.length > _limits.maxDataJsonBytes) {
        throw StateError('백업 메타데이터가 허용 크기를 초과했습니다');
      }
      if (totalUncompressedBytes + dataBytes.length >
          _limits.maxTotalUncompressedBytes) {
        throw StateError('백업 데이터가 허용 크기를 초과했습니다');
      }
      _addArchiveFile(archive, archiveNames, 'data.json', dataBytes);
      if (archive.length > _limits.maxEntryCount) {
        throw StateError('백업 파일 수가 허용 개수를 초과했습니다');
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        throw StateError('백업 zip 인코딩에 실패했습니다');
      }
      if (encoded.length > _limits.maxCompressedBytes) {
        throw StateError('백업 ZIP이 허용 크기를 초과했습니다');
      }
      final encrypted = await _archiveCipher.encrypt(
        encoded,
        password: password,
      );
      _logger.phase(
        'backup.create',
        LogPhase.success,
        context: {
          'members': memberJsonList.length,
          'records': recordRows.length,
          'photos': photoJsonList.length,
        },
      );
      return encrypted;
    } catch (_) {
      _logger.phase('backup.create', LogPhase.failure);
      rethrow;
    }
  }

  AppSettings _portableSettings(
    AppSettings settings,
    GridSettings actualGrid, {
    required String? archivedStudioLogoPath,
  }) {
    // 잠금 자격 증명은 기기 secure storage에만 있으므로 잠금 관련 상태는
    // 백업하지 않는다. 로고는 별도 ZIP 항목의 상대경로로 치환한다.
    return AppSettings(
      lockMode: LockMode.none,
      biometricEnabled: false,
      autoLockSeconds: 0,
      defaultGrid: actualGrid,
      defaultExportOptions: settings.defaultExportOptions,
      studioName: settings.studioName,
      studioLogoPath: archivedStudioLogoPath,
      dataNoticeAcknowledged: settings.dataNoticeAcknowledged,
    );
  }

  void _validateStoredStudioLogoPath(String storedPath) {
    final normalized = p.posix.normalize(storedPath);
    final segments = p.posix.split(normalized);
    if (normalized != storedPath ||
        segments.length != 3 ||
        segments[0] != PhotoStorageServiceImpl.rootDirName ||
        segments[1] != _studioAssetOwner ||
        segments[2].isEmpty) {
      throw const FormatException('스튜디오 로고가 관리 저장소 경로에 있지 않습니다');
    }
  }

  Future<List<int>> _readRequiredBackupFile(
    File file, {
    required String label,
    required int totalSoFar,
  }) async {
    if (!await file.exists()) {
      throw StateError('$label 원본 파일이 누락되어 백업을 만들 수 없습니다');
    }
    final length = await file.length();
    if (length > _limits.maxSingleFileBytes) {
      throw StateError('$label 파일이 허용 크기를 초과했습니다');
    }
    if (totalSoFar + length > _limits.maxTotalUncompressedBytes) {
      throw StateError('백업 데이터가 허용 크기를 초과했습니다');
    }
    return file.readAsBytes();
  }

  void _addArchiveFile(
    Archive archive,
    Set<String> archiveNames,
    String name,
    List<int> bytes,
  ) {
    final normalized = _validateArchivePath(name);
    final duplicateKey = normalized.toLowerCase();
    if (!archiveNames.add(duplicateKey)) {
      throw StateError('백업 내부 파일 경로가 중복됩니다');
    }
    if (archive.length >= _limits.maxEntryCount) {
      throw StateError('백업 파일 수가 허용 개수를 초과했습니다');
    }
    archive.addFile(ArchiveFile(normalized, bytes.length, bytes));
  }

  // ---------------------------------------------------------------------
  // 복원 1단계: 검증 + 미리보기 (실제 데이터 미변경)
  // ---------------------------------------------------------------------

  @override
  bool isEncryptedBackup(List<int> bytes) => _archiveCipher.isEncrypted(bytes);

  @override
  Future<RestorePreview> prepareRestore(
    Uint8List backupBytes, {
    String? password,
  }) async {
    await cleanupStaleRestoreDirectories();

    final zipBytes = isEncryptedBackup(backupBytes)
        ? await _archiveCipher.decrypt(backupBytes, password: password)
        : backupBytes;
    if (zipBytes.length > _limits.maxCompressedBytes) {
      throw const FormatException('백업 ZIP이 허용 크기를 초과했습니다');
    }
    _validateZipEnvelope(zipBytes);

    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const FormatException('올바른 백업 파일이 아닙니다');
    }

    if (archive.isEmpty || archive.length > _limits.maxEntryCount) {
      throw const FormatException('백업 파일 수가 허용 범위를 벗어납니다');
    }

    final entries = <String, ArchiveFile>{};
    var totalUncompressedBytes = 0;
    for (final entry in archive.files) {
      if (entry.isSymbolicLink || !entry.isFile) {
        throw const FormatException('백업 ZIP에는 일반 파일만 포함할 수 있습니다');
      }
      final name = _validateArchivePath(entry.name);
      final duplicateKey = name.toLowerCase();
      if (entries.keys.any((key) => key.toLowerCase() == duplicateKey)) {
        throw const FormatException('백업 ZIP에 중복 파일 경로가 있습니다');
      }
      if (entry.size < 0) {
        throw const FormatException('백업 ZIP 파일 크기가 올바르지 않습니다');
      }
      final perFileLimit = name == 'data.json'
          ? _limits.maxDataJsonBytes
          : _limits.maxSingleFileBytes;
      if (entry.size > perFileLimit) {
        throw const FormatException('백업 ZIP 항목이 허용 크기를 초과했습니다');
      }
      totalUncompressedBytes += entry.size;
      if (totalUncompressedBytes > _limits.maxTotalUncompressedBytes) {
        throw const FormatException('백업 ZIP 해제 크기가 허용량을 초과했습니다');
      }
      entries[name] = entry;
    }

    final dataEntry = entries['data.json'];
    if (dataEntry == null) {
      throw const FormatException('백업 데이터가 없습니다(data.json 누락)');
    }

    late Map<String, dynamic> data;
    try {
      final content = _verifiedArchiveContent(
        dataEntry,
        maxBytes: _limits.maxDataJsonBytes,
      );
      data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('백업 데이터 형식이 올바르지 않습니다');
    }

    final payload = _validatePayload(data);
    final expectedFiles = payload.expectedFilePaths;
    final actualFiles = entries.keys
        .where((name) => name != 'data.json')
        .toSet();
    if (actualFiles.length != expectedFiles.length ||
        !actualFiles.containsAll(expectedFiles)) {
      throw const FormatException('백업 ZIP의 파일 목록과 메타데이터가 일치하지 않습니다');
    }

    final tempRoot = await _tempRoot();
    final tempDir = Directory(
      p.join(tempRoot.path, '$_restoreDirPrefix${_uuid.v4()}'),
    );
    await tempDir.create(recursive: true);

    try {
      for (final relativePath in expectedFiles) {
        final entry = entries[relativePath]!;
        final outPath = _pathInsideRestoreDir(tempDir.path, relativePath);
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(
          _verifiedArchiveContent(entry, maxBytes: _limits.maxSingleFileBytes),
          flush: true,
        );
      }

      final existingMemberRows = await (await _db.database).query(
        AppDatabase.tableMembers,
        columns: ['id'],
      );
      final existingIds = existingMemberRows
          .map((row) => row['id'] as String)
          .toSet();
      final duplicates = payload.members
          .map((member) => member['id'] as String)
          .where(existingIds.contains)
          .toSet();

      final preview = RestorePreview(
        tempDirPath: tempDir.path,
        formatVersion: payload.formatVersion,
        scope: payload.scope,
        memberCount: payload.members.length,
        recordCount: payload.records.length,
        photoCount: payload.photos.length,
        duplicateMemberIds: Set.unmodifiable(duplicates),
        rawMembers: _immutableMaps(payload.members),
        rawRecords: _immutableMaps(payload.records),
        rawPhotos: _immutableMaps(payload.photos),
        rawSettings: payload.settings == null
            ? null
            : Map.unmodifiable(payload.settings!),
        rawGridSettings: payload.gridSettings == null
            ? null
            : Map.unmodifiable(payload.gridSettings!),
      );
      _logger.phase(
        'backup.restore.prepare',
        LogPhase.success,
        context: {
          'members': payload.members.length,
          'records': payload.records.length,
          'photos': payload.photos.length,
          'duplicates': duplicates.length,
        },
      );
      return preview;
    } catch (_) {
      await _deleteKnownRestoreDir(tempDir);
      rethrow;
    }
  }

  void _validateZipEnvelope(Uint8List bytes) {
    const endOfCentralDirectorySize = 22;
    const maxCommentLength = 0xFFFF;
    if (bytes.length < endOfCentralDirectorySize) {
      throw const FormatException('올바른 백업 ZIP 구조가 아닙니다');
    }

    final lowestOffset =
        bytes.length - endOfCentralDirectorySize - maxCommentLength;
    final scanStart = lowestOffset < 0 ? 0 : lowestOffset;
    var directoryEndOffset = -1;
    for (
      var offset = bytes.length - endOfCentralDirectorySize;
      offset >= scanStart;
      offset--
    ) {
      if (_readUint32(bytes, offset) != 0x06054B50) continue;
      final commentLength = _readUint16(bytes, offset + 20);
      if (offset + endOfCentralDirectorySize + commentLength == bytes.length) {
        directoryEndOffset = offset;
        break;
      }
    }
    if (directoryEndOffset < 0) {
      throw const FormatException('올바른 백업 ZIP 구조가 아닙니다');
    }

    final diskNumber = _readUint16(bytes, directoryEndOffset + 4);
    final directoryDisk = _readUint16(bytes, directoryEndOffset + 6);
    final entriesOnDisk = _readUint16(bytes, directoryEndOffset + 8);
    final totalEntries = _readUint16(bytes, directoryEndOffset + 10);
    final directorySize = _readUint32(bytes, directoryEndOffset + 12);
    final directoryOffset = _readUint32(bytes, directoryEndOffset + 16);
    if (diskNumber != 0 ||
        directoryDisk != 0 ||
        entriesOnDisk != totalEntries ||
        totalEntries == 0 ||
        totalEntries == 0xFFFF ||
        directorySize == 0xFFFFFFFF ||
        directoryOffset == 0xFFFFFFFF ||
        totalEntries > _limits.maxEntryCount ||
        directoryOffset + directorySize > directoryEndOffset) {
      throw const FormatException('백업 ZIP 중앙 디렉터리가 허용 범위를 벗어납니다');
    }
  }

  int _readUint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _readUint32(Uint8List bytes, int offset) {
    return _readUint16(bytes, offset) | (_readUint16(bytes, offset + 2) << 16);
  }

  List<int> _verifiedArchiveContent(
    ArchiveFile entry, {
    required int maxBytes,
  }) {
    if (entry.compressionType != ArchiveFile.STORE &&
        entry.compressionType != ArchiveFile.DEFLATE) {
      throw const FormatException('지원하지 않는 ZIP 압축 방식입니다');
    }

    final output = _BoundedOutputStream(maxBytes);
    try {
      final rawContent = entry.rawContent;
      if (rawContent == null) {
        output.writeBytes(List<int>.from(entry.content as List<int>));
      } else if (entry.compressionType == ArchiveFile.DEFLATE) {
        Inflate.stream(rawContent, output);
      } else {
        output.writeInputStream(rawContent);
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('백업 ZIP 항목의 압축을 해제할 수 없습니다');
    }
    final content = output.takeBytes();
    if (content.length != entry.size) {
      throw const FormatException('백업 ZIP 항목 크기가 올바르지 않습니다');
    }
    final expectedCrc = entry.crc32;
    if (expectedCrc != null && getCrc32(content) != expectedCrc) {
      throw const FormatException('백업 ZIP 항목이 손상되었습니다');
    }
    return content;
  }

  // ---------------------------------------------------------------------
  // 복원 2단계: 파일 staging -> 설정/DB 적용 -> 이전 파일 정리
  // ---------------------------------------------------------------------

  @override
  Future<BackupOutcome> applyRestore(
    RestorePreview preview, {
    required RestoreMode mode,
  }) async {
    await _reconcileInterruptedRestore();
    _logger.phase(
      'backup.restore.apply',
      LogPhase.start,
      context: {'mode': mode.name},
    );

    final stagedAbsolutePaths = <String>{};
    var settingsApplied = false;
    var databaseCommitted = false;
    var journalPersisted = false;
    AppSettings? previousSettings;
    GridSettings? previousGrid;
    _RestoreJournal? restoreJournal;
    _RestorePlan? restorePlan;
    Directory? restoreDir;

    try {
      final tempDir = await _validatedRestoreDir(preview.tempDirPath);
      restoreDir = tempDir;
      final payload = _validatePreview(preview);
      if (payload.scope == BackupScope.member && mode == RestoreMode.replace) {
        throw const FormatException('회원별 백업은 기존 전체 데이터를 교체할 수 없습니다');
      }
      final db = await _db.database;
      previousSettings = await _settingsService.load();
      previousGrid = await _gridSettingsService.load();
      final plan = await _createRestorePlan(
        db,
        payload,
        mode,
        tempDir,
        stagedAbsolutePaths,
        currentStudioLogoPath: previousSettings.studioLogoPath,
      );
      restorePlan = plan;

      if (payload.scope == BackupScope.all && mode == RestoreMode.replace) {
        final restoredGrid = GridSettings.fromMap(payload.gridSettings!);
        final restoredSettings = _settingsForThisDevice(
          AppSettings.fromMap(payload.settings!),
          restoredGrid,
          previousSettings,
          restoredStudioLogoPath: plan.restoredStudioLogoPath,
        );
        final newStoredPaths = <String>{};
        for (final absolutePath in stagedAbsolutePaths) {
          newStoredPaths.add(await _storage.toStoredPath(absolutePath));
        }
        final journalOldStoredPaths = <String>{};
        for (final storedPath in plan.oldStoredPaths) {
          journalOldStoredPaths.add(await _storage.toStoredPath(storedPath));
        }
        final previousLogoPath = previousSettings.studioLogoPath;
        final journalPreviousSettings = previousLogoPath == null
            ? previousSettings
            : previousSettings.copyWith(
                studioLogoPath: await _storage.toStoredPath(previousLogoPath),
              );
        restoreJournal = _RestoreJournal(
          operationId: _uuid.v4(),
          previousSettings: journalPreviousSettings,
          previousGrid: previousGrid,
          newStoredPaths: newStoredPaths,
          oldStoredPaths: journalOldStoredPaths,
          restoreDirectoryName: p.basename(tempDir.path),
        );
        await _writeRestoreJournal(restoreJournal);
        journalPersisted = true;
        settingsApplied = true;

        await _gridSettingsService.save(restoredGrid);
        await _settingsService.save(restoredSettings);
        await _runRestoreInterruptionHook(
          RestoreInterruptionPoint.settingsAppliedBeforeDatabaseCommit,
        );
      }

      await db.transaction((txn) async {
        if (mode == RestoreMode.replace) {
          await txn.delete(AppDatabase.tableMembers);
        }
        for (final member in plan.members) {
          await txn.insert(
            AppDatabase.tableMembers,
            member,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        for (final record in plan.records) {
          await txn.insert(
            AppDatabase.tablePhotoRecords,
            record,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        for (final photo in plan.photos) {
          await txn.insert(
            AppDatabase.tableBodyPhotos,
            photo,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        final journal = restoreJournal;
        if (journal != null) {
          await txn.insert(
            AppDatabase.tableRestoreOperations,
            {'id': journal.operationId},
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      });
      databaseCommitted = true;

      if (restoreJournal != null) {
        await _runRestoreInterruptionHook(
          RestoreInterruptionPoint.databaseCommittedBeforeJournalCleanup,
        );
      }

      await _deleteOldFilesBestEffort(plan.oldStoredPaths);
      await _deleteKnownRestoreDir(tempDir);
      if (restoreJournal != null) {
        await _clearCommittedRestoreJournal(restoreJournal);
      }

      _logger.phase(
        'backup.restore.apply',
        LogPhase.success,
        context: {
          'members': plan.members.length,
          'records': plan.records.length,
          'photos': plan.photos.length,
        },
      );
      return BackupOutcome(
        success: true,
        memberCount: plan.members.length,
        recordCount: plan.records.length,
        photoCount: plan.photos.length,
      );
    } on RestoreProcessInterruptedException {
      _logger.warn('backup.restore.interrupted');
      rethrow;
    } catch (_) {
      if (databaseCommitted &&
          restoreJournal != null &&
          restorePlan != null &&
          restoreDir != null) {
        await _deleteOldFilesBestEffort(restorePlan.oldStoredPaths);
        await _deleteKnownRestoreDir(restoreDir);
        await _clearCommittedRestoreJournal(restoreJournal);
        _logger.phase(
          'backup.restore.apply',
          LogPhase.success,
          context: {
            'members': restorePlan.members.length,
            'records': restorePlan.records.length,
            'photos': restorePlan.photos.length,
          },
        );
        return BackupOutcome(
          success: true,
          memberCount: restorePlan.members.length,
          recordCount: restorePlan.records.length,
          photoCount: restorePlan.photos.length,
        );
      }

      var settingsRestored = true;
      if (settingsApplied && previousSettings != null && previousGrid != null) {
        settingsRestored = await _restoreSettingsBestEffort(
          previousSettings,
          previousGrid,
        );
      }
      await _deleteStagedFiles(stagedAbsolutePaths);
      await _discardRestoreBestEffort(preview);
      if (journalPersisted && settingsRestored) {
        await _deleteRestoreJournalBestEffort();
      }
      _logger.phase('backup.restore.apply', LogPhase.failure);
      return const BackupOutcome(
        success: false,
        error: '복원 검증 또는 적용에 실패했습니다. 기존 데이터는 변경되지 않았습니다.',
      );
    }
  }

  AppSettings _settingsForThisDevice(
    AppSettings restored,
    GridSettings restoredGrid,
    AppSettings current, {
    required String? restoredStudioLogoPath,
  }) {
    // secure storage의 PIN/비밀번호와 기기 생체 상태는 백업에 포함되지 않는다.
    // 현재 기기의 잠금 관련 값은 보존하고, 로고는 복원 과정에서 새 관리
    // 상대경로로 재배치한 값만 사용한다.
    return AppSettings(
      lockMode: current.lockMode,
      biometricEnabled: current.biometricEnabled,
      autoLockSeconds: current.autoLockSeconds,
      defaultGrid: restoredGrid,
      defaultExportOptions: restored.defaultExportOptions,
      studioName: restored.studioName,
      studioLogoPath: restoredStudioLogoPath,
      dataNoticeAcknowledged: restored.dataNoticeAcknowledged,
    );
  }

  Future<_RestorePlan> _createRestorePlan(
    Database db,
    _ValidatedPayload payload,
    RestoreMode mode,
    Directory tempDir,
    Set<String> stagedAbsolutePaths, {
    required String? currentStudioLogoPath,
  }) async {
    final existingMemberIds = <String>{};
    final existingRecordIds = <String>{};
    final existingPhotoIds = <String>{};
    final oldStoredPaths = <String>{};

    if (mode == RestoreMode.append) {
      existingMemberIds.addAll(
        (await db.query(
          AppDatabase.tableMembers,
          columns: ['id'],
        )).map((row) => row['id'] as String),
      );
      existingRecordIds.addAll(
        (await db.query(
          AppDatabase.tablePhotoRecords,
          columns: ['id'],
        )).map((row) => row['id'] as String),
      );
      existingPhotoIds.addAll(
        (await db.query(
          AppDatabase.tableBodyPhotos,
          columns: ['id'],
        )).map((row) => row['id'] as String),
      );
    } else {
      final memberRows = await db.query(
        AppDatabase.tableMembers,
        columns: ['avatar_path'],
      );
      final photoRows = await db.query(
        AppDatabase.tableBodyPhotos,
        columns: ['file_path'],
      );
      for (final row in memberRows) {
        final path = row['avatar_path'] as String?;
        if (path != null && path.isNotEmpty) oldStoredPaths.add(path);
      }
      for (final row in photoRows) {
        final path = row['file_path'] as String?;
        if (path != null && path.isNotEmpty) oldStoredPaths.add(path);
      }
    }
    if (payload.scope == BackupScope.all &&
        mode == RestoreMode.replace &&
        currentStudioLogoPath != null &&
        currentStudioLogoPath.isNotEmpty) {
      oldStoredPaths.add(currentStudioLogoPath);
    }

    final memberIdMap = _buildIndependentIdMap(
      payload.members.map((map) => map['id'] as String),
      existingMemberIds,
    );
    final recordIdMap = _buildIndependentIdMap(
      payload.records.map((map) => map['id'] as String),
      existingRecordIds,
    );
    final photoIdMap = _buildIndependentIdMap(
      payload.photos.map((map) => map['id'] as String),
      existingPhotoIds,
    );

    final members = <Map<String, Object?>>[];
    for (final raw in payload.members) {
      final map = Map<String, Object?>.from(raw);
      final originalId = map['id'] as String;
      final finalId = memberIdMap[originalId]!;
      map['id'] = finalId;
      final avatarRelativePath = map['avatar_path'] as String?;
      if (avatarRelativePath != null) {
        map['avatar_path'] = await _stageManagedFile(
          tempDir,
          avatarRelativePath,
          finalId,
          stagedAbsolutePaths,
        );
      }
      members.add(map);
    }

    final records = <Map<String, Object?>>[];
    final finalRecordOwner = <String, String>{};
    for (final raw in payload.records) {
      final map = Map<String, Object?>.from(raw);
      final originalId = map['id'] as String;
      final originalMemberId = map['member_id'] as String;
      final finalId = recordIdMap[originalId]!;
      final finalMemberId = memberIdMap[originalMemberId]!;
      map['id'] = finalId;
      map['member_id'] = finalMemberId;
      finalRecordOwner[finalId] = finalMemberId;
      records.add(map);
    }

    final photos = <Map<String, Object?>>[];
    for (final raw in payload.photos) {
      final map = Map<String, Object?>.from(raw);
      final originalId = map['id'] as String;
      final originalRecordId = map['record_id'] as String;
      final finalId = photoIdMap[originalId]!;
      final finalRecordId = recordIdMap[originalRecordId]!;
      final finalMemberId = finalRecordOwner[finalRecordId]!;
      final relativePath = map['file_path'] as String;
      map['id'] = finalId;
      map['record_id'] = finalRecordId;
      map['file_path'] = await _stageManagedFile(
        tempDir,
        relativePath,
        finalMemberId,
        stagedAbsolutePaths,
      );
      photos.add(map);
    }

    String? restoredStudioLogoPath;
    if (payload.scope == BackupScope.all && mode == RestoreMode.replace) {
      final archivedLogoPath = payload.settings!['studioLogoPath'] as String?;
      if (archivedLogoPath != null) {
        restoredStudioLogoPath = await _stageManagedFile(
          tempDir,
          archivedLogoPath,
          _studioAssetOwner,
          stagedAbsolutePaths,
        );
      }
    }

    return _RestorePlan(
      members: members,
      records: records,
      photos: photos,
      oldStoredPaths: oldStoredPaths,
      restoredStudioLogoPath: restoredStudioLogoPath,
    );
  }

  Map<String, String> _buildIndependentIdMap(
    Iterable<String> incomingIds,
    Set<String> existingIds,
  ) {
    final used = <String>{...existingIds};
    final result = <String, String>{};
    for (final originalId in incomingIds) {
      var finalId = originalId;
      if (!used.add(finalId)) {
        do {
          finalId = _uuid.v4();
        } while (!used.add(finalId));
      }
      result[originalId] = finalId;
    }
    return result;
  }

  Future<String> _stageManagedFile(
    Directory tempDir,
    String relativeSourcePath,
    String memberId,
    Set<String> stagedAbsolutePaths,
  ) async {
    final sourcePath = _pathInsideRestoreDir(tempDir.path, relativeSourcePath);
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FormatException('복원할 사진 파일이 누락되었습니다');
    }

    final memberDirectory = await _storage.memberDir(memberId);
    final sourceExtension = p.extension(relativeSourcePath);
    final safeExtension =
        sourceExtension.length <= 16 &&
            !sourceExtension.contains(RegExp(r'[/\\]'))
        ? sourceExtension
        : '';
    String destinationPath;
    do {
      destinationPath = p.join(
        memberDirectory.path,
        'restore_${_uuid.v4()}$safeExtension',
      );
    } while (await File(destinationPath).exists());

    stagedAbsolutePaths.add(destinationPath);
    final copier = _restoreFileCopier ?? _copyFileAtomically;
    await copier(sourcePath, destinationPath);
    final destination = File(destinationPath);
    if (!await destination.exists() ||
        await destination.length() != await source.length()) {
      throw const FileSystemException('복원 staging 파일 검증에 실패했습니다');
    }
    return _storage.toStoredPath(destinationPath);
  }

  Future<void> _copyFileAtomically(
    String sourcePath,
    String destinationPath,
  ) async {
    final partialPath = '$destinationPath.partial';
    final partial = File(partialPath);
    try {
      await File(sourcePath).copy(partialPath);
      await partial.rename(destinationPath);
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  Future<void> _deleteStagedFiles(Set<String> absolutePaths) async {
    for (final path in absolutePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        final partial = File('$path.partial');
        if (await partial.exists()) await partial.delete();
      } catch (_) {
        // 고유 staging 파일의 정리는 best effort다. DB에서는 참조하지 않는다.
      }
    }
  }

  Future<void> _deleteOldFilesBestEffort(Set<String> storedPaths) async {
    var failures = 0;
    for (final path in storedPaths) {
      try {
        await _storage.deleteFile(path);
      } catch (_) {
        failures += 1;
      }
    }
    if (failures > 0) {
      _logger.warn(
        'backup.restore.oldFileCleanup.failure',
        context: {'count': failures},
      );
    }
  }

  Future<bool> _restoreSettingsBestEffort(
    AppSettings previousSettings,
    GridSettings previousGrid,
  ) async {
    try {
      await _gridSettingsService.save(previousGrid);
      await _settingsService.save(previousSettings);
      return true;
    } catch (_) {
      _logger.warn('backup.restore.settingsRollback.failure');
      return false;
    }
  }

  Future<void> _runRestoreInterruptionHook(
    RestoreInterruptionPoint point,
  ) async {
    final hook = _restoreInterruptionHook;
    if (hook == null) return;
    try {
      await hook(point);
    } catch (_) {
      throw const RestoreProcessInterruptedException();
    }
  }

  Future<File> _restoreJournalFile() async {
    final root = await _tempRoot();
    return File(p.join(root.path, _restoreJournalFileName));
  }

  Future<void> _writeRestoreJournal(_RestoreJournal journal) async {
    final journalFile = await _restoreJournalFile();
    if (await journalFile.exists()) {
      throw StateError('이전 복원 작업 조정이 완료되지 않았습니다');
    }
    final partial = File('${journalFile.path}.partial');
    try {
      if (await partial.exists()) await partial.delete();
      await partial.writeAsString(jsonEncode(journal.toMap()), flush: true);
      await partial.rename(journalFile.path);
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  Future<_RestoreJournal?> _readRestoreJournal() async {
    final journalFile = await _restoreJournalFile();
    final partial = File('${journalFile.path}.partial');
    if (!await journalFile.exists()) {
      if (await partial.exists()) await partial.delete();
      return null;
    }
    if (await journalFile.length() > _limits.maxDataJsonBytes * 2) {
      throw StateError('복원 조정 정보의 크기가 올바르지 않습니다');
    }

    try {
      final value = jsonDecode(await journalFile.readAsString());
      if (value is! Map) {
        throw const FormatException('복원 조정 정보가 객체가 아닙니다');
      }
      final map = value.cast<String, dynamic>();
      _expectExactKeys(map, const {
        'version',
        'operationId',
        'previousSettings',
        'previousGrid',
        'newStoredPaths',
        'oldStoredPaths',
        'restoreDirectoryName',
      }, 'restoreJournal');
      if (map['version'] != _restoreJournalVersion) {
        throw const FormatException('복원 조정 정보 버전이 올바르지 않습니다');
      }
      final operationId = map['operationId'];
      if (operationId is! String ||
          !Uuid.isValidUUID(fromString: operationId)) {
        throw const FormatException('복원 조정 작업 ID가 올바르지 않습니다');
      }
      final restoreDirectoryName = map['restoreDirectoryName'];
      if (restoreDirectoryName is! String ||
          restoreDirectoryName.length > _limits.maxPathLength ||
          !restoreDirectoryName.startsWith(_restoreDirPrefix) ||
          p.basename(restoreDirectoryName) != restoreDirectoryName) {
        throw const FormatException('복원 조정 디렉터리가 올바르지 않습니다');
      }

      final rawSettings = map['previousSettings'];
      final rawGrid = map['previousGrid'];
      if (rawSettings is! Map || rawGrid is! Map) {
        throw const FormatException('복원 전 설정 스냅샷이 올바르지 않습니다');
      }
      final settingsMap = rawSettings.cast<String, dynamic>();
      final gridMap = rawGrid.cast<String, dynamic>();
      _validateLocalSettingsSnapshot(settingsMap);
      final previousSettings = AppSettings.fromMap(settingsMap);
      final previousGrid = _validateGridMap(gridMap);
      final logoPath = previousSettings.studioLogoPath;
      if (logoPath != null) {
        _validateJournalStoredPath(logoPath, 'previousStudioLogoPath');
      }

      return _RestoreJournal(
        operationId: operationId,
        previousSettings: previousSettings,
        previousGrid: previousGrid,
        newStoredPaths: _readJournalStoredPaths(
          map['newStoredPaths'],
          'newStoredPaths',
        ),
        oldStoredPaths: _readJournalStoredPaths(
          map['oldStoredPaths'],
          'oldStoredPaths',
        ),
        restoreDirectoryName: restoreDirectoryName,
      );
    } catch (_) {
      _logger.warn('backup.restore.journal.invalid');
      throw StateError('복원 조정 정보가 손상되어 자동 복구할 수 없습니다');
    }
  }

  void _validateLocalSettingsSnapshot(Map<String, dynamic> map) {
    _expectExactKeys(map, _settingsKeys, 'restoreJournal.settings');
    final lockMode = map['lockMode'];
    if (lockMode is! String ||
        !LockMode.values.any((value) => value.key == lockMode) ||
        map['biometricEnabled'] is! bool ||
        map['autoLockSeconds'] is! int ||
        !const {0, 15, 30, 60, 300}.contains(map['autoLockSeconds']) ||
        map['studioName'] is! String? ||
        map['studioLogoPath'] is! String? ||
        map['dataNoticeAcknowledged'] is! bool) {
      throw const FormatException('복원 전 앱 설정이 올바르지 않습니다');
    }
    final grid = map['defaultGrid'];
    final exportOptions = map['defaultExportOptions'];
    if (grid is! Map || exportOptions is! Map) {
      throw const FormatException('복원 전 앱 설정 구조가 올바르지 않습니다');
    }
    _validateGridMap(grid.cast<String, dynamic>());
    final exportMap = exportOptions.cast<String, dynamic>();
    _expectExactKeys(
      exportMap,
      _exportOptionKeys,
      'restoreJournal.exportOptions',
    );
    if (_exportOptionKeys.any((key) => exportMap[key] is! bool)) {
      throw const FormatException('복원 전 내보내기 설정이 올바르지 않습니다');
    }
  }

  Set<String> _readJournalStoredPaths(Object? value, String label) {
    if (value is! List || value.length > _limits.maxEntryCount + 1) {
      throw FormatException('복원 조정 $label 목록이 올바르지 않습니다');
    }
    final paths = <String>{};
    for (final rawPath in value) {
      if (rawPath is! String) {
        throw FormatException('복원 조정 $label 경로가 올바르지 않습니다');
      }
      final canonical = _validateJournalStoredPath(rawPath, label);
      if (!paths.add(canonical)) {
        throw FormatException('복원 조정 $label 경로가 올바르지 않습니다');
      }
    }
    return paths;
  }

  String _validateJournalStoredPath(String path, String label) {
    if (path.trim().isEmpty ||
        path.length > _limits.maxPathLength ||
        path.contains('\u0000') ||
        path.contains(r'\') ||
        p.posix.isAbsolute(path) ||
        p.windows.isAbsolute(path)) {
      throw FormatException('복원 조정 $label 경로가 올바르지 않습니다');
    }
    final normalized = p.posix.normalize(path);
    final segments = p.posix.split(normalized);
    if (normalized != path ||
        segments.length < 3 ||
        segments.first != PhotoStorageServiceImpl.rootDirName ||
        segments[1] == PhotoStorageServiceImpl.quarantineDirName ||
        segments[1] == PhotoStorageServiceImpl.stagingDirName ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) ||
        segments.last.length > 240) {
      throw FormatException('복원 조정 $label 경로가 올바르지 않습니다');
    }
    return normalized;
  }

  Future<void> _reconcileInterruptedRestore() async {
    final journal = await _readRestoreJournal();
    final db = await _db.database;
    if (journal == null) {
      // 저널을 먼저 지우고 marker를 지우는 정상 완료 순서 사이에서 앱이
      // 종료되었을 수 있다. 이 marker에는 무작위 작업 ID 외의 데이터가 없다.
      await db.delete(AppDatabase.tableRestoreOperations);
      return;
    }

    final committedRows = await db.query(
      AppDatabase.tableRestoreOperations,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [journal.operationId],
      limit: 1,
    );
    if (committedRows.isNotEmpty) {
      final restoreDir = await _journalRestoreDirectory(
        journal.restoreDirectoryName,
      );
      await _deleteOldFilesBestEffort(journal.oldStoredPaths);
      await _deleteKnownRestoreDir(restoreDir);
      await _clearCommittedRestoreJournal(journal);
      _logger.info('backup.restore.reconcile.committed');
      return;
    }

    final settingsRestored = await _restoreSettingsBestEffort(
      journal.previousSettings,
      journal.previousGrid,
    );
    if (!settingsRestored) {
      throw StateError('중단된 복원의 설정을 복구할 수 없습니다');
    }
    final restoreDir = await _journalRestoreDirectory(
      journal.restoreDirectoryName,
    );
    await _deleteStoredFilesBestEffort(journal.newStoredPaths);
    await _deleteKnownRestoreDir(restoreDir);
    final cleared = await _deleteRestoreJournalBestEffort();
    if (!cleared) {
      throw StateError('완료된 복원 조정 정보를 정리할 수 없습니다');
    }
    _logger.info('backup.restore.reconcile.rolledBack');
  }

  Future<Directory> _journalRestoreDirectory(String name) async {
    final root = await _tempRoot();
    final candidate = p.normalize(p.join(root.path, name));
    if (p.dirname(candidate) != p.normalize(root.path) ||
        p.basename(candidate) != name ||
        !name.startsWith(_restoreDirPrefix)) {
      throw StateError('복원 조정 디렉터리 경계가 올바르지 않습니다');
    }
    return Directory(candidate);
  }

  Future<void> _deleteStoredFilesBestEffort(Set<String> storedPaths) async {
    var failures = 0;
    for (final storedPath in storedPaths) {
      try {
        await _storage.deleteFile(storedPath);
      } catch (_) {
        failures += 1;
      }
    }
    if (failures > 0) {
      _logger.warn(
        'backup.restore.stagedFileCleanup.failure',
        context: {'count': failures},
      );
    }
  }

  Future<void> _clearCommittedRestoreJournal(_RestoreJournal journal) async {
    final cleared = await _deleteRestoreJournalBestEffort();
    if (!cleared) return;
    try {
      final db = await _db.database;
      await db.delete(
        AppDatabase.tableRestoreOperations,
        where: 'id = ?',
        whereArgs: [journal.operationId],
      );
    } catch (_) {
      // 저널이 먼저 제거되었으므로 다음 진입에서 비식별 marker만 정리한다.
    }
  }

  Future<bool> _deleteRestoreJournalBestEffort() async {
    try {
      final journalFile = await _restoreJournalFile();
      if (await journalFile.exists()) await journalFile.delete();
      final partial = File('${journalFile.path}.partial');
      if (await partial.exists()) await partial.delete();
      return true;
    } catch (_) {
      _logger.warn('backup.restore.journal.cleanup.failure');
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // 신뢰되지 않은 JSON/경로 검증
  // ---------------------------------------------------------------------

  _ValidatedPayload _validatePreview(RestorePreview preview) {
    return _validatePayload({
      'formatVersion': preview.formatVersion,
      'scope': preview.scope == BackupScope.member ? 'member' : 'all',
      'exportedAt': 0,
      'settings': preview.rawSettings,
      if (preview.formatVersion >= backupFormatVersion)
        'gridSettings': preview.rawGridSettings,
      'members': preview.rawMembers,
      'photoRecords': preview.rawRecords,
      'bodyPhotos': preview.rawPhotos,
    });
  }

  _ValidatedPayload _validatePayload(Map<String, dynamic> data) {
    final formatVersion = _requireInt(data, 'formatVersion', 'data');
    if (formatVersion != legacyBackupFormatVersion &&
        formatVersion != backupFormatVersion) {
      throw FormatException('지원하지 않는 백업 형식 버전입니다: $formatVersion');
    }
    _expectExactKeys(
      data,
      formatVersion >= backupFormatVersion ? _dataV2Keys : _dataV1Keys,
      'data',
    );
    _requireInt(data, 'exportedAt', 'data');

    final scopeValue = _requireString(data, 'scope', 'data');
    final scope = switch (scopeValue) {
      'all' => BackupScope.all,
      'member' => BackupScope.member,
      _ => throw const FormatException('백업 범위가 올바르지 않습니다'),
    };

    final rawMembers = _requireMapList(data['members'], 'members');
    final rawRecords = _requireMapList(data['photoRecords'], 'photoRecords');
    final rawPhotos = _requireMapList(data['bodyPhotos'], 'bodyPhotos');
    if (scope == BackupScope.member && rawMembers.length != 1) {
      throw const FormatException('회원별 백업에는 정확히 한 회원만 포함되어야 합니다');
    }

    final memberIds = <String>{};
    final members = <Map<String, dynamic>>[];
    final expectedFiles = <String>{};
    for (final raw in rawMembers) {
      _expectExactKeys(raw, _memberKeys, 'member');
      final id = _requireUuid(raw, 'id', 'member');
      if (!memberIds.add(id)) {
        throw const FormatException('백업에 중복 회원 ID가 있습니다');
      }
      final name = _requireString(raw, 'name', 'member');
      if (name.trim().isEmpty) {
        throw const FormatException('회원 이름이 비어 있습니다');
      }
      final gender = _requireString(raw, 'gender', 'member');
      if (!Gender.values.any((value) => value.key == gender)) {
        throw const FormatException('회원 성별 값이 올바르지 않습니다');
      }
      _requireNullableString(raw, 'birth', 'member');
      _requireNullableString(raw, 'contact', 'member');
      _requireNullableString(raw, 'memo', 'member');
      _requireInt(raw, 'created_at', 'member');
      _requireInt(raw, 'updated_at', 'member');
      final avatarPath = _requireNullableString(raw, 'avatar_path', 'member');
      if (avatarPath != null) {
        _validateOwnedArchiveFile(avatarPath, root: 'avatars', ownerId: id);
        if (!expectedFiles.add(avatarPath)) {
          throw const FormatException('백업 파일 경로가 중복 참조됩니다');
        }
      }
      members.add(Map<String, dynamic>.from(raw));
    }

    final recordIds = <String>{};
    final recordOwners = <String, String>{};
    final records = <Map<String, dynamic>>[];
    for (final raw in rawRecords) {
      _expectExactKeys(raw, _recordKeys, 'photoRecord');
      final id = _requireUuid(raw, 'id', 'photoRecord');
      if (!recordIds.add(id)) {
        throw const FormatException('백업에 중복 촬영 기록 ID가 있습니다');
      }
      final ownerId = _requireUuid(raw, 'member_id', 'photoRecord');
      if (!memberIds.contains(ownerId)) {
        throw const FormatException('촬영 기록의 소속 회원이 백업에 없습니다');
      }
      _requireInt(raw, 'shot_at', 'photoRecord');
      _requireNullableString(raw, 'memo', 'photoRecord');
      _requireInt(raw, 'created_at', 'photoRecord');
      _requireInt(raw, 'updated_at', 'photoRecord');
      recordOwners[id] = ownerId;
      records.add(Map<String, dynamic>.from(raw));
    }

    final photoIds = <String>{};
    final photos = <Map<String, dynamic>>[];
    for (final raw in rawPhotos) {
      _expectExactKeys(raw, _photoKeys, 'bodyPhoto');
      final id = _requireUuid(raw, 'id', 'bodyPhoto');
      if (!photoIds.add(id)) {
        throw const FormatException('백업에 중복 사진 ID가 있습니다');
      }
      final recordId = _requireUuid(raw, 'record_id', 'bodyPhoto');
      final ownerId = recordOwners[recordId];
      if (ownerId == null) {
        throw const FormatException('사진의 촬영 기록이 백업에 없습니다');
      }
      final filePath = _requireString(raw, 'file_path', 'bodyPhoto');
      _validateOwnedArchiveFile(filePath, root: 'photos', ownerId: ownerId);
      if (!expectedFiles.add(filePath)) {
        throw const FormatException('백업 파일 경로가 중복 참조됩니다');
      }
      final direction = _requireString(raw, 'direction', 'bodyPhoto');
      if (!BodyDirection.values.any((value) => value.key == direction)) {
        throw const FormatException('사진 방향 값이 올바르지 않습니다');
      }
      final width = _requireInt(raw, 'width', 'bodyPhoto');
      final height = _requireInt(raw, 'height', 'bodyPhoto');
      final orientation = _requireInt(raw, 'orientation', 'bodyPhoto');
      if (width < 0 || height < 0 || orientation < 1 || orientation > 8) {
        throw const FormatException('사진 메타데이터 값이 올바르지 않습니다');
      }
      final gridJson = _requireNullableString(
        raw,
        'grid_settings',
        'bodyPhoto',
      );
      if (gridJson != null) {
        try {
          _validateGridSettings(GridSettings.fromJson(gridJson));
        } catch (_) {
          throw const FormatException('사진 격자 설정이 올바르지 않습니다');
        }
      }
      _requireNullableString(raw, 'memo', 'bodyPhoto');
      _requireInt(raw, 'created_at', 'bodyPhoto');
      photos.add(Map<String, dynamic>.from(raw));
    }

    Map<String, dynamic>? settings;
    Map<String, dynamic>? gridSettings;
    final rawSettingsValue = data['settings'];
    if (scope == BackupScope.all) {
      if (rawSettingsValue is! Map) {
        throw const FormatException('전체 백업에 앱 설정이 없습니다');
      }
      final settingsInput = rawSettingsValue.cast<String, dynamic>();
      settings = _validateSettingsMap(
        settingsInput,
        expectedFiles: expectedFiles,
        includesManagedLogo: formatVersion >= backupFormatVersion,
      );

      if (formatVersion >= backupFormatVersion) {
        final gridValue = data['gridSettings'];
        if (gridValue is! Map) {
          throw const FormatException('전체 백업에 격자 설정이 없습니다');
        }
        gridSettings = _validateGridMap(
          gridValue.cast<String, dynamic>(),
        ).toMap();
      } else {
        gridSettings = Map<String, dynamic>.from(
          settings['defaultGrid'] as Map<String, dynamic>,
        );
      }
    } else {
      if (rawSettingsValue != null ||
          (formatVersion >= backupFormatVersion &&
              data['gridSettings'] != null)) {
        throw const FormatException('회원별 백업에는 전역 설정을 포함할 수 없습니다');
      }
    }

    return _ValidatedPayload(
      formatVersion: formatVersion,
      scope: scope,
      members: members,
      records: records,
      photos: photos,
      settings: settings,
      gridSettings: gridSettings,
      expectedFilePaths: expectedFiles,
    );
  }

  Map<String, dynamic> _validateSettingsMap(
    Map<String, dynamic> map, {
    required Set<String> expectedFiles,
    required bool includesManagedLogo,
  }) {
    _expectExactKeys(map, _settingsKeys, 'settings');
    final lockMode = _requireString(map, 'lockMode', 'settings');
    if (!LockMode.values.any((value) => value.key == lockMode)) {
      throw const FormatException('앱 잠금 설정이 올바르지 않습니다');
    }
    _requireBool(map, 'biometricEnabled', 'settings');
    final autoLockSeconds = _requireInt(map, 'autoLockSeconds', 'settings');
    if (autoLockSeconds < 0) {
      throw const FormatException('자동 잠금 시간이 올바르지 않습니다');
    }

    final gridValue = map['defaultGrid'];
    if (gridValue is! Map) {
      throw const FormatException('기본 격자 설정이 올바르지 않습니다');
    }
    final grid = _validateGridMap(gridValue.cast<String, dynamic>());

    final optionsValue = map['defaultExportOptions'];
    if (optionsValue is! Map) {
      throw const FormatException('기본 내보내기 설정이 올바르지 않습니다');
    }
    final optionsMap = optionsValue.cast<String, dynamic>();
    _expectExactKeys(optionsMap, _exportOptionKeys, 'exportOptions');
    for (final key in _exportOptionKeys) {
      _requireBool(optionsMap, key, 'exportOptions');
    }

    _requireNullableString(map, 'studioName', 'settings');
    final rawStudioLogoPath = _requireNullableString(
      map,
      'studioLogoPath',
      'settings',
    );
    String? studioLogoPath;
    if (includesManagedLogo && rawStudioLogoPath != null) {
      _validateStudioArchiveFile(rawStudioLogoPath);
      if (!expectedFiles.add(rawStudioLogoPath)) {
        throw const FormatException('백업 파일 경로가 중복 참조됩니다');
      }
      studioLogoPath = rawStudioLogoPath;
    }
    _requireBool(map, 'dataNoticeAcknowledged', 'settings');
    final settings = AppSettings.fromMap(map);
    return AppSettings(
      lockMode: settings.lockMode,
      biometricEnabled: settings.biometricEnabled,
      autoLockSeconds: settings.autoLockSeconds,
      defaultGrid: grid,
      defaultExportOptions: settings.defaultExportOptions,
      studioName: settings.studioName,
      // v1의 기기 로컬 경로는 폐기하고 v2의 검증된 ZIP 상대경로만 유지한다.
      studioLogoPath: studioLogoPath,
      dataNoticeAcknowledged: settings.dataNoticeAcknowledged,
    ).toMap();
  }

  void _validateStudioArchiveFile(String path) {
    final normalized = _validateArchivePath(path);
    final segments = p.posix.split(normalized);
    if (segments.length != 3 ||
        segments[0] != 'assets' ||
        segments[1] != 'studio' ||
        segments[2].isEmpty) {
      throw const FormatException('스튜디오 로고 백업 경로가 올바르지 않습니다');
    }
  }

  GridSettings _validateGridMap(Map<String, dynamic> map) {
    _expectExactKeys(map, _gridKeys, 'gridSettings');
    _requireBool(map, 'visible', 'gridSettings');
    _requireNumber(map, 'opacity', 'gridSettings');
    _requireNumber(map, 'lineWidth', 'gridSettings');
    _requireNumber(map, 'spacing', 'gridSettings');
    _requireInt(map, 'colorValue', 'gridSettings');
    final grid = GridSettings.fromMap(map);
    _validateGridSettings(grid);
    return grid;
  }

  void _validateGridSettings(GridSettings grid) {
    if (!grid.opacity.isFinite ||
        grid.opacity < 0 ||
        grid.opacity > 1 ||
        !grid.lineWidth.isFinite ||
        grid.lineWidth <= 0 ||
        !grid.spacing.isFinite ||
        grid.spacing <= 0 ||
        grid.colorValue < 0 ||
        grid.colorValue > 0xFFFFFFFF) {
      throw const FormatException('격자 설정 값이 허용 범위를 벗어납니다');
    }
  }

  void _validateOwnedArchiveFile(
    String path, {
    required String root,
    required String ownerId,
  }) {
    final normalized = _validateArchivePath(path);
    final segments = p.posix.split(normalized);
    if (segments.length != 3 ||
        segments[0] != root ||
        segments[1] != ownerId ||
        segments[2].isEmpty) {
      throw const FormatException('백업 파일의 소유 경로가 올바르지 않습니다');
    }
  }

  String _validateArchivePath(String path) {
    if (path.isEmpty ||
        path.length > _limits.maxPathLength ||
        path.contains('\u0000') ||
        path.contains(r'\') ||
        p.posix.isAbsolute(path) ||
        p.windows.isAbsolute(path)) {
      throw const FormatException('백업 파일 경로가 올바르지 않습니다');
    }
    final normalized = p.posix.normalize(path);
    final segments = p.posix.split(normalized);
    if (normalized != path ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) ||
        segments.last.length > 240) {
      throw const FormatException('백업 파일 경로가 허용 범위를 벗어납니다');
    }
    return normalized;
  }

  String _pathInsideRestoreDir(String root, String archivePath) {
    final validated = _validateArchivePath(archivePath);
    final candidate = p.normalize(
      p.join(root, p.joinAll(p.posix.split(validated))),
    );
    if (!p.isWithin(root, candidate)) {
      throw const FormatException('복원 임시 저장소 경계를 벗어납니다');
    }
    return candidate;
  }

  void _expectExactKeys(
    Map<String, dynamic> map,
    Set<String> expected,
    String label,
  ) {
    final actual = map.keys.toSet();
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw FormatException('$label 필드 구성이 올바르지 않습니다');
    }
  }

  List<Map<String, dynamic>> _requireMapList(Object? value, String label) {
    if (value is! List) {
      throw FormatException('$label 목록이 올바르지 않습니다');
    }
    return value.map((item) {
      if (item is! Map) {
        throw FormatException('$label 항목이 올바르지 않습니다');
      }
      return item.cast<String, dynamic>();
    }).toList();
  }

  String _requireUuid(Map<String, dynamic> map, String key, String label) {
    final value = _requireString(map, key, label);
    if (!Uuid.isValidUUID(fromString: value)) {
      throw FormatException('$label.$key UUID가 올바르지 않습니다');
    }
    return value;
  }

  String _requireString(Map<String, dynamic> map, String key, String label) {
    final value = map[key];
    if (value is! String || value.length > _limits.maxDataJsonBytes) {
      throw FormatException('$label.$key 문자열이 올바르지 않습니다');
    }
    return value;
  }

  String? _requireNullableString(
    Map<String, dynamic> map,
    String key,
    String label,
  ) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String || value.length > _limits.maxDataJsonBytes) {
      throw FormatException('$label.$key 문자열이 올바르지 않습니다');
    }
    return value;
  }

  int _requireInt(Map<String, dynamic> map, String key, String label) {
    final value = map[key];
    if (value is! int) {
      throw FormatException('$label.$key 정수가 올바르지 않습니다');
    }
    return value;
  }

  num _requireNumber(Map<String, dynamic> map, String key, String label) {
    final value = map[key];
    if (value is! num) {
      throw FormatException('$label.$key 숫자가 올바르지 않습니다');
    }
    return value;
  }

  bool _requireBool(Map<String, dynamic> map, String key, String label) {
    final value = map[key];
    if (value is! bool) {
      throw FormatException('$label.$key 불리언이 올바르지 않습니다');
    }
    return value;
  }

  List<Map<String, dynamic>> _immutableMaps(List<Map<String, dynamic>> source) {
    return List.unmodifiable(
      source.map((map) => Map<String, dynamic>.unmodifiable(map)),
    );
  }

  // ---------------------------------------------------------------------
  // 안전한 임시 디렉터리 수명 관리
  // ---------------------------------------------------------------------

  @override
  Future<void> cleanupStaleRestoreDirectories() async {
    await _reconcileInterruptedRestore();
    final root = await _tempRoot();
    await for (final entity in root.list(followLinks: false)) {
      final normalizedPath = p.normalize(p.absolute(entity.path));
      if (p.dirname(normalizedPath) != p.normalize(p.absolute(root.path)) ||
          !p.basename(normalizedPath).startsWith(_restoreDirPrefix)) {
        continue;
      }
      final type = await FileSystemEntity.type(
        normalizedPath,
        followLinks: false,
      );
      if (type == FileSystemEntityType.directory) {
        await _deleteKnownRestoreDir(Directory(normalizedPath));
      }
    }
  }

  @override
  Future<void> discardRestore(RestorePreview preview) async {
    await _reconcileInterruptedRestore();
    final dir = await _validatedRestoreDir(preview.tempDirPath);
    await _deleteKnownRestoreDir(dir);
  }

  Future<Directory> _validatedRestoreDir(String path) async {
    final root = await _tempRoot();
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final normalizedPath = p.normalize(p.absolute(path));
    if (!p.isWithin(normalizedRoot, normalizedPath) ||
        p.dirname(normalizedPath) != normalizedRoot ||
        !p.basename(normalizedPath).startsWith(_restoreDirPrefix)) {
      throw const FormatException('복원 임시 디렉터리 경계가 올바르지 않습니다');
    }
    final dir = Directory(normalizedPath);
    if (!await dir.exists()) {
      throw const FormatException('복원 임시 데이터가 없습니다');
    }
    return dir;
  }

  Future<void> _deleteKnownRestoreDir(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 임시 데이터 정리는 best effort다.
    }
  }

  Future<void> _discardRestoreBestEffort(RestorePreview preview) async {
    try {
      final dir = await _validatedRestoreDir(preview.tempDirPath);
      await _deleteKnownRestoreDir(dir);
    } catch (_) {
      // 검증되지 않은 경로는 절대 삭제하지 않는다.
    }
  }
}

class _ValidatedPayload {
  final int formatVersion;
  final BackupScope scope;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> photos;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? gridSettings;
  final Set<String> expectedFilePaths;

  const _ValidatedPayload({
    required this.formatVersion,
    required this.scope,
    required this.members,
    required this.records,
    required this.photos,
    required this.settings,
    required this.gridSettings,
    required this.expectedFilePaths,
  });
}

class _RestorePlan {
  final List<Map<String, Object?>> members;
  final List<Map<String, Object?>> records;
  final List<Map<String, Object?>> photos;
  final Set<String> oldStoredPaths;
  final String? restoredStudioLogoPath;

  const _RestorePlan({
    required this.members,
    required this.records,
    required this.photos,
    required this.oldStoredPaths,
    required this.restoredStudioLogoPath,
  });
}

class _RestoreJournal {
  final String operationId;
  final AppSettings previousSettings;
  final GridSettings previousGrid;
  final Set<String> newStoredPaths;
  final Set<String> oldStoredPaths;
  final String restoreDirectoryName;

  const _RestoreJournal({
    required this.operationId,
    required this.previousSettings,
    required this.previousGrid,
    required this.newStoredPaths,
    required this.oldStoredPaths,
    required this.restoreDirectoryName,
  });

  Map<String, Object?> toMap() => {
    'version': BackupServiceImpl._restoreJournalVersion,
    'operationId': operationId,
    'previousSettings': previousSettings.toMap(),
    'previousGrid': previousGrid.toMap(),
    'newStoredPaths': newStoredPaths.toList(growable: false)..sort(),
    'oldStoredPaths': oldStoredPaths.toList(growable: false)..sort(),
    'restoreDirectoryName': restoreDirectoryName,
  };
}

/// ZIP 헤더의 해제 크기가 조작되어 있어도 실제 해제 바이트가 상한을 넘는
/// 순간 중단한다.
class _BoundedOutputStream implements OutputStreamBase {
  final int maxBytes;
  Uint8List _buffer = Uint8List(0);

  @override
  int length = 0;

  _BoundedOutputStream(this.maxBytes);

  Uint8List takeBytes() =>
      Uint8List.fromList(Uint8List.view(_buffer.buffer, 0, length));

  void _reserve(int count) {
    if (count < 0 || length + count > maxBytes) {
      throw const FormatException('백업 ZIP 항목의 실제 해제 크기가 허용량을 초과했습니다');
    }
    final requiredLength = length + count;
    if (requiredLength <= _buffer.length) return;
    var nextLength = _buffer.isEmpty ? requiredLength : _buffer.length * 2;
    if (nextLength < requiredLength) nextLength = requiredLength;
    if (nextLength > maxBytes) nextLength = maxBytes;
    final expanded = Uint8List(nextLength);
    expanded.setRange(0, length, _buffer);
    _buffer = expanded;
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _reserve(1);
    _buffer[length++] = value & 0xff;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    if (count > bytes.length) {
      throw const FormatException('백업 ZIP 항목의 바이트 길이가 올바르지 않습니다');
    }
    _reserve(count);
    _buffer.setRange(length, length + count, bytes);
    length += count;
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    final count = stream.length;
    _reserve(count);
    _buffer.setRange(
      length,
      length + count,
      stream.readBytes(count).toUint8List(),
    );
    length += count;
  }

  /// archive의 Inflate 구현이 LZ77 거리 참조를 위해 동적으로 호출한다.
  List<int> subset(int start, [int? end]) {
    var resolvedStart = start < 0 ? length + start : start;
    var resolvedEnd = end ?? length;
    if (resolvedEnd < 0) resolvedEnd = length + resolvedEnd;
    if (resolvedStart < 0 ||
        resolvedEnd < resolvedStart ||
        resolvedEnd > length) {
      throw const FormatException('백업 ZIP 압축 참조 범위가 올바르지 않습니다');
    }
    return Uint8List.view(
      _buffer.buffer,
      resolvedStart,
      resolvedEnd - resolvedStart,
    );
  }

  @override
  void writeUint16(int value) {
    writeBytes([value & 0xff, (value >> 8) & 0xff]);
  }

  @override
  void writeUint32(int value) {
    writeBytes([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  @override
  void writeUint64(int value) {
    writeBytes([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
      (value >> 32) & 0xff,
      (value >> 40) & 0xff,
      (value >> 48) & 0xff,
      (value >> 56) & 0xff,
    ]);
  }
}
