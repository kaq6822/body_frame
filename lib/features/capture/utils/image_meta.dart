import 'dart:io';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';

/// 저장 대상 이미지의 픽셀 크기와 EXIF 회전 정보.
///
/// MVP.md 15장: 이미지 회전 정보를 올바르게 반영해야 하므로 원본을 변형하지
/// 않는 대신 이 메타데이터를 [BodyPhoto]에 함께 저장해 표시 단계에서 활용한다.
class ImageMeta {
  final int width;
  final int height;

  /// EXIF Orientation 값(1~8). 읽을 수 없으면 1(정상 방향)로 취급한다.
  final int orientation;

  const ImageMeta({
    required this.width,
    required this.height,
    this.orientation = 1,
  });
}

/// [path]의 이미지를 읽어 크기와 EXIF 회전 정보를 반환한다.
///
/// 크기/EXIF를 읽지 못해도 예외를 던지지 않고 기본값으로 대체한다(저장 흐름을
/// 막지 않기 위함).
Future<ImageMeta> readImageMeta(String path) async {
  final bytes = await File(path).readAsBytes();

  var width = 0;
  var height = 0;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    width = frame.image.width;
    height = frame.image.height;
    frame.image.dispose();
  } catch (_) {
    // 디코딩 실패해도 저장은 계속 진행하고 크기는 0으로 둔다.
  }

  final orientation = await _readOrientation(bytes);
  return ImageMeta(width: width, height: height, orientation: orientation);
}

/// EXIF DateTimeOriginal(없으면 DateTime)에서 촬영일을 추출한다.
/// 갤러리 등록 화면에서 촬영일 기본값 제안에 사용한다(MVP.md 5장).
Future<DateTime?> readExifShotDate(List<int> bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    final tag = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
    if (tag == null) return null;
    return _parseExifDateTime(tag.printable);
  } catch (_) {
    return null;
  }
}

Future<int> _readOrientation(List<int> bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    final tag = tags['Image Orientation'];
    if (tag == null) return 1;
    final values = tag.values.toList();
    if (values.isNotEmpty) {
      final raw = values.first;
      if (raw is int) return raw;
      final parsed = int.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
  } catch (_) {
    // EXIF가 없는 이미지(예: 카메라 직촬영 후 일부 인코더)는 기본값을 쓴다.
  }
  return 1;
}

/// EXIF 표준 형식 'yyyy:MM:dd HH:mm:ss'을 파싱한다.
DateTime? _parseExifDateTime(String raw) {
  final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})').firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  try {
    return DateTime(year, month, day);
  } catch (_) {
    return null;
  }
}
