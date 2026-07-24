import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import 'compare_grid_overlay.dart';

/// 좌우 비교 화면과 비교 이미지 생성 화면이 공용으로 쓰는 사진 표시 영역.
///
/// 화면 구도와 생성 이미지 구도를 일치시키기 위해 실제 조작 가능한
/// 비교 화면과 캡처용(정적) 생성 화면 모두 동일한
/// InteractiveViewer 렌더링 경로를 사용한다. [interactive]가 false이면
/// 제스처만 막고 [controller]의 행렬은 그대로 적용해 동일한 픽셀 결과를
/// 만든다.
class ComparePhotoPane extends StatelessWidget {
  final String label;
  final String dateLabel;
  final BodyPhoto photo;
  final TransformationController controller;
  final bool interactive;
  final GridSettings gridSettings;
  final bool showGrid;

  /// 예: 'compare.before'. 하위 요소(viewer/grid.overlay)는 이 값에
  /// 접두사로 붙는다.
  final String paneIdentifier;

  /// 사진 프레임을 이 논리 크기로 고정 렌더링한다(생성 화면용).
  ///
  /// [controller]의 행렬은 pane 로컬 픽셀 좌표 기준이므로, 비교 화면과
  /// 동일한 크기로 렌더링해야 구도가 일치한다. 공간이 부족하면 FittedBox로
  /// 균등 축소해 구도를 그대로 유지한다.
  final Size? fixedPhotoSize;

  /// 레이아웃으로 결정된 사진 프레임 크기를 보고한다(비교 화면용).
  final ValueChanged<Size>? onPhotoBoxSize;

  const ComparePhotoPane({
    super.key,
    required this.label,
    required this.dateLabel,
    required this.photo,
    required this.controller,
    required this.interactive,
    required this.gridSettings,
    required this.showGrid,
    required this.paneIdentifier,
    this.fixedPhotoSize,
    this.onPhotoBoxSize,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: paneIdentifier,
      container: true,
      label: '$label 사진${dateLabel.isEmpty ? '' : ', $dateLabel'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          if (dateLabel.isNotEmpty)
            Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          // 원본 비율은 항상 BoxFit.contain으로 유지한다.
          // 두 사진이 동일한 비교가 가능하도록 고정 비율(3:4) 프레임을 쓰되,
          // 가로/세로 중 더 좁은 쪽에 맞춰 줄여(letterbox) 오버플로를 피한다
          // (plain AspectRatio는 폭만 기준으로 커지므로 세로 공간이 좁은
          // 레이아웃에서 넘칠 수 있다).
          Flexible(
            child: fixedPhotoSize != null
                // 생성 화면: 비교 화면에서 보고된 크기로 고정 렌더링해
                // 행렬이 동일한 픽셀 구도를 만들도록 한다. 공간이 부족하면
                // FittedBox가 균등 축소하므로 구도는 유지된다.
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: fixedPhotoSize!.width,
                        height: fixedPhotoSize!.height,
                        child: _photoBox(context),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const targetAspect = 3 / 4; // width / height
                      double width = constraints.maxWidth;
                      double height = width / targetAspect;
                      if (!height.isFinite ||
                          height > constraints.maxHeight) {
                        height = constraints.maxHeight;
                        width = height * targetAspect;
                      }
                      final size = Size(width, height);
                      final report = onPhotoBoxSize;
                      if (report != null) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => report(size));
                      }
                      return Center(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: _photoBox(context),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _photoBox(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x14000000)),
          Semantics(
            identifier: '$paneIdentifier.viewer',
            label: interactive ? '$label 사진, 확대 및 이동 가능' : '$label 사진 미리보기',
            child: InteractiveViewer(
              key: ValueKey('$paneIdentifier.viewer'),
              transformationController: controller,
              panEnabled: interactive,
              scaleEnabled: interactive,
              minScale: 0.5,
              maxScale: 6,
              clipBehavior: Clip.hardEdge,
              child: Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          if (showGrid)
            CompareGridOverlay(
              settings: gridSettings,
              semanticsIdentifier: '$paneIdentifier.grid.overlay',
            ),
        ],
      ),
    );
  }
}
