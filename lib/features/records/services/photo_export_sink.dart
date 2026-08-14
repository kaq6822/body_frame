import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/export_album.dart';

typedef PhotoShareDirectoryProvider = Future<Directory> Function();
typedef PhotoShareInvoker =
    Future<void> Function(List<XFile> files, {Rect? sharePositionOrigin});

/// 단일 사진을 사진 보관함으로 내보내거나 외부로 공유하는 플랫폼 경계.
///
/// 사진 보관함 저장(gal)과 OS 공유 시트(share_plus)를 감싸는 얇은 추상화.
/// 두 플러그인 모두 네이티브 구현이 있어야 동작하는 플랫폼 채널을 타므로,
/// 화면이 직접 부르면 위젯 테스트에서 성공 경로를 한 번도 통과할 수 없다.
/// 테스트에서는 이 provider를 fake로 바꿔 원본과 파생 PNG 중 어떤 경로가
/// 선택됐는지 플러그인 호출 없이 검증한다.
abstract class PhotoExportSink {
  Future<void> saveOriginalFile(String sourcePath, {required String name});

  Future<void> savePng(Uint8List bytes, {required String name});

  /// 원본 파일을 그대로 공유한다(변형 없이 저장소의 파일을 넘긴다).
  Future<void> shareOriginalFile(
    String sourcePath, {
    Rect? sharePositionOrigin,
  });

  /// 격자를 합성한 파생 PNG를 공유한다.
  ///
  /// 파생 이미지는 공유 시트에 넘기기 위한 임시 산출물이므로 앱 안에 남기지
  /// 않는다. 임시 파일 생성과 정리는 이 경계 안에서 끝낸다.
  Future<void> sharePng(
    Uint8List bytes, {
    required String name,
    Rect? sharePositionOrigin,
  });
}

class PhotoExportSinkImpl implements PhotoExportSink {
  /// 공유용 파생 이미지를 두는 전용 디렉터리 이름.
  static const String shareDirName = 'photo_share';

  final PhotoShareDirectoryProvider _supportDirectoryProvider;
  final PhotoShareInvoker _shareInvoker;

  PhotoExportSinkImpl({
    PhotoShareDirectoryProvider? supportDirectoryProvider,
    PhotoShareInvoker? shareInvoker,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _shareInvoker =
           shareInvoker ??
           ((files, {sharePositionOrigin}) async {
             await Share.shareXFiles(
               files,
               sharePositionOrigin: sharePositionOrigin,
             );
           });

  Future<void> _ensureAccess() async {
    final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
    if (!hasAccess) {
      throw Exception('사진 보관함 접근 권한이 거부되었습니다.');
    }
  }

  @override
  Future<void> saveOriginalFile(
    String sourcePath, {
    required String name,
  }) async {
    await _ensureAccess();
    final source = File(sourcePath);
    final extension = p.extension(sourcePath);
    final tempPath = p.join(
      (await getTemporaryDirectory()).path,
      '${name}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    final tempFile = await source.copy(tempPath);
    try {
      await Gal.putImage(tempFile.path, album: kExportAlbumName);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<void> savePng(Uint8List bytes, {required String name}) async {
    await _ensureAccess();
    await Gal.putImageBytes(bytes, name: name, album: kExportAlbumName);
  }

  @override
  Future<void> shareOriginalFile(
    String sourcePath, {
    Rect? sharePositionOrigin,
  }) async {
    // 원본은 저장소에 그대로 있으므로 복사도 정리도 필요 없다.
    await _shareInvoker([
      XFile(sourcePath),
    ], sharePositionOrigin: _safeOrigin(sharePositionOrigin));
  }

  @override
  Future<void> sharePng(
    Uint8List bytes, {
    required String name,
    Rect? sharePositionOrigin,
  }) async {
    final support = await _supportDirectoryProvider();
    final shareDir = Directory(p.join(support.path, shareDirName));
    // 앞선 공유가 비정상 종료로 남긴 파일이 있으면 먼저 걷어낸다.
    await _deleteQuietly(shareDir);
    await shareDir.create(recursive: true);
    // 이름은 파일명으로만 쓴다. 경로 구분자가 섞여 디렉터리를 벗어나면 안 된다.
    final safeName = p.basename(name);
    final file = File(p.join(shareDir.path, '$safeName.png'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _shareInvoker([
        XFile(file.path, mimeType: 'image/png', name: '$safeName.png'),
      ], sharePositionOrigin: _safeOrigin(sharePositionOrigin));
    } finally {
      await _deleteQuietly(shareDir);
    }
  }

  /// iPad의 popover 공유 시트는 비어 있지 않은 기준 사각형이 필수다.
  Rect _safeOrigin(Rect? origin) => origin == null || origin.isEmpty
      ? const Rect.fromLTWH(0, 0, 1, 1)
      : origin;

  Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // 다음 공유가 같은 전용 디렉터리를 다시 정리한다.
    }
  }
}

final photoExportSinkProvider = Provider<PhotoExportSink>((ref) {
  return PhotoExportSinkImpl();
});
