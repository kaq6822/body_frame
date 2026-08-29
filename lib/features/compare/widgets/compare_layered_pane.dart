import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/photo_frame.dart';
import '../../../core/theme/app_tokens.dart';
import '../compare_export_models.dart';
import 'compare_grid_overlay.dart';

/// 겹쳐 보기와 슬라이더 비교가 화면/내보내기에서 함께 사용하는 사진 프레임.
///
/// 두 사진은 완전히 같은 프레임에서 각각의 [TransformationController]를
/// 사용한다. 따라서 비교 화면에서 조정한 확대·이동 행렬과 프레임 크기를
/// 내보내기 화면에 그대로 전달하면 같은 구도를 재현할 수 있다.
class CompareLayeredPane extends StatelessWidget {
  final CompareMode mode;
  final BodyPhoto beforePhoto;
  final BodyPhoto afterPhoto;
  final String beforeDateLabel;
  final String afterDateLabel;
  final TransformationController beforeController;
  final TransformationController afterController;
  final bool interactive;
  final GridSettings gridSettings;
  final bool showGrid;
  final double overlayOpacity;
  final double sliderPosition;
  final ValueChanged<double>? onSliderPositionChanged;
  final String identifierPrefix;
  final Size? fixedPhotoSize;
  final ValueChanged<Size>? onPhotoBoxSize;

  const CompareLayeredPane({
    super.key,
    required this.mode,
    required this.beforePhoto,
    required this.afterPhoto,
    required this.beforeDateLabel,
    required this.afterDateLabel,
    required this.beforeController,
    required this.afterController,
    required this.interactive,
    required this.gridSettings,
    required this.showGrid,
    required this.overlayOpacity,
    required this.sliderPosition,
    required this.identifierPrefix,
    this.onSliderPositionChanged,
    this.fixedPhotoSize,
    this.onPhotoBoxSize,
  }) : assert(mode != CompareMode.sideBySide);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('$identifierPrefix.pane'),
      identifier: '$identifierPrefix.pane',
      container: true,
      label: mode == CompareMode.overlay ? '전후 사진 겹쳐 보기' : '전후 사진 슬라이더 비교',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _headerLabel(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Flexible(
            child: fixedPhotoSize != null
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: fixedPhotoSize!.width,
                        height: fixedPhotoSize!.height,
                        child: _buildCanvas(),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = _frameSize(constraints);
                      final report = onPhotoBoxSize;
                      if (report != null) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => report(size),
                        );
                      }
                      return Center(
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: _buildCanvas(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _headerLabel() {
    final beforeDate = beforeDateLabel.isEmpty ? '이전' : '이전 $beforeDateLabel';
    final afterDate = afterDateLabel.isEmpty ? '이후' : '이후 $afterDateLabel';
    return '$beforeDate  ·  $afterDate';
  }

  Size _frameSize(BoxConstraints constraints) {
    const targetAspect = kPhotoFrameAspect;
    var width = constraints.maxWidth;
    if (!width.isFinite) {
      width = constraints.maxHeight.isFinite
          ? constraints.maxHeight * targetAspect
          : 300;
    }
    var height = width / targetAspect;
    if (constraints.maxHeight.isFinite && height > constraints.maxHeight) {
      height = constraints.maxHeight;
      width = height * targetAspect;
    }
    return Size(
      width.clamp(0, double.infinity),
      height.clamp(0, double.infinity),
    );
  }

  Widget _buildCanvas() {
    final opacity = overlayOpacity.clamp(0.0, 1.0);
    final position = sliderPosition.clamp(0.0, 1.0);
    final modeValue = mode == CompareMode.overlay
        ? '이후 사진 투명도 ${(opacity * 100).round()}%'
        : '비교 경계 ${(position * 100).round()}%';

    return Semantics(
      key: ValueKey('$identifierPrefix.canvas'),
      identifier: '$identifierPrefix.canvas',
      label: mode.label,
      value: modeValue,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final before = _photoLayer(
              photo: beforePhoto,
              controller: beforeController,
              identifier: '$identifierPrefix.before.viewer',
              label: '이전 사진',
            );
            final after = _photoLayer(
              photo: afterPhoto,
              controller: afterController,
              identifier: '$identifierPrefix.after.viewer',
              label: '이후 사진',
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: context.photoColors.inset),
                before,
                if (mode == CompareMode.overlay)
                  Opacity(opacity: opacity, child: after)
                else
                  ClipRect(
                    clipper: _HorizontalFractionClipper(position),
                    child: after,
                  ),
                if (showGrid)
                  CompareGridOverlay(
                    settings: gridSettings,
                    semanticsIdentifier: '$identifierPrefix.grid.overlay',
                  ),
                if (mode == CompareMode.slider)
                  _SliderBoundary(
                    identifier: '$identifierPrefix.handle',
                    position: position,
                    frameWidth: constraints.maxWidth,
                    onChanged: onSliderPositionChanged,
                    // 내보내기 프레임에서는 경계선만 남긴다. 드래그 손잡이는
                    // 조작 수단이므로 저장된 이미지에 합성되면 결과물에 앱 UI가
                    // 섞인다.
                    showHandle: interactive,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _photoLayer({
    required BodyPhoto photo,
    required TransformationController controller,
    required String identifier,
    required String label,
  }) {
    return Semantics(
      identifier: identifier,
      label: '$label${interactive ? ', 확대 및 이동 가능' : ', 미리보기'}',
      child: InteractiveViewer(
        key: ValueKey(identifier),
        transformationController: controller,
        panEnabled: interactive,
        scaleEnabled: interactive,
        minScale: 0.5,
        maxScale: 6,
        clipBehavior: Clip.hardEdge,
        child: Image.file(
          File(photo.filePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

class _SliderBoundary extends StatelessWidget {
  final String identifier;
  final double position;
  final double frameWidth;
  final ValueChanged<double>? onChanged;
  final bool showHandle;

  const _SliderBoundary({
    required this.identifier,
    required this.position,
    required this.frameWidth,
    required this.onChanged,
    required this.showHandle,
  });

  @override
  Widget build(BuildContext context) {
    // 최소 터치 타겟(48dp)을 채운다. 경계를 끌 때 손가락이 자주 미끄러지는 지점이다.
    const handleWidth = AppSpacing.minTouchTarget;
    const lineWidth = 3.0;
    final percent = (position * 100).round();
    final callback = onChanged;
    final line = Container(width: lineWidth, color: context.photoColors.onChrome);

    if (!showHandle) {
      // 경계 위치는 canvas의 semantics value로 이미 읽히므로 표시용 선에는
      // 별도 노드를 만들지 않는다.
      return Positioned(
        left: frameWidth * position - lineWidth / 2,
        top: 0,
        bottom: 0,
        width: lineWidth,
        child: line,
      );
    }

    return Positioned(
      left: frameWidth * position - handleWidth / 2,
      top: 0,
      bottom: 0,
      width: handleWidth,
      child: Semantics(
        identifier: identifier,
        label: '이전과 이후 사진의 비교 경계',
        slider: true,
        value: '$percent%',
        increasedValue: '${((position + 0.05).clamp(0.0, 1.0) * 100).round()}%',
        decreasedValue: '${((position - 0.05).clamp(0.0, 1.0) * 100).round()}%',
        onIncrease: callback == null
            ? null
            : () => callback((position + 0.05).clamp(0.0, 1.0)),
        onDecrease: callback == null
            ? null
            : () => callback((position - 0.05).clamp(0.0, 1.0)),
        child: GestureDetector(
          key: ValueKey(identifier),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: callback == null || frameWidth <= 0
              ? null
              : (details) {
                  callback(
                    (position + details.delta.dx / frameWidth).clamp(0.0, 1.0),
                  );
                },
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                line,
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.photoColors.onChrome,
                      width: 2,
                    ),
                  ),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.drag_handle,
                      size: 18,
                      color: context.photoColors.onChrome,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalFractionClipper extends CustomClipper<Rect> {
  final double fraction;

  const _HorizontalFractionClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _HorizontalFractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
