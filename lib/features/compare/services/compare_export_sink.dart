import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 생성된 비교 이미지를 기기에 저장하거나 외부로 공유하는 출구.
///
/// MVP.md 9장: 기기 사진 보관함 저장(gal)과 OS 공유 시트(share_plus)를
/// 감싸는 얇은 추상화. 위젯 테스트에서는 실제 플러그인 채널을 타지 않도록
/// [CompareExportSink]를 인메모리 Fake로 교체할 수 있다(ARCHITECTURE.md §8).
abstract class CompareExportSink {
  Future<void> saveToGallery(Uint8List bytes, {required String name});

  Future<void> share(Uint8List bytes, {required String name, String? text});
}

class CompareExportSinkImpl implements CompareExportSink {
  @override
  Future<void> saveToGallery(Uint8List bytes, {required String name}) {
    return Gal.putImageBytes(bytes, name: name);
  }

  @override
  Future<void> share(Uint8List bytes, {required String name, String? text}) async {
    final dir = await getTemporaryDirectory();
    // 전용 하위 디렉터리를 사용하고, 새 공유 전에 이전 공유에서 남은 평문
    // PNG를 정리한다(민감 사진 잔존 방지). 공유 직후 즉시 삭제하면 수신 앱이
    // 파일을 읽기 전에 사라질 수 있어 다음 공유 시점에 청소한다.
    final shareDir = Directory('${dir.path}/compare_share');
    if (await shareDir.exists()) {
      try {
        await shareDir.delete(recursive: true);
      } catch (_) {
        // best effort
      }
    }
    await shareDir.create(recursive: true);
    final file = File('${shareDir.path}/$name.png');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: '$name.png')],
      text: text,
    );
  }
}

/// compare feature 전용 DI 지점. `lib/core/providers.dart`는 건드리지 않는다.
final compareExportSinkProvider = Provider<CompareExportSink>((ref) {
  return CompareExportSinkImpl();
});
