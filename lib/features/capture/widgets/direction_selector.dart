import 'package:flutter/material.dart';

import 'package:body_frame/core/models/models.dart';

/// 촬영 방향(정면/좌측면/우측면/후면/기타) 선택 위젯.
///
/// 촬영 방향 선택 화면, 촬영 결과 확인 화면(방향 변경), 갤러리 등록 화면
/// (사진별 방향 지정)에서 재사용한다. [idPrefix]로 화면/항목별 안정적인
/// Semantics.identifier를 구성한다(예: `capture.direction.front.button`).
class DirectionSelector extends StatelessWidget {
  final String idPrefix;
  final BodyDirection? selected;
  final ValueChanged<BodyDirection> onSelected;

  const DirectionSelector({
    super.key,
    required this.idPrefix,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BodyDirection.values.map((direction) {
        final isSelected = direction == selected;
        final id = '$idPrefix.${direction.key}.button';
        return Semantics(
          identifier: id,
          button: true,
          selected: isSelected,
          label: direction.label,
          child: ChoiceChip(
            key: ValueKey(id),
            label: Text(direction.label),
            selected: isSelected,
            onSelected: (_) => onSelected(direction),
          ),
        );
      }).toList(),
    );
  }
}
