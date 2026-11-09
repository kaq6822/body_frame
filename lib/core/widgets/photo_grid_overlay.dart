import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_tokens.dart';
import 'grid_painter.dart';

/// 저장된 사진 위에 겹쳐 그리는 정렬 격자.
///
/// 앱 안의 모든 사진 보기(타임라인 스트립, 방향 모아보기, 기록 상세, 원본 보기,
/// 촬영 결과 확인, 갤러리 등록 미리보기)가 같은 규칙으로 격자를 얹도록 이
/// 위젯을 공유한다. 격자는 언제나 오버레이일 뿐이므로 원본 픽셀에는 남지 않는다.
///
/// [GridSettings.spacing]과 [GridSettings.lineWidth]는 촬영 화면(거의 화면 폭)
/// 기준의 논리 픽셀 값이다. 그대로 쓰면 썸네일에서는 선 몇 개만 지나가는 모양이
/// 되므로, 상자 폭을 [referenceWidth]와 비교해 격자 밀도를 비례 축소한다.
class PhotoGridOverlay extends StatelessWidget {
  /// 이 사진에 적용된 격자 설정. [GridSettings.visible]이 false면 아무것도
  /// 그리지 않는다.
  final GridSettings settings;

  /// 예: 'records.viewer.grid.overlay'. 화면마다 격자 상태를 검사·테스트할 수
  /// 있도록 별도 식별자를 부여한다.
  final String semanticsIdentifier;

  /// 격자 밀도의 기준 폭. 비워두면 화면 폭(촬영 화면 기준)을 쓴다.
  final double? referenceWidth;

  const PhotoGridOverlay({
    super.key,
    required this.settings,
    required this.semanticsIdentifier,
    this.referenceWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!settings.visible) return const SizedBox.shrink();

    final reference = referenceWidth ?? MediaQuery.sizeOf(context).width;
    final opacityPercent = (settings.opacity.clamp(0.0, 1.0) * 100).round();

    return Semantics(
      identifier: semanticsIdentifier,
      label: '체형 정렬 격자',
      value: '표시됨, 투명도 $opacityPercent%',
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            key: ValueKey(semanticsIdentifier),
            size: Size.infinite,
            painter: GridPainter(
              scaleGridToBox(
                settings,
                boxWidth: constraints.maxWidth,
                referenceWidth: reference,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 격자 밀도를 [boxWidth]에 맞춰 비례 축소한다.
///
/// 상자가 기준 폭보다 넓으면(확대 보기 등) 설정값을 그대로 쓴다. 축소할 때도
/// 선이 뭉개지거나 사라지지 않도록 간격과 굵기에 하한을 둔다.
GridSettings scaleGridToBox(
  GridSettings settings, {
  required double boxWidth,
  required double referenceWidth,
}) {
  const minSpacing = 12.0;
  const minLineWidth = 0.5;

  if (!boxWidth.isFinite ||
      boxWidth <= 0 ||
      !referenceWidth.isFinite ||
      referenceWidth <= 0) {
    return settings;
  }
  final scale = boxWidth / referenceWidth;
  if (scale >= 1) return settings;

  // 하한이 설정값을 거꾸로 키우지 않게 원래 값과 하한 중 작은 쪽을 바닥으로 쓴다.
  final spacingFloor = math.min(settings.spacing, minSpacing);
  final lineWidthFloor = math.min(settings.lineWidth, minLineWidth);
  return settings.copyWith(
    spacing: math.max(spacingFloor, settings.spacing * scale),
    lineWidth: math.max(lineWidthFloor, settings.lineWidth * scale),
  );
}

/// 사진을 원본 비율 그대로(contain) 놓고, 그 사진이 실제로 차지하는 사각형
/// 위에만 격자를 얹는다.
///
/// 격자를 바깥 상자 전체에 깔면 letterbox 여백까지 선이 번져 촬영 프레임과
/// 어긋난다. 촬영 화면과 내보내기 합성본은 모두 사진 프레임 기준으로 격자를
/// 그리므로, 보기 화면도 사진 사각형을 기준으로 삼아야 같은 구도가 된다.
/// 이미지와 격자가 한 상자 안에 있으므로 PhotoView 같은 확대·이동 부모에
/// 넣으면 격자도 사진과 함께 움직인다.
///
/// 비율은 [aspectRatio](저장된 메타데이터) 힌트를 먼저 쓰고, 디코딩된 이미지
/// 크기가 나오면 그 값으로 바로잡는다. 둘 다 없으면 사진만 contain으로 보이고
/// 격자는 비율을 알 때까지 그리지 않는다. 원본 픽셀은 읽기만 한다.
class PhotoWithGrid extends StatefulWidget {
  final ImageProvider image;

  /// 격자 설정. [GridSettings.visible]이 false면 사진만 그린다.
  final GridSettings settings;

  /// 격자 오버레이 식별자. [PhotoGridOverlay.semanticsIdentifier]로 전달된다.
  final String gridSemanticsIdentifier;

  /// 사진 로드 실패 표시의 식별자 접두어.
  /// `<prefix>.error`, `<prefix>.retry.button`을 쓴다.
  final String errorIdPrefix;

  /// 저장된 가로 ÷ 세로 비율. 0 이하이거나 null이면 디코딩 결과를 기다린다.
  final double? aspectRatio;

  /// [PhotoGridOverlay.referenceWidth].
  final double? referenceWidth;

  /// 썸네일처럼 좁은 곳에서는 문구 없이 아이콘 재시도 버튼만 보인다.
  final bool compactError;

  const PhotoWithGrid({
    super.key,
    required this.image,
    required this.settings,
    required this.gridSemanticsIdentifier,
    required this.errorIdPrefix,
    this.aspectRatio,
    this.referenceWidth,
    this.compactError = false,
  });

  /// 픽셀 크기로 비율을 만든다. 크기를 모르면(0) null.
  static double? aspectFromSize(int width, int height) =>
      width > 0 && height > 0 ? width / height : null;

  @override
  State<PhotoWithGrid> createState() => _PhotoWithGridState();
}

class _PhotoWithGridState extends State<PhotoWithGrid> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onError,
  );
  double? _decodedAspect;
  bool _failed = false;
  int _attempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PhotoWithGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _decodedAspect = null;
      _failed = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key && _stream != null) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final aspect = PhotoWithGrid.aspectFromSize(
      info.image.width,
      info.image.height,
    );
    info.dispose();
    if (!mounted) return;
    if (aspect == _decodedAspect && !_failed) return;
    setState(() {
      _decodedAspect = aspect;
      _failed = false;
    });
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (!mounted || _failed) return;
    setState(() => _failed = true);
  }

  Future<void> _retry() async {
    // 실패한 항목이 캐시에 남아 있으면 같은 결과만 되풀이한다.
    await widget.image.evict();
    if (!mounted) return;
    _stream?.removeListener(_listener);
    _stream = null;
    setState(() {
      _failed = false;
      _attempt++;
    });
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final error = PhotoLoadError(
      idPrefix: widget.errorIdPrefix,
      onRetry: _retry,
      compact: widget.compactError,
    );
    if (_failed) return error;

    final hint = widget.aspectRatio;
    final aspect =
        _decodedAspect ??
        (hint != null && hint.isFinite && hint > 0 ? hint : null);
    final image = Image(
      key: ValueKey(_attempt),
      image: widget.image,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => error,
    );
    if (aspect == null) return SizedBox.expand(child: image);

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            PhotoGridOverlay(
              settings: widget.settings,
              semanticsIdentifier: widget.gridSemanticsIdentifier,
              referenceWidth: widget.referenceWidth,
            ),
          ],
        ),
      ),
    );
  }
}

/// 사진을 불러오지 못했을 때의 표시. 사진 영역(어두운 backdrop) 위에 놓인다.
class PhotoLoadError extends StatelessWidget {
  /// `<prefix>.error`, `<prefix>.retry.button` 식별자를 만든다.
  final String idPrefix;

  /// null이면 재시도 버튼을 두지 않는다.
  final VoidCallback? onRetry;

  /// 좁은 썸네일용. 문구는 Semantics·툴팁으로만 제공한다.
  final bool compact;

  const PhotoLoadError({
    super.key,
    required this.idPrefix,
    this.onRetry,
    this.compact = false,
  });

  static const message = '사진을 불러오지 못했어요';

  /// 원본 파일은 앱이 고치거나 지우지 않는다. 다시 불러오기만 제안한다.
  static const description = '파일을 읽지 못했어요. 다시 불러와 보세요.';

  @override
  Widget build(BuildContext context) {
    final onPhoto = context.photoColors.onChrome;
    final errorId = '$idPrefix.error';
    final retryId = '$idPrefix.retry.button';

    if (compact) {
      return Semantics(
        identifier: errorId,
        container: true,
        label: message,
        child: Center(
          key: ValueKey(errorId),
          child: onRetry == null
              ? Icon(Icons.broken_image_outlined, color: onPhoto)
              : Semantics(
                  identifier: retryId,
                  button: true,
                  label: '사진 다시 불러오기',
                  child: IconButton(
                    key: ValueKey(retryId),
                    tooltip: '$message. 다시 불러오기',
                    onPressed: onRetry,
                    icon: Icon(Icons.broken_image_outlined, color: onPhoto),
                  ),
                ),
        ),
      );
    }

    final photo = context.photoColors;
    return Semantics(
      identifier: errorId,
      container: true,
      label: message,
      child: Center(
        key: ValueKey(errorId),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sp4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: photo.hudSurface,
                  border: Border.all(color: photo.hudOutline),
                ),
                child: Icon(Icons.broken_image_outlined, color: onPhoto),
              ),
              const SizedBox(height: AppSpacing.sp3),
              ExcludeSemantics(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.texts.titleSmall?.copyWith(color: onPhoto),
                ),
              ),
              const SizedBox(height: AppSpacing.sp1),
              ExcludeSemantics(
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall?.copyWith(
                    color: onPhoto.withValues(alpha: 0.72),
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.sp3),
                Semantics(
                  identifier: retryId,
                  button: true,
                  label: '사진 다시 불러오기',
                  child: OutlinedButton.icon(
                    key: ValueKey(retryId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: onPhoto,
                      side: BorderSide(color: photo.controlOutline),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('다시 불러오기'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
