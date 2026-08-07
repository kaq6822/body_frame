import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app_logger.dart';

/// 사진 파일 저장 서비스.
///
/// - 원본 사진은 앱 전용 저장소(문서 디렉터리 하위 photos/{yyyyMM}/)에 저장한다.
///   촬영월로 나누는 이유는 한 디렉터리에 파일이 무한정 쌓이지 않게 하기 위함이다.
/// - 원본 이미지는 절대 자동 변형/크롭하지 않는다. 바이트를 그대로 복사한다.
/// - 쓰기는 staging 파일에 먼저 기록한 뒤 rename으로 확정해, 중간에 실패해도
///   반쯤 쓰인 파일이 저장소에 남지 않게 한다.
///
/// 이 서비스는 파일 I/O만 담당하고 DB 기록은 리포지토리가 담당한다.
abstract class PhotoStorageService {
  /// 촬영월 디렉터리(photos/{yyyyMM})의 절대 경로를 반환하고 없으면 생성한다.
  Future<Directory> bucketDir(DateTime shotAt);

  /// [sourcePath]의 원본 파일을 저장소로 **무변형 복사**하고
  /// 저장된 파일의 절대 경로를 반환한다.
  ///
  /// DB에 기록할 때는 반드시 [toStoredPath]로 앱 저장소 상대경로로 변환한다.
  Future<String> saveOriginal({
    required DateTime shotAt,
    required String sourcePath,
    String? fileName,
  });

  /// 원본 바이트를 저장소에 그대로 기록하고 경로를 반환한다.
  Future<String> saveBytes({
    required DateTime shotAt,
    required List<int> bytes,
    required String fileName,
  });

  /// DB에 저장된 상대경로를 현재 앱 컨테이너의 절대경로로 해석한다.
  ///
  /// 앱 컨테이너 경로는 업데이트나 기기 이전으로 바뀔 수 있으므로 저장된 값의
  /// 앞부분을 신뢰하지 않고 `photos/` 이하만 현재 저장소에 다시 붙인다.
  Future<String> resolvePath(String storedPath);

  /// 앱 사진 저장소의 절대경로를 DB에 기록할 상대경로로 변환한다.
  Future<String> toStoredPath(String filePath);

  /// 단일 사진 파일 삭제. 존재하지 않으면 무시한다.
  Future<void> deleteFile(String filePath);
}

class PhotoStorageServiceImpl implements PhotoStorageService {
  static const String rootDirName = 'photos';
  static const String stagingDirName = '.staging';

  final AppLogger _logger;

  /// 저장 루트 재정의(테스트에서 임시 디렉터리 주입). null이면 문서 디렉터리.
  final String? _overrideRoot;

  PhotoStorageServiceImpl({AppLogger? logger, String? rootPath})
    : _logger = logger ?? AppLogger.instance,
      _overrideRoot = rootPath;

  Future<Directory> _baseRoot() async {
    final base =
        _overrideRoot ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.normalize(p.absolute(base)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _photosRoot() async {
    final base = await _baseRoot();
    final dir = Directory(p.join(base.path, rootDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _stagingRoot() async {
    final photosRoot = await _photosRoot();
    final dir = Directory(p.join(photosRoot.path, stagingDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 촬영월 버킷 이름. 예: 2026년 8월 → `202608`.
  static String bucketName(DateTime shotAt) {
    final month = shotAt.month.toString().padLeft(2, '0');
    return '${shotAt.year}$month';
  }

  @override
  Future<Directory> bucketDir(DateTime shotAt) async {
    final name = bucketName(shotAt);
    _validatePathSegment(name, field: 'bucket');
    final root = await _photosRoot();
    final dir = Directory(_pathWithin(root.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> saveOriginal({
    required DateTime shotAt,
    required String sourcePath,
    String? fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('원본 파일을 찾을 수 없음', sourcePath);
    }
    final dir = await bucketDir(shotAt);
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
    _logger.info('photo.save');
    return dest;
  }

  @override
  Future<String> saveBytes({
    required DateTime shotAt,
    required List<int> bytes,
    required String fileName,
  }) async {
    final dir = await bucketDir(shotAt);
    _validatePathSegment(fileName, field: 'fileName');
    final dest = await _stageAndCommitFile(
      p.join(dir.path, fileName),
      (stagingPath) =>
          File(stagingPath).writeAsBytes(bytes, flush: true).then((_) {}),
    );
    _logger.info('photo.save');
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
      // 앱 컨테이너 경로는 바뀔 수 있으므로 앞부분을 신뢰하지 않고
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

  /// staging 파일에 먼저 쓰고 rename으로 확정한다. 실패하면 staging만 지우고
  /// 목적지에는 아무것도 남기지 않는다.
  Future<String> _stageAndCommitFile(
    String desiredPath,
    Future<void> Function(String stagingPath) writer,
  ) async {
    final stagingRoot = await _stagingRoot();
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
        normalized == stagingDirName ||
        p.isAbsolute(normalized) ||
        p.windows.isAbsolute(normalized) ||
        normalized.contains('/') ||
        normalized.contains(r'\')) {
      throw FormatException('$field 값이 파일 경로로 사용할 수 없습니다.');
    }
  }

  String _pathWithin(String root, String segment) {
    final candidate = p.normalize(p.join(root, segment));
    if (!p.isWithin(root, candidate)) {
      throw const FormatException('사진 저장소 경계를 벗어난 경로입니다.');
    }
    return candidate;
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
