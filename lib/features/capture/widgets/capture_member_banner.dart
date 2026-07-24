import 'package:flutter/material.dart';

import 'package:body_frame/core/models/models.dart';

/// 회원 이름(+ 촬영 방향)을 상시 표시하는 배너.
///
/// 잘못된 회원에게 사진이 등록되는 것을 방지하기 위해 촬영 전과
/// 저장 전에 회원 이름을 다시 확인할 수 있어야 한다. 촬영 방향 선택/격자
/// 카메라/촬영 결과 확인 화면에서 동일한 식별자로 재사용한다.
class CaptureMemberBanner extends StatelessWidget {
  final String memberName;
  final BodyDirection? direction;
  final Color? textColor;

  const CaptureMemberBanner({
    super.key,
    required this.memberName,
    this.direction,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final directionSuffix = direction == null ? '' : ' · ${direction!.label}';
    final text = '$memberName$directionSuffix';
    return Semantics(
      identifier: 'capture.member.name.label',
      label: '현재 촬영 대상: $text',
      child: Text(
        text,
        key: const ValueKey('capture.member.name.label'),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}
