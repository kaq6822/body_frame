import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/records/services/grid_photo_composer.dart';
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
