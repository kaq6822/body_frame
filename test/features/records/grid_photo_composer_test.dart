import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/features/records/services/grid_photo_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('원본 바이트와 별개인 동일 크기 격자 PNG를 생성한다', () async {
    final source = await _solidPngBytes(4, 3);
    final result = await composePhotoWithGrid(
      source,
      const GridSettings(visible: false, opacity: 1, lineWidth: 2, spacing: 40),
    );

    expect(result, isNot(orderedEquals(source)));
    final codec = await ui.instantiateImageCodec(result);
    final frame = await codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (4, 3));
    frame.image.dispose();
    codec.dispose();
  });

  group('gridSettingsForImage', () {
    const settings = GridSettings(
      visible: true,
      opacity: 0.5,
      lineWidth: 1,
      spacing: 40,
    );

    test('기준 폭 대비 원본 폭만큼 간격과 굵기를 키워 화면과 같은 밀도를 만든다', () {
      final scaled = gridSettingsForImage(
        settings,
        imageWidth: 1440,
        referenceWidth: 360,
      );
      expect(scaled.spacing, 160);
      expect(scaled.lineWidth, 4);
      // 사진 폭 대비 세로선 개수가 화면(360 / 40 = 9)과 같다.
      expect(1440 / scaled.spacing, 360 / settings.spacing);
      expect(scaled.opacity, settings.opacity);
    });

    test('기준 폭이 없거나 잘못되면 설정값을 그대로 쓴다', () {
      for (final reference in const [null, 0.0, -1.0, double.infinity]) {
        expect(
          gridSettingsForImage(
            settings,
            imageWidth: 1440,
            referenceWidth: reference,
          ),
          settings,
        );
      }
    });
  });
}

Future<Uint8List> _solidPngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
