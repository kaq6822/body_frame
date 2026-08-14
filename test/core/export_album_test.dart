import 'package:body_frame/core/export_album.dart';
import 'package:body_frame/features/compare/services/compare_export_sink.dart';
import 'package:body_frame/features/records/services/photo_export_sink.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 내보내기 경로가 사진 보관함의 같은 앨범을 쓰는지 gal 채널 인자로 확인한다.
///
/// 앨범을 넘기지 않으면 gal은 보관함 루트에 저장한다. 사진 내보내기만 앨범을
/// 지정하고 비교 이미지는 지정하지 않아 결과물이 `Pictures/BodyFrame/`과
/// `Pictures/`로 흩어진 적이 있어, 상수 공유만 믿지 않고 실제 호출을 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const galChannel = MethodChannel('gal');
  late List<MethodCall> galCalls;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    galCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(galChannel, (call) async {
      galCalls.add(call);
      if (call.method == 'hasAccess' || call.method == 'requestAccess') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(galChannel, null);
  });

  String? albumOf(String method) {
    final call = galCalls.lastWhere((call) => call.method == method);
    return (call.arguments as Map)['album'] as String?;
  }

  test('격자를 합성한 사진 PNG는 전용 앨범에 저장한다', () async {
    await PhotoExportSinkImpl().savePng(
      Uint8List.fromList([1, 2, 3]),
      name: 'grid_photo',
    );

    expect(albumOf('putImageBytes'), kExportAlbumName);
  });

  test('비교 이미지도 사진과 같은 앨범에 저장한다', () async {
    await CompareExportSinkImpl().saveToGallery(
      Uint8List.fromList([4, 5, 6]),
      name: 'compare_front',
    );

    expect(albumOf('putImageBytes'), kExportAlbumName);
  });
}
