import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef CompareShareDirectoryProvider = Future<Directory> Function();
typedef CompareShareInvoker =
    Future<void> Function(
      List<XFile> files, {
      String? text,
      Rect? sharePositionOrigin,
    });

/// 생성된 비교 이미지를 기기에 저장하거나 외부로 공유하는 출구.
///
/// 기기 사진 보관함 저장(gal)과 OS 공유 시트(share_plus)를 감싸는 얇은
/// 추상화. 위젯 테스트에서는 실제 플러그인 채널을 타지 않도록
/// [CompareExportSink]를 인메모리 Fake로 교체할 수 있다.
abstract class CompareExportSink {
  Future<void> saveToGallery(Uint8List bytes, {required String name});

  Future<void> share(
    Uint8List bytes, {
    required String name,
    String? text,
    Rect? sharePositionOrigin,
  });
}

class CompareExportSinkImpl implements CompareExportSink {
  final CompareShareDirectoryProvider _supportDirectoryProvider;
  final CompareShareInvoker _shareInvoker;

  CompareExportSinkImpl({
    CompareShareDirectoryProvider? supportDirectoryProvider,
    CompareShareInvoker? shareInvoker,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _shareInvoker =
           shareInvoker ??
           ((files, {text, sharePositionOrigin}) async {
             await Share.shareXFiles(
               files,
               text: text,
               sharePositionOrigin: sharePositionOrigin,
             );
           });

  @override
  Future<void> saveToGallery(Uint8List bytes, {required String name}) {
    return Gal.putImageBytes(bytes, name: name);
  }

  @override
  Future<void> share(
    Uint8List bytes, {
    required String name,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    // 공유용 파생 이미지는 임시 산출물이므로 성공하든 실패하든 즉시 정리한다.
    final support = await _supportDirectoryProvider();
    final shareDir = Directory(p.join(support.path, 'compare_share'));
    if (await shareDir.exists()) {
      try {
        await shareDir.delete(recursive: true);
      } catch (_) {
        // best effort
      }
    }
    await shareDir.create(recursive: true);
    final safeName = p.basename(name);
    final file = File(p.join(shareDir.path, '$safeName.png'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _shareInvoker(
        [XFile(file.path, mimeType: 'image/png', name: '$safeName.png')],
        text: text,
        sharePositionOrigin:
            // iPad의 popover 공유 시트는 비어 있지 않은 기준 사각형이 필수다.
            sharePositionOrigin ?? const Rect.fromLTWH(0, 0, 1, 1),
      );
    } finally {
      try {
        if (await shareDir.exists()) {
          await shareDir.delete(recursive: true);
        }
      } catch (_) {
        // 다음 공유 시작 시에도 같은 전용 디렉터리를 다시 정리한다.
      }
    }
  }
}

/// compare feature 전용 DI 지점. `lib/core/providers.dart`는 건드리지 않는다.
final compareExportSinkProvider = Provider<CompareExportSink>((ref) {
  return CompareExportSinkImpl();
});
