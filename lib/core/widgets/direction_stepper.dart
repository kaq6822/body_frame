import 'package:flutter/material.dart';

import '../models/body_direction.dart';
import '../theme/app_tokens.dart';

/// 4방향 촬영 단계 선택기(정면/좌측면/우측면/후면).
///
/// 각 방향은 세 상태 중 하나다.
/// - 비활성: 옅은 회색 면.
/// - 기록됨([recorded]에 포함): 오른쪽 위 체크 표시 + 주요 색 테두리.
/// - 활성([selected]): 주요 색으로 채움. [onDark]면 측정 시안으로 채운다(카메라).
///
/// 세그먼트마다 48dp 터치 영역을 보장한다. 네 칸이 한 줄에 들어가지 않으면(좁은
/// 화면·큰 글꼴) 2×2로 줄바꿈한다. 글자를 줄이지 않는다.
///
/// [singleRow]를 켜면 줄바꿈하지 않고 높이를 고정한다. 칸에 들어가지 않는 글자는
/// 칸 안에서 축소한다. 카메라처럼 단계가 바뀌어도 아래 영역(뷰파인더) 크기가
/// 흔들리면 안 되는 곳에서 쓴다.
///
/// 세그먼트 키와 Semantics identifier는 `<identifier>.<direction.key>`다.
class DirectionStepper extends StatelessWidget {
  static const defaultIdentifier = 'common.direction.stepper';

  /// 기본 표시 순서.
  static const standardDirections = [
    BodyDirection.front,
    BodyDirection.leftSide,
    BodyDirection.rightSide,
    BodyDirection.back,
  ];

  final BodyDirection? selected;

  /// null이면 누를 수 없다(표시 전용).
  final ValueChanged<BodyDirection>? onSelected;

  final Set<BodyDirection> recorded;
  final List<BodyDirection> directions;

  /// 카메라 뷰파인더처럼 어두운 바탕 위에 놓일 때 켠다.
  final bool onDark;

  /// 라벨을 바꿀 때 쓴다. 예: 활성 방향에만 "정면 1/4".
  final String Function(BodyDirection direction)? labelBuilder;

  /// 방향 아래 작은 보조 문구. 예: "완료", "건너뜀". null을 돌려주면 생략한다.
  final String? Function(BodyDirection direction)? captionBuilder;

  /// 항상 한 줄·고정 높이로 그린다.
  final bool singleRow;

  final String identifier;

  const DirectionStepper({
    super.key,
    required this.selected,
    this.onSelected,
    this.recorded = const {},
    this.directions = standardDirections,
    this.onDark = false,
    this.labelBuilder,
    this.captionBuilder,
    this.singleRow = false,
    this.identifier = defaultIdentifier,
  });

  String _label(BodyDirection d) => labelBuilder?.call(d) ?? d.label;

  static const _gap = AppSpacing.sp2;

  /// [singleRow]일 때의 고정 높이. 보조 문구가 있으면 한 줄만큼 더 둔다.
  static const _singleRowHeight = AppSpacing.minTouchTarget;
  static const _singleRowCaptionHeight = AppSpacing.minTouchTarget + 12;
  static const _checkSize = 12.0;

  /// 라벨 좌우 여백. 오른쪽 위 체크 표시가 라벨과 겹치지 않을 만큼 둔다.
  static const _horizontalPadding = AppSpacing.sp3;

  @override
  Widget build(BuildContext context) {
    final style = context.texts.labelLarge!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    // 가장 넓은 세그먼트가 필요로 하는 폭. 체크 표시는 모서리에 겹쳐 놓아 상태가
    // 바뀌어도 폭과 줄바꿈 여부가 흔들리지 않는다.
    var widest = 0.0;
    for (final d in directions) {
      final painter = TextPainter(
        text: TextSpan(text: _label(d), style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width + _horizontalPadding * 2 + 2;
      if (w > widest) widest = w;
      painter.dispose();
    }

    return Semantics(
      identifier: identifier,
      container: true,
      child: LayoutBuilder(
        key: ValueKey(identifier),
        builder: (context, constraints) {
          final count = directions.length;
          final fitsOneRow =
              singleRow ||
              widest * count + _gap * (count - 1) <= constraints.maxWidth;
          final perRow = fitsOneRow ? count : (count / 2).ceil();
          final rows = <Widget>[];
          for (var start = 0; start < count; start += perRow) {
            final slice = directions.sublist(
              start,
              (start + perRow).clamp(0, count),
            );
            rows.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < perRow; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: i < slice.length
                          ? _segment(context, slice[i], start + i, count)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          }
          if (singleRow) {
            return SizedBox(
              height: captionBuilder == null
                  ? _singleRowHeight
                  : _singleRowCaptionHeight,
              child: rows.single,
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                IntrinsicHeight(child: rows[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _segment(BuildContext context, BodyDirection d, int index, int total) {
    final colors = context.colors;
    final photo = context.photoColors;
    final isActive = d == selected;
    final isRecorded = recorded.contains(d);

    final Color background;
    final Color foreground;
    final Color? border;
    final Color checkColor;
    if (onDark) {
      background = isActive ? photo.measure : photo.hudSurface;
      foreground = isActive ? photo.onMeasure : photo.onChrome;
      border = isActive
          ? null
          : (isRecorded ? photo.measure : photo.hudOutline);
      checkColor = isActive ? photo.onMeasure : photo.measure;
    } else {
      background = isActive
          ? colors.primary
          : (isRecorded
                ? colors.surfaceContainerLowest
                : colors.secondaryContainer);
      foreground = isActive
          ? colors.onPrimary
          : (isRecorded ? colors.onSurface : colors.onSurfaceVariant);
      border = isActive ? null : (isRecorded ? colors.primary : null);
      checkColor = isActive ? colors.onPrimary : colors.primary;
    }

    final label = _label(d);
    final caption = captionBuilder?.call(d);
    final state = [
      if (isRecorded) '기록됨',
      if (isActive) '현재 단계',
      if (caption != null && !isRecorded && !isActive) caption,
    ].join(', ');
    final id = '$identifier.${d.key}';

    return Semantics(
      identifier: id,
      button: onSelected != null,
      selected: isActive,
      enabled: onSelected != null,
      label: '$label, ${index + 1}/$total단계${state.isEmpty ? '' : ', $state'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        child: Material(
          key: ValueKey(id),
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.smAll,
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              InkWell(
                onTap: onSelected == null ? null : () => onSelected!(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _horizontalPadding,
                    vertical: AppSpacing.sp1,
                  ),
                  child: Center(
                    child: _content(context, label, caption, foreground),
                  ),
                ),
              ),
              if (isRecorded)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(Icons.check, size: _checkSize, color: checkColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    String label,
    String? caption,
    Color foreground,
  ) {
    Widget content = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: singleRow ? 1 : null,
      style: context.texts.labelLarge?.copyWith(
        color: foreground,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (caption != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: singleRow ? 1 : null,
            style: context.texts.labelSmall?.copyWith(
              color: foreground.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    // 고정 높이 한 줄에서는 글자를 칸 안으로 축소해 줄바꿈·넘침을 막는다.
    return singleRow
        ? FittedBox(fit: BoxFit.scaleDown, child: content)
        : content;
  }
}
