import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 단일 사진을 사진 보관함으로 내보내는 플랫폼 경계.
///
/// 테스트에서는 이 provider를 fake로 바꿔 원본 파일과 파생 PNG 중 어떤
/// 경로가 선택됐는지 플러그인 호출 없이 검증한다.
abstract class PhotoExportSink {
  Future<void> saveOriginalFile(String sourcePath, {required String name});

  Future<void> savePng(Uint8List bytes, {required String name});
}

class PhotoExportSinkImpl implements PhotoExportSink {
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
      await Gal.putImage(tempFile.path, album: 'BodyFrame');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<void> savePng(Uint8List bytes, {required String name}) async {
    await _ensureAccess();
    await Gal.putImageBytes(bytes, name: name);
  }
}

final photoExportSinkProvider = Provider<PhotoExportSink>((ref) {
  return PhotoExportSinkImpl();
});
