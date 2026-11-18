import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'app_logger.dart';
import 'photo_storage_service.dart';

/// 레슨 동영상 파일 저장 서비스.
///
/// [PhotoStorageService]와 같은 불변식을 따르되 경로 공간을 나눈다. 사진 경로
/// 검증(`photos/`)을 느슨하게 만들지 않으려고 별도 서비스로 둔다.
///
/// - 원본은 `videos/{yyyyMM}/{uuid}.{원본 확장자}`에 **무변형 복사**한다.
///   트랜스코딩·압축·자르기는 하지 않는다.
/// - 큰 파일이라 메모리에 올리지 않고 파일 복사로 staging에 쓴 뒤 rename으로
///   확정한다. staging은 사진과 같은 `photos/.staging`을 써서, 앱 시작 시
///   [PhotoStorageService.cleanupStagingLeftovers]가 함께 정리한다.
abstract class VideoStorageService {
  /// [sourcePath]를 저장소로 복사하고 저장된 파일의 절대경로를 반환한다.
  Future<String> saveOriginal({
    required DateTime capturedAt,
    required String sourcePath,
  });

  /// DB의 상대경로를 현재 앱 컨테이너의 절대경로로 해석한다. 앞부분을 신뢰하지
  /// 않고 `videos/` 이하만 현재 저장소에 다시 붙인다.
  Future<String> resolvePath(String storedPath);

  /// 앱 동영상 저장소의 경로를 DB에 기록할 상대경로로 바꾼다.
  Future<String> toStoredPath(String filePath);

  /// 단일 동영상 파일 삭제. 없으면 무시한다.
  Future<void> deleteFile(String filePath);
}

class VideoStorageServiceImpl implements VideoStorageService {
  static const String rootDirName = 'videos';

  final AppLogger _logger;
  final String? _overrideRoot;

  VideoStorageServiceImpl({AppLogger? logger, String? rootPath})
    : _logger = logger ?? AppLogger.instance,
      _overrideRoot = rootPath;

  Future<Directory> _ensure(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _baseRoot() async {
    final base =
        _overrideRoot ?? (await getApplicationDocumentsDirectory()).path;
    return _ensure(p.normalize(p.absolute(base)));
  }

  Future<Directory> _videosRoot() async =>
      _ensure(p.join((await _baseRoot()).path, rootDirName));

  Future<Directory> _stagingRoot() async => _ensure(
    p.join(
      (await _baseRoot()).path,
      PhotoStorageServiceImpl.rootDirName,
      PhotoStorageServiceImpl.stagingDirName,
    ),
  );

  @override
  Future<String> saveOriginal({
    required DateTime capturedAt,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('원본 동영상을 찾을 수 없음', sourcePath);
    }
    final bucket = PhotoStorageServiceImpl.bucketName(capturedAt);
    final dir = await _ensure(p.join((await _videosRoot()).path, bucket));
    final ext = p.extension(sourcePath).toLowerCase();
    final name = '${const Uuid().v4()}${_safeExtension(ext)}';
    final staging = File(
      p.join((await _stagingRoot()).path, '${const Uuid().v4()}.partial'),
    );
    try {
      // File.copy는 플랫폼 파일 복사라 바이트를 메모리에 올리지 않는다.
      final staged = await source.copy(staging.path);
      final handle = await staged.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (await staged.length() != await source.length()) {
        throw const FileSystemException('동영상 복사 크기가 일치하지 않습니다.');
      }
      final destination = p.join(dir.path, name);
      await staged.rename(destination);
      _logger.info('video.save');
      return destination;
    } catch (_) {
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  /// 확장자는 원본을 따르되 경로 구분자나 이상한 값은 버린다.
  String _safeExtension(String ext) =>
      RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '.mp4';

  @override
  Future<String> resolvePath(String storedPath) async {
    if (storedPath.trim().isEmpty) {
      throw const FormatException('동영상 경로가 비어 있습니다.');
    }
    final base = await _baseRoot();
    final root = await _videosRoot();
    final portable = storedPath.replaceAll(r'\', '/');
    String relative;
    if (p.posix.isAbsolute(portable) || p.windows.isAbsolute(storedPath)) {
      const marker = '/$rootDirName/';
      final index = portable.lastIndexOf(marker);
      if (index < 0) throw const FormatException('앱 동영상 저장소 밖의 경로입니다.');
      relative = portable.substring(index + 1);
    } else {
      relative = portable;
    }
    final normalized = p.posix.normalize(relative);
    final segments = p.posix.split(normalized);
    if (relative != normalized ||
        segments.length != 3 ||
        segments.first != rootDirName ||
        !RegExp(r'^\d{6}$').hasMatch(segments[1]) ||
        segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException('허용되지 않는 동영상 상대경로입니다.');
    }
    final absolute = p.normalize(p.join(base.path, p.joinAll(segments)));
    if (!p.isWithin(root.path, absolute)) {
      throw const FormatException('동영상 경로가 저장소 경계를 벗어납니다.');
    }
    return absolute;
  }

  @override
  Future<String> toStoredPath(String filePath) async {
    final base = await _baseRoot();
    final absolute = await resolvePath(filePath);
    return p.posix.joinAll(p.split(p.relative(absolute, from: base.path)));
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(await resolvePath(filePath));
    if (await file.exists()) {
      await file.delete();
      _logger.info('video.delete');
    }
  }
}
