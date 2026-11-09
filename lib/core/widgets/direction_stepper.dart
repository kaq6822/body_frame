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

  final String identifier;

  const DirectionStepper({
    super.key,
    required this.selected,
    this.onSelected,
    this.recorded = const {},
    this.directions = standardDirections,
    this.onDark = false,
    this.labelBuilder,
    this.identifier = defaultIdentifier,
  });

  String _label(BodyDirection d) => labelBuilder?.call(d) ?? d.label;

  static const _gap = AppSpacing.sp2;
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
    final state = [if (isRecorded) '기록됨', if (isActive) '현재 단계'].join(', ');
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
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: context.texts.labelLarge?.copyWith(
                        color: foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
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
}
