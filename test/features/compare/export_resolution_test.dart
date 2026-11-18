import 'package:bodymark/features/compare/compare_export_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 공유 이미지 해상도가 화면 폭과 상관없이 같은지 본다.
void main() {
  test('구성 폭이 달라도 결과 가로는 compareExportWidthPx다', () {
    for (final width in [288.0, 352.0, 380.0, 768.0]) {
      expect(width * exportPixelRatio(width), compareExportWidthPx);
    }
  });

  test('폭을 아직 모르면 기존 2배를 쓴다', () {
    expect(exportPixelRatio(0), 2.0);
  });
}
