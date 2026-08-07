import 'package:body_frame/core/models/models.dart';

/// 촬영 방향별 보조 안내 문구. 카메라 높이/서는 위치/발 위치/
/// 촬영 거리를 반복 가능한 조건으로 안내한다.
List<String> captureGuideMessages(BodyDirection direction) {
  const distance = '촬영 거리: 전신이 화면에 들어오도록 약 2~3m 거리를 유지하세요.';
  const height = '카메라 높이: 가슴 높이에 맞춰 수평으로 두세요.';
  const foot = '발 위치: 격자 중앙 세로선에 두 발 사이를 맞춰 서주세요.';

  switch (direction) {
    case BodyDirection.front:
      return ['서는 방향: 카메라를 정면으로 바라보고 서주세요.', foot, height, distance];
    case BodyDirection.leftSide:
      return ['서는 방향: 왼쪽 옆모습이 카메라를 향하도록 서주세요.', foot, height, distance];
    case BodyDirection.rightSide:
      return ['서는 방향: 오른쪽 옆모습이 카메라를 향하도록 서주세요.', foot, height, distance];
    case BodyDirection.back:
      return ['서는 방향: 뒷모습이 보이도록 카메라 반대쪽을 바라봐 주세요.', foot, height, distance];
    case BodyDirection.etc:
      return ['필요한 촬영 구도로 자유롭게 위치를 조정하세요.', height, distance];
  }
}
