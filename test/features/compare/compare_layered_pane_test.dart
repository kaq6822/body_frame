import 'dart:io';
import 'dart:ui' as ui;

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/features/compare/compare_export_models.dart';
import 'package:body_frame/features/compare/widgets/compare_layered_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String widePath;
  late String tallPath;
  late TransformationController beforeController;
  late TransformationController afterController;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'body_frame_layered_compare_',
    );
    widePath = await _writePng(tempDir, 'wide.png', 180, 60);
    tallPath = await _writePng(tempDir, 'tall.png', 60, 180);
    beforeController = TransformationController();
    afterController = TransformationController();
  });

  tearDown(() async {
    beforeController.dispose();
    afterController.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('가로·세로 비율이 다른 사진도 화면 비율에 맞춰 같은 프레임에 표시한다', (tester) async {
    final before = BodyPhoto(
      id: 'wide',
      recordId: 'r1',
      filePath: widePath,
      direction: BodyDirection.front,
      width: 180,
      height: 60,
      createdAt: DateTime(2026, 1, 1),
    );
    final after = BodyPhoto(
      id: 'tall',
      recordId: 'r2',
      filePath: tallPath,
      direction: BodyDirection.front,
      width: 60,
      height: 180,
      createdAt: DateTime(2026, 2, 1),
    );

    for (final testCase in <(Size, CompareMode)>[
      (const Size(320, 520), CompareMode.overlay),
      (const Size(700, 300), CompareMode.slider),
    ]) {
      final (viewportSize, mode) = testCase;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: CompareLayeredPane(
                  mode: mode,
                  beforePhoto: before,
                  afterPhoto: after,
                  beforeDateLabel: '2026.01.01',
                  afterDateLabel: '2026.02.01',
                  beforeController: beforeController,
                  afterController: afterController,
                  interactive: true,
                  gridSettings: GridSettings.defaults,
                  showGrid: true,
                  overlayOpacity: 0.5,
                  sliderPosition: 0.5,
                  onSliderPositionChanged: (_) {},
                  identifierPrefix: 'ratio.${mode.key}',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final canvasSize = tester.getSize(
        find.byKey(ValueKey('ratio.${mode.key}.canvas')),
      );
      expect(canvasSize.width / canvasSize.height, closeTo(3 / 4, 0.001));
      expect(find.byType(Image), findsNWidgets(2));
    }
  });
}

Future<String> _writePng(
  Directory directory,
  String name,
  int width,
  int height,
) async {
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
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  return file.path;
}
