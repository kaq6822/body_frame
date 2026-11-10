import 'package:bodymark/core/models/models.dart';

/// 촬영 화면에 상시 보이는 방향별 한 줄 안내.
///
/// 뷰파인더를 가리지 않도록 한 문장만 둔다. 카메라 높이·거리·이전 사진 활용 같은
/// 자세한 내용은 촬영 가이드 화면([captureGuideSteps])에 있다.
String captureHint(BodyDirection direction) => switch (direction) {
  BodyDirection.front => '정면을 보고 머리와 발이 모두 보이게 맞춰주세요',
  BodyDirection.leftSide => '왼쪽 옆모습이 보이게 서서 머리와 발을 맞춰주세요',
  BodyDirection.rightSide => '오른쪽 옆모습이 보이게 서서 머리와 발을 맞춰주세요',
  BodyDirection.back => '뒷모습이 보이게 서서 머리와 발을 맞춰주세요',
  BodyDirection.etc => '필요한 구도로 머리와 발이 모두 보이게 맞춰주세요',
};

/// 촬영 가이드 화면의 단계(제목, 본문). 반복 촬영의 일관성을 위한 조건이다.
const List<(String, String)> captureGuideSteps = [
  (
    '카메라 높이와 수평 맞추기',
    '카메라를 가슴 높이에 두고 이전 촬영과 같은 높이를 유지해요. 화면의 수평계가 '
        '청록색으로 바뀌면 기기가 수평이에요.',
  ),
  (
    '머리와 발끝 맞추기',
    '약 2~3m 거리에서 머리와 발이 모두 보이게 서요. 화면의 머리 상단선과 발끝 '
        '기준선 안에 전신이 들어오게 하고, 두 발 사이를 중앙 세로선에 맞춰요.',
  ),
  (
    '이전 사진 참고하기',
    '같은 회원의 같은 방향 사진이 반투명하게 겹쳐 보여요. 위치와 크기를 참고해 '
        '휴대폰의 거리와 각도를 조절해요. 앱이 몸을 자동으로 정렬하거나 보정하지는 않아요.',
  ),
];
