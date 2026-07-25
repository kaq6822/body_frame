import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app_logger.dart';

/// DB 변경 전에 파일을 임시 격리했다가 성공 시 폐기하거나 실패 시 복구하기
/// 위한 핸들. 경로는 서비스 구현 내부에서 검증한 절대경로다.
class StorageQuarantine {
  final String originalPath;
  final String quarantinedPath;
  final String journalPath;
  final bool isDirectory;

  const StorageQuarantine({
    required this.originalPath,
    required this.quarantinedPath,
    required this.journalPath,
    required this.isDirectory,
  });
}

/// 격리 crash 지점 회귀 테스트에서만 사용하는 관찰 지점.
enum StorageQuarantinePhase {
  journalPublished,
  payloadMoved,
  payloadRestored,
  payloadDiscarded,
}

typedef StorageQuarantinePhaseHook =
    Future<void> Function(
      StorageQuarantine quarantine,
      StorageQuarantinePhase phase,
    );

/// 미완료 격리가 DB 변경 전/후 어느 쪽에서 중단됐는지 판단할 읽기 전용 스냅샷.
///
/// 파일 payload는 현재 DB의 avatar/photo 경로가 원래 경로를 참조할 때만
/// 복구하고, 회원 디렉터리는 회원 행이 아직 존재할 때만 복구한다.
class StorageQuarantineReferences {
  final Set<String> storedFilePaths;
  final Set<String> memberIds;

  StorageQuarantineReferences({
    required Iterable<String> storedFilePaths,
    required Iterable<String> memberIds,
  }) : storedFilePaths = Set.unmodifiable(storedFilePaths),
       memberIds = Set.unmodifiable(memberIds);
}

typedef StorageQuarantineReferencesLoader =
    Future<StorageQuarantineReferences> Function();

/// 사진 파일 저장 서비스.
///
/// - 원본 사진은 앱 전용 저장소(문서 디렉터리 하위 photos/{memberId}/)에 저장.
/// - 사용자가 명시적으로 내보내기 전까지 일반 갤러리에 노출하지 않는다.
/// - 원본 이미지는 절대 자동 변형/크롭하지 않는다. 바이트를 그대로 복사한다.
///
/// 이 서비스는 파일 I/O만 담당하고 DB 기록은 리포지토리가 담당한다.
abstract class PhotoStorageService {
  /// DB 참조 스냅샷과 durable journal을 대조해 이전 실행의 미완료 격리를
  /// 복구/폐기한다. 같은 서비스 인스턴스에서는 한 번만 실행된다.
  Future<void> reconcilePendingQuarantines();

  /// 회원 사진 디렉터리(photos/{memberId})의 절대 경로를 반환하고 없으면 생성한다.
  Future<Directory> memberDir(String memberId);

  /// [sourcePath]의 원본 파일을 회원 저장소로 **무변형 복사**하고
  /// 저장된 파일의 절대 경로를 반환한다.
  ///
  /// DB에 기록할 때는 반드시 [toStoredPath]로 앱 저장소 상대경로로 변환한다.
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  });

  /// 원본 바이트를 회원 저장소에 그대로 기록하고 경로를 반환한다.
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  });

  /// DB에 저장된 상대경로를 현재 앱 컨테이너의 절대경로로 해석한다.
  ///
  /// 이전 버전이 기록한 절대경로도 `photos/` 이하 부분만 사용해 현재
  /// 컨테이너로 안전하게 재배치한다.
  Future<String> resolvePath(String storedPath);

  /// 앱 사진 저장소의 절대경로를 DB에 기록할 상대경로로 변환한다.
  Future<String> toStoredPath(String filePath);

  /// 단일 사진 파일 삭제. 존재하지 않으면 무시한다.
  Future<void> deleteFile(String filePath);

  /// 회원 사진 디렉터리 전체 삭제(회원 삭제 시 연쇄 파일 정리).
  Future<void> deleteMemberDir(String memberId);

  /// 파일/회원 디렉터리를 같은 저장소의 격리 영역으로 원자적으로 이동한다.
  /// 대상이 없으면 null을 반환한다.
  Future<StorageQuarantine?> quarantineFile(String filePath);
  Future<StorageQuarantine?> quarantineMemberDir(String memberId);

  /// 격리한 대상을 원래 위치로 되돌리거나 영구 폐기한다.
  Future<void> restoreQuarantine(StorageQuarantine quarantine);
  Future<void> discardQuarantine(StorageQuarantine quarantine);
}

class PhotoStorageServiceImpl implements PhotoStorageService {
  static const String rootDirName = 'photos';
  static const String quarantineDirName = '.quarantine';
  static const String quarantineJournalDirName = 'journals';
  static const String quarantinePayloadDirName = 'payloads';
  static const String stagingDirName = '.staging';
  static const int _quarantineJournalVersion = 1;

  final AppLogger _logger;
  final StorageQuarantinePhaseHook? _quarantinePhaseHook;
  final StorageQuarantineReferencesLoader? _quarantineReferencesLoader;

  /// 저장 루트 재정의(테스트에서 임시 디렉터리 주입). null이면 문서 디렉터리.
  final String? _overrideRoot;

  Future<void>? _recoveryFuture;

  PhotoStorageServiceImpl({
    AppLogger? logger,
    String? rootPath,
    StorageQuarantinePhaseHook? quarantinePhaseHook,
    StorageQuarantineReferencesLoader? quarantineReferencesLoader,
  }) : _logger = logger ?? AppLogger.instance,
       _overrideRoot = rootPath,
       _quarantinePhaseHook = quarantinePhaseHook,
       _quarantineReferencesLoader = quarantineReferencesLoader;

  Future<Directory> _baseRootRaw() async {
    final base =
        _overrideRoot ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.normalize(p.absolute(base)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _photosRootRaw() async {
    final base = await _baseRootRaw();
    final dir = Directory(p.join(base.path, rootDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _quarantineRootRaw() async {
    final photosRoot = await _photosRootRaw();
    final dir = Directory(p.join(photosRoot.path, quarantineDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _stagingRootRaw() async {
    final photosRoot = await _photosRootRaw();
    final dir = Directory(p.join(photosRoot.path, stagingDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _baseRoot() async {
    final base = await _baseRootRaw();
    await _ensureRecovered();
    return base;
  }

  Future<Directory> _photosRoot() async {
    final root = await _photosRootRaw();
    await _ensureRecovered();
    return root;
  }

  Future<Directory> _quarantineRoot() async {
    final root = await _quarantineRootRaw();
    await _ensureRecovered();
    return root;
  }

  Future<void> _ensureRecovered() {
    return _recoveryFuture ??= _recoverPendingQuarantines();
  }

  @override
  Future<void> reconcilePendingQuarantines() => _ensureRecovered();

  @override
  Future<Directory> memberDir(String memberId) async {
    _validatePathSegment(memberId, field: 'memberId');
    final root = await _photosRoot();
    final dir = Directory(_pathWithin(root.path, memberId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> saveOriginal({
    required String memberId,
    required String sourcePath,
    String? fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('원본 파일을 찾을 수 없음', sourcePath);
    }
    final dir = await memberDir(memberId);
    final ext = p.extension(sourcePath);
    final name = fileName ?? _uniqueName(ext);
    _validatePathSegment(name, field: 'fileName');
    final dest = await _stageAndCommitFile(p.join(dir.path, name), (
      stagingPath,
    ) async {
      final staged = await source.copy(stagingPath);
      final handle = await staged.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (await staged.length() != await source.length()) {
        throw const FileSystemException('원본 파일 복사 크기가 일치하지 않습니다.');
      }
    });
    _logger.info('photo.save', context: {'memberId': memberId});
    return dest;
  }

  @override
  Future<String> saveBytes({
    required String memberId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final dir = await memberDir(memberId);
    _validatePathSegment(fileName, field: 'fileName');
    final dest = await _stageAndCommitFile(
      p.join(dir.path, fileName),
      (stagingPath) =>
          File(stagingPath).writeAsBytes(bytes, flush: true).then((_) {}),
    );
    _logger.info('photo.save', context: {'memberId': memberId});
    return dest;
  }

  @override
  Future<String> resolvePath(String storedPath) async {
    if (storedPath.trim().isEmpty) {
      throw const FormatException('사진 경로가 비어 있습니다.');
    }

    final base = await _baseRoot();
    final photosRoot = await _photosRoot();
    final portable = storedPath.replaceAll(r'\', '/');
    String relative;

    if (p.posix.isAbsolute(portable) || p.windows.isAbsolute(storedPath)) {
      // 이전 버전이 저장한 절대경로에서는 컨테이너 앞부분을 신뢰하지 않고
      // `photos/` 이하만 현재 앱 저장소에 붙인다.
      final marker = '/$rootDirName/';
      final markerIndex = portable.lastIndexOf(marker);
      if (markerIndex < 0) {
        throw const FormatException('앱 사진 저장소 밖의 경로입니다.');
      }
      relative = portable.substring(markerIndex + 1);
    } else {
      relative = portable;
    }

    final normalizedRelative = p.posix.normalize(relative);
    final segments = p.posix.split(normalizedRelative);
    if (relative != normalizedRelative ||
        normalizedRelative == rootDirName ||
        !normalizedRelative.startsWith('$rootDirName/') ||
        segments.length < 3 ||
        segments[1] == quarantineDirName ||
        segments[1] == stagingDirName ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const FormatException('허용되지 않는 사진 상대경로입니다.');
    }

    final platformRelative = p.joinAll(p.posix.split(normalizedRelative));
    final absolute = p.normalize(p.join(base.path, platformRelative));
    if (!p.isWithin(photosRoot.path, absolute)) {
      throw const FormatException('사진 경로가 저장소 경계를 벗어납니다.');
    }
    return absolute;
  }

  @override
  Future<String> toStoredPath(String filePath) async {
    final base = await _baseRoot();
    final absolute = await resolvePath(filePath);
    final relative = p.relative(absolute, from: base.path);
    return p.posix.joinAll(p.split(relative));
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final resolved = await resolvePath(filePath);
    final file = File(resolved);
    if (await file.exists()) {
      await file.delete();
      _logger.info('photo.delete');
    }
  }

  @override
  Future<void> deleteMemberDir(String memberId) async {
    _validatePathSegment(memberId, field: 'memberId');
    final root = await _photosRoot();
    final dir = Directory(_pathWithin(root.path, memberId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      _logger.info('photo.deleteMemberDir', context: {'memberId': memberId});
    }
  }

  @override
  Future<StorageQuarantine?> quarantineFile(String filePath) async {
    final originalPath = await resolvePath(filePath);
    final original = File(originalPath);
    if (!await original.exists()) return null;
    final quarantine = await _createQuarantine(
      originalPath,
      isDirectory: false,
    );
    await _publishJournal(quarantine);
    await _notifyPhase(quarantine, StorageQuarantinePhase.journalPublished);
    await original.rename(quarantine.quarantinedPath);
    await _notifyPhase(quarantine, StorageQuarantinePhase.payloadMoved);
    return quarantine;
  }

  @override
  Future<StorageQuarantine?> quarantineMemberDir(String memberId) async {
    _validatePathSegment(memberId, field: 'memberId');
    final photosRoot = await _photosRoot();
    final originalPath = _pathWithin(photosRoot.path, memberId);
    final original = Directory(originalPath);
    if (!await original.exists()) return null;
    final quarantine = await _createQuarantine(originalPath, isDirectory: true);
    await _publishJournal(quarantine);
    await _notifyPhase(quarantine, StorageQuarantinePhase.journalPublished);
    await original.rename(quarantine.quarantinedPath);
    await _notifyPhase(quarantine, StorageQuarantinePhase.payloadMoved);
    return quarantine;
  }

  @override
  Future<void> restoreQuarantine(StorageQuarantine quarantine) async {
    final photosRoot = await _photosRoot();
    _validateQuarantineHandle(photosRoot.path, quarantine);
    if (quarantine.isDirectory) {
      final source = Directory(quarantine.quarantinedPath);
      if (!await source.exists()) {
        if (await Directory(quarantine.originalPath).exists()) {
          await _deleteJournal(quarantine.journalPath);
          return;
        }
        throw StateError('복구할 격리 디렉터리가 없습니다.');
      }
      if (await FileSystemEntity.type(
            quarantine.originalPath,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('격리 디렉터리를 복구할 위치가 이미 존재합니다.');
      }
      await Directory(
        p.dirname(quarantine.originalPath),
      ).create(recursive: true);
      await source.rename(quarantine.originalPath);
    } else {
      final source = File(quarantine.quarantinedPath);
      if (!await source.exists()) {
        if (await File(quarantine.originalPath).exists()) {
          await _deleteJournal(quarantine.journalPath);
          return;
        }
        throw StateError('복구할 격리 파일이 없습니다.');
      }
      if (await FileSystemEntity.type(
            quarantine.originalPath,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('격리 파일을 복구할 위치가 이미 존재합니다.');
      }
      await File(quarantine.originalPath).parent.create(recursive: true);
      await source.rename(quarantine.originalPath);
    }
    await _notifyPhase(quarantine, StorageQuarantinePhase.payloadRestored);
    await _deleteJournal(quarantine.journalPath);
  }

  @override
  Future<void> discardQuarantine(StorageQuarantine quarantine) async {
    final photosRoot = await _photosRoot();
    _validateQuarantineHandle(photosRoot.path, quarantine);
    if (quarantine.isDirectory) {
      final directory = Directory(quarantine.quarantinedPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } else {
      final file = File(quarantine.quarantinedPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _notifyPhase(quarantine, StorageQuarantinePhase.payloadDiscarded);
    await _deleteJournal(quarantine.journalPath);
  }

  Future<StorageQuarantine> _createQuarantine(
    String originalPath, {
    required bool isDirectory,
  }) async {
    final photosRoot = await _photosRoot();
    _assertOriginalAbsolute(photosRoot.path, originalPath);
    final quarantineRoot = await _quarantineRoot();
    final payloadRoot = Directory(
      p.join(quarantineRoot.path, quarantinePayloadDirName),
    );
    final journalRoot = Directory(
      p.join(quarantineRoot.path, quarantineJournalDirName),
    );
    await payloadRoot.create(recursive: true);
    await journalRoot.create(recursive: true);
    final id = const Uuid().v4();
    return StorageQuarantine(
      originalPath: p.normalize(originalPath),
      quarantinedPath: p.join(payloadRoot.path, id),
      journalPath: p.join(journalRoot.path, '$id.json'),
      isDirectory: isDirectory,
    );
  }

  Future<void> _publishJournal(StorageQuarantine quarantine) async {
    final photosRoot = await _photosRoot();
    _validateQuarantineHandle(photosRoot.path, quarantine);
    final relativeOriginal = p.posix.joinAll(
      p.split(p.relative(quarantine.originalPath, from: photosRoot.path)),
    );
    final payloadName = p.basename(quarantine.quarantinedPath);
    final journal = <String, Object>{
      'version': _quarantineJournalVersion,
      'id': payloadName,
      'originalRelativePath': relativeOriginal,
      'payloadName': payloadName,
      'kind': quarantine.isDirectory ? 'directory' : 'file',
    };
    final published = File(quarantine.journalPath);
    final pending = File('${quarantine.journalPath}.pending');
    try {
      await pending.writeAsString(jsonEncode(journal), flush: true);
      await pending.rename(published.path);
    } catch (_) {
      if (await pending.exists()) {
        await pending.delete();
      }
      rethrow;
    }
  }

  Future<void> _recoverPendingQuarantines() async {
    final photosRoot = await _photosRootRaw();
    final quarantineRoot = await _quarantineRootRaw();
    await _cleanupStaleStagingFiles();
    final journalRoot = Directory(
      p.join(quarantineRoot.path, quarantineJournalDirName),
    );
    final journalFiles = <File>[];
    if (await journalRoot.exists()) {
      await for (final entity in journalRoot.list(followLinks: false)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file &&
            p.basename(entity.path).endsWith('.json')) {
          journalFiles.add(File(entity.path));
        } else if (type == FileSystemEntityType.file &&
            p.basename(entity.path).endsWith('.json.pending')) {
          // 저널 게시 전에 중단된 경우 payload 이동은 시작되지 않았다.
          await File(entity.path).delete();
        }
      }
    }
    journalFiles.sort((left, right) => left.path.compareTo(right.path));

    Object? firstFailure;
    var restoredCount = 0;
    var discardedCount = 0;
    StorageQuarantineReferences? references;
    for (final journalFile in journalFiles) {
      try {
        final quarantine = await _readJournal(
          photosRoot.path,
          quarantineRoot.path,
          journalFile,
        );
        final originalType = await FileSystemEntity.type(
          quarantine.originalPath,
          followLinks: false,
        );
        final payloadType = await FileSystemEntity.type(
          quarantine.quarantinedPath,
          followLinks: false,
        );
        final expectedType = quarantine.isDirectory
            ? FileSystemEntityType.directory
            : FileSystemEntityType.file;

        if (payloadType == expectedType) {
          if (originalType != FileSystemEntityType.notFound) {
            throw StateError('격리 복구 대상과 원래 경로가 동시에 존재합니다.');
          }
          final snapshotLoader = _quarantineReferencesLoader;
          if (snapshotLoader == null) {
            throw StateError('격리 복구에 필요한 DB 참조 스냅샷이 없습니다.');
          }
          references ??= await snapshotLoader();
          final shouldRestore = _isReferencedByDatabase(
            photosRoot.path,
            quarantine,
            references,
          );
          if (shouldRestore) {
            if (quarantine.isDirectory) {
              await Directory(
                p.dirname(quarantine.originalPath),
              ).create(recursive: true);
              await Directory(
                quarantine.quarantinedPath,
              ).rename(quarantine.originalPath);
            } else {
              await File(
                quarantine.originalPath,
              ).parent.create(recursive: true);
              await File(
                quarantine.quarantinedPath,
              ).rename(quarantine.originalPath);
            }
            restoredCount += 1;
          } else {
            if (quarantine.isDirectory) {
              await Directory(
                quarantine.quarantinedPath,
              ).delete(recursive: true);
            } else {
              await File(quarantine.quarantinedPath).delete();
            }
            discardedCount += 1;
          }
          await _deleteJournal(journalFile.path);
          continue;
        }

        if (payloadType != FileSystemEntityType.notFound) {
          throw StateError('격리 payload 형식이 저널과 일치하지 않습니다.');
        }
        if (originalType != FileSystemEntityType.notFound &&
            originalType != expectedType) {
          throw StateError('원래 경로 형식이 격리 저널과 일치하지 않습니다.');
        }
        // journal 게시 전/restore 후/discard 후 중단된 상태다. 이동할
        // payload가 없으므로 원래 파일은 그대로 두고 완료된 journal만 지운다.
        await _deleteJournal(journalFile.path);
      } catch (error) {
        firstFailure ??= error;
        _logger.warn('storage.quarantine.recovery.failure');
      }
    }
    if (restoredCount > 0) {
      _logger.info(
        'storage.quarantine.recovery',
        context: {'count': restoredCount},
      );
    }
    if (discardedCount > 0) {
      _logger.info(
        'storage.quarantine.reconcile.discard',
        context: {'count': discardedCount},
      );
    }
    final snapshotLoader = _quarantineReferencesLoader;
    if (snapshotLoader != null) {
      references ??= await snapshotLoader();
      final orphanCount = await _discardUnreferencedManagedFiles(
        photosRoot.path,
        references,
      );
      if (orphanCount > 0) {
        _logger.info(
          'storage.orphan.reconcile.discard',
          context: {'count': orphanCount},
        );
      }
    }
    if (firstFailure != null) {
      throw StateError(
        '미완료 사진 격리를 안전하게 복구하지 못했습니다: '
        '${firstFailure.runtimeType}',
      );
    }
  }

  Future<StorageQuarantine> _readJournal(
    String photosRoot,
    String quarantineRoot,
    File journalFile,
  ) async {
    final normalizedJournal = p.normalize(p.absolute(journalFile.path));
    final expectedJournalRoot = p.normalize(
      p.join(quarantineRoot, quarantineJournalDirName),
    );
    if (p.dirname(normalizedJournal) != expectedJournalRoot) {
      throw const FormatException('격리 저널 경로가 올바르지 않습니다.');
    }
    final decoded = jsonDecode(await journalFile.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _quarantineJournalVersion ||
        decoded['id'] is! String ||
        decoded['payloadName'] is! String ||
        decoded['originalRelativePath'] is! String ||
        decoded['kind'] is! String) {
      throw const FormatException('격리 저널 형식이 올바르지 않습니다.');
    }
    final id = decoded['id'] as String;
    final payloadName = decoded['payloadName'] as String;
    final relativeOriginal = decoded['originalRelativePath'] as String;
    final kind = decoded['kind'] as String;
    _validatePathSegment(id, field: 'journal.id');
    if (payloadName != id ||
        p.basename(normalizedJournal) != '$id.json' ||
        (kind != 'file' && kind != 'directory')) {
      throw const FormatException('격리 저널 식별자가 올바르지 않습니다.');
    }
    final originalSegments = p.posix.split(relativeOriginal);
    if ((kind == 'directory' && originalSegments.length != 1) ||
        (kind == 'file' && originalSegments.length < 2)) {
      throw const FormatException('격리 저널 대상 종류가 원래 경로와 일치하지 않습니다.');
    }
    final originalPath = _managedAbsoluteFromRelative(
      photosRoot,
      relativeOriginal,
    );
    final quarantine = StorageQuarantine(
      originalPath: originalPath,
      quarantinedPath: p.join(
        quarantineRoot,
        quarantinePayloadDirName,
        payloadName,
      ),
      journalPath: normalizedJournal,
      isDirectory: kind == 'directory',
    );
    _validateQuarantineHandle(photosRoot, quarantine);
    return quarantine;
  }

  bool _isReferencedByDatabase(
    String photosRoot,
    StorageQuarantine quarantine,
    StorageQuarantineReferences references,
  ) {
    final relative = p.posix.joinAll(
      p.split(p.relative(quarantine.originalPath, from: photosRoot)),
    );
    if (quarantine.isDirectory) {
      return references.memberIds.contains(relative);
    }
    final storedPath = p.posix.join(rootDirName, relative);
    return references.storedFilePaths.any(
      (candidate) => _portableStoredPath(candidate) == storedPath,
    );
  }

  String? _portableStoredPath(String value) {
    final portable = value.replaceAll(r'\', '/');
    if (p.posix.isAbsolute(portable) || p.windows.isAbsolute(value)) {
      final marker = '/$rootDirName/';
      final markerIndex = portable.lastIndexOf(marker);
      if (markerIndex < 0) return null;
      return p.posix.normalize(portable.substring(markerIndex + 1));
    }
    return p.posix.normalize(portable);
  }

  String _managedAbsoluteFromRelative(String photosRoot, String relativePath) {
    final portable = relativePath.replaceAll(r'\', '/');
    final normalized = p.posix.normalize(portable);
    final segments = p.posix.split(normalized);
    if (portable != normalized ||
        p.posix.isAbsolute(normalized) ||
        segments.isEmpty ||
        segments.first == quarantineDirName ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const FormatException('격리 저널의 원래 경로가 올바르지 않습니다.');
    }
    final absolute = p.normalize(p.joinAll([photosRoot, ...segments]));
    _assertOriginalAbsolute(photosRoot, absolute);
    return absolute;
  }

  Future<void> _notifyPhase(
    StorageQuarantine quarantine,
    StorageQuarantinePhase phase,
  ) async {
    await _quarantinePhaseHook?.call(quarantine, phase);
  }

  Future<void> _deleteJournal(String journalPath) async {
    final journal = File(journalPath);
    if (await journal.exists()) {
      await journal.delete();
    }
  }

  String _uniqueName(String ext) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$ts${ext.isEmpty ? '.jpg' : ext}';
  }

  void _validatePathSegment(String value, {required String field}) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized != value ||
        normalized == '.' ||
        normalized == '..' ||
        normalized == quarantineDirName ||
        normalized == stagingDirName ||
        p.isAbsolute(normalized) ||
        p.windows.isAbsolute(normalized) ||
        normalized.contains('/') ||
        normalized.contains(r'\') ||
        p.basename(normalized) != normalized) {
      throw ArgumentError.value(value, field, '안전한 단일 경로 조각이어야 합니다.');
    }
  }

  Future<String> _stageAndCommitFile(
    String desiredPath,
    Future<void> Function(String stagingPath) writer,
  ) async {
    final stagingRoot = await _stagingRootRaw();
    final staging = File(
      p.join(stagingRoot.path, '${const Uuid().v4()}.partial'),
    );
    try {
      await writer(staging.path);
      if (!await staging.exists()) {
        throw const FileSystemException('완성된 staging 파일이 없습니다.');
      }
      final destination = _nonClobberingPath(desiredPath);
      await staging.rename(destination);
      return destination;
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete();
      }
      rethrow;
    }
  }

  Future<void> _cleanupStaleStagingFiles() async {
    final stagingRoot = await _stagingRootRaw();
    await for (final entity in stagingRoot.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        _logger.warn('storage.staging.cleanup.failure');
      }
    }
  }

  Future<int> _discardUnreferencedManagedFiles(
    String photosRoot,
    StorageQuarantineReferences references,
  ) async {
    final referenced = references.storedFilePaths
        .map(_portableStoredPath)
        .whereType<String>()
        .toSet();
    var discarded = 0;
    await for (final entity in Directory(
      photosRoot,
    ).list(recursive: true, followLinks: false)) {
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: photosRoot)),
      );
      final segments = p.posix.split(relative);
      if (segments.isEmpty ||
          segments.first == quarantineDirName ||
          segments.first == stagingDirName) {
        continue;
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.link) {
        continue;
      }
      final storedPath = p.posix.join(rootDirName, relative);
      if (type == FileSystemEntityType.file &&
          referenced.contains(storedPath)) {
        continue;
      }
      try {
        await entity.delete();
        discarded += 1;
      } catch (_) {
        _logger.warn('storage.orphan.cleanup.failure');
      }
    }
    return discarded;
  }

  String _pathWithin(String root, String segment) {
    final candidate = p.normalize(p.join(root, segment));
    if (!p.isWithin(root, candidate)) {
      throw const FormatException('사진 저장소 경계를 벗어난 경로입니다.');
    }
    return candidate;
  }

  void _assertOriginalAbsolute(String photosRoot, String candidate) {
    final normalized = p.normalize(candidate);
    final quarantineRoot = p.normalize(p.join(photosRoot, quarantineDirName));
    if (!p.isWithin(photosRoot, normalized) ||
        normalized == p.normalize(photosRoot) ||
        normalized == quarantineRoot ||
        p.isWithin(quarantineRoot, normalized)) {
      throw const FormatException('사진 저장소 경계를 벗어난 경로입니다.');
    }
  }

  void _validateQuarantineHandle(
    String photosRoot,
    StorageQuarantine quarantine,
  ) {
    _assertOriginalAbsolute(photosRoot, quarantine.originalPath);
    final quarantineRoot = p.normalize(p.join(photosRoot, quarantineDirName));
    final payloadRoot = p.normalize(
      p.join(quarantineRoot, quarantinePayloadDirName),
    );
    final journalRoot = p.normalize(
      p.join(quarantineRoot, quarantineJournalDirName),
    );
    final payloadPath = p.normalize(quarantine.quarantinedPath);
    final journalPath = p.normalize(quarantine.journalPath);
    final id = p.basename(payloadPath);
    _validatePathSegment(id, field: 'quarantine.id');
    if (p.dirname(payloadPath) != payloadRoot ||
        p.dirname(journalPath) != journalRoot ||
        p.basename(journalPath) != '$id.json') {
      throw const FormatException('격리 저장소 핸들이 올바르지 않습니다.');
    }
  }

  /// 동일 파일명이 있으면 '(1)', '(2)' 접미사를 붙여 충돌을 피한다.
  String _nonClobberingPath(String desired) {
    if (!File(desired).existsSync()) return desired;
    final dir = p.dirname(desired);
    final base = p.basenameWithoutExtension(desired);
    final ext = p.extension(desired);
    var i = 1;
    while (true) {
      final candidate = p.join(dir, '$base($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
      i++;
    }
  }
}
