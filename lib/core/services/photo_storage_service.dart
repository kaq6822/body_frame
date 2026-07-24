import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

/// 사진 파일 저장 서비스.
///
/// MVP.md 9.1 / 19장 원칙:
/// - 원본 사진은 앱 전용 저장소(문서 디렉터리 하위 photos/{memberId}/)에 저장.
/// - 사용자가 명시적으로 내보내기 전까지 일반 갤러리에 노출하지 않는다.
/// - 원본 이미지는 절대 자동 변형/크롭하지 않는다. 바이트를 그대로 복사한다.
///
/// 이 서비스는 파일 I/O만 담당하고 DB 기록은 리포지토리가 담당한다.
abstract class PhotoStorageService {
  /// 회원 사진 디렉터리(photos/{memberId})의 절대 경로를 반환하고 없으면 생성한다.
  Future<Directory> memberDir(String memberId);

  /// [sourcePath]의 원본 파일을 회원 저장소로 **무변형 복사**하고
  /// 저장된 파일의 절대 경로를 반환한다.
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

  /// 단일 사진 파일 삭제. 존재하지 않으면 무시한다.
  Future<void> deleteFile(String filePath);

  /// 회원 사진 디렉터리 전체 삭제(회원 삭제 시 연쇄 파일 정리).
  Future<void> deleteMemberDir(String memberId);
}

class PhotoStorageServiceImpl implements PhotoStorageService {
  static const String rootDirName = 'photos';

  final AppLogger _logger;

  /// 저장 루트 재정의(테스트에서 임시 디렉터리 주입). null이면 문서 디렉터리.
  final String? _overrideRoot;

  PhotoStorageServiceImpl({AppLogger? logger, String? rootPath})
      : _logger = logger ?? AppLogger.instance,
        _overrideRoot = rootPath;

  Future<Directory> _photosRoot() async {
    final base = _overrideRoot ??
        (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(base, rootDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<Directory> memberDir(String memberId) async {
    final root = await _photosRoot();
    final dir = Directory(p.join(root.path, memberId));
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
    final dest = _nonClobberingPath(p.join(dir.path, name));
    // MVP.md 9.2: 동일 파일명이 존재해도 덮어쓰지 않는다.
    // MVP.md 15장: 바이트 무변형 복사.
    await source.copy(dest);
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
    final dest = _nonClobberingPath(p.join(dir.path, fileName));
    await File(dest).writeAsBytes(bytes, flush: true);
    _logger.info('photo.save', context: {'memberId': memberId});
    return dest;
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      _logger.info('photo.delete');
    }
  }

  @override
  Future<void> deleteMemberDir(String memberId) async {
    final root = await _photosRoot();
    final dir = Directory(p.join(root.path, memberId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      _logger.info('photo.deleteMemberDir', context: {'memberId': memberId});
    }
  }

  String _uniqueName(String ext) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$ts${ext.isEmpty ? '.jpg' : ext}';
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
