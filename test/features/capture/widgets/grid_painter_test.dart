import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/capture/widgets/grid_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 격자 페인터 단위 테스트. MVP.md 4.3 구성 요소(중앙 세로 기준선, 세로/가로선,
/// 중앙 기준점, 좌우 대칭 기준선)가 예외 없이 그려지는지, 그리고 설정 변경
/// 감지(shouldRepaint)가 올바른지 검증한다.
void main() {
  group('GridPainter', () {
    test('shouldRepaint는 설정이 다르면 true, 같으면 false를 반환한다', () {
      const a = GridPainter(GridSettings.defaults);
      const b = GridPainter(GridSettings.defaults);
      const c = GridPainter(GridSettings(opacity: 0.2));

      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });

    test('격자가 보이는 상태에서는 예외 없이 그려진다', () {
      const painter = GridPainter(GridSettings.defaults);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => painter.paint(canvas, const Size(360, 640)), returnsNormally);

      recorder.endRecording().dispose();
    });

    test('visible=false면 그리지 않고 예외 없이 반환한다', () {
      const painter = GridPainter(GridSettings(visible: false));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => painter.paint(canvas, const Size(360, 640)), returnsNormally);

      recorder.endRecording().dispose();
    });

    test('크기가 0이어도 예외 없이 처리한다', () {
      const painter = GridPainter(GridSettings.defaults);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => painter.paint(canvas, Size.zero), returnsNormally);

      recorder.endRecording().dispose();
    });

    test('극단적인 spacing/lineWidth 값에도 안전하게 그려진다', () {
      const painter = GridPainter(GridSettings(spacing: 0, lineWidth: 0));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => painter.paint(canvas, const Size(200, 200)), returnsNormally);

      recorder.endRecording().dispose();
    });
  });
}
