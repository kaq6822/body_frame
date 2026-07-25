import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/grid_painter.dart';

abstract class GridPhotoComposer {
  Future<Uint8List> compose(Uint8List sourceBytes, GridSettings settings);
}

class GridPhotoComposerImpl implements GridPhotoComposer {
  const GridPhotoComposerImpl();

  @override
  Future<Uint8List> compose(Uint8List sourceBytes, GridSettings settings) {
    return composePhotoWithGrid(sourceBytes, settings);
  }
}

final gridPhotoComposerProvider = Provider<GridPhotoComposer>((ref) {
  return const GridPhotoComposerImpl();
});

/// 원본 이미지 바이트를 수정하지 않고 격자가 합성된 새 PNG를 만든다.
///
/// Flutter 이미지 코덱으로 EXIF 방향이 반영된 픽셀을 디코딩한 뒤 촬영/비교
/// 화면과 동일한 [GridPainter]를 별도 캔버스에 그린다.
Future<Uint8List> composePhotoWithGrid(
  Uint8List sourceBytes,
  GridSettings settings,
) async {
  final codec = await ui.instantiateImageCodec(sourceBytes);
  ui.Image? sourceImage;
  ui.Picture? picture;
  ui.Image? composedImage;
  try {
    final frame = await codec.getNextFrame();
    sourceImage = frame.image;
    final size = ui.Size(
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(sourceImage, ui.Offset.zero, ui.Paint());
    GridPainter(settings.copyWith(visible: true)).paint(canvas, size);
    picture = recorder.endRecording();
    composedImage = await picture.toImage(
      sourceImage.width,
      sourceImage.height,
    );
    final data = await composedImage.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('격자 합성 이미지를 PNG로 인코딩하지 못했습니다.');
    }
    return data.buffer.asUint8List();
  } finally {
    composedImage?.dispose();
    picture?.dispose();
    sourceImage?.dispose();
    codec.dispose();
  }
}
