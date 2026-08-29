import 'package:flutter/widgets.dart';

/// 체형 사진 프레임의 종횡비(가로 ÷ 세로). 세로로 긴 3:4다.
///
/// 촬영 화면과 비교 화면이 **같은 값**을 써야 한다. 격자 오버레이는 자기 부모
/// 박스 크기를 기준으로 중앙 대칭 좌표를 그리므로, 두 화면의 프레임 비율이
/// 다르면 촬영할 때 맞춘 격자와 비교할 때 보이는 격자가 몸 대비 다른 자리에
/// 놓인다. 그래서 비율을 각자 선언하지 않고 이 상수를 공유한다.
const double kPhotoFrameAspect = 3 / 4;

/// 주어진 제약 안에 [kPhotoFrameAspect] 프레임을 넘치지 않게 최대로 넣은 크기.
///
/// 폭에만 맞추면(`AspectRatio` 기본 동작) 세로 공간이 좁은 레이아웃에서 넘친다.
/// 좁은 쪽에 맞춰 줄여 항상 제약 안에 들어오게 한다.
Size fitPhotoFrame(BoxConstraints constraints) {
  final maxWidth = constraints.maxWidth;
  final maxHeight = constraints.maxHeight;

  // 양쪽이 모두 무한하면 크기를 정할 근거가 없다. 호출부가 경계를 주지 않은
  // 경우이므로 0을 돌려 그리지 않게 한다.
  if (!maxWidth.isFinite && !maxHeight.isFinite) return Size.zero;

  if (!maxWidth.isFinite) {
    return Size(maxHeight * kPhotoFrameAspect, maxHeight);
  }

  var width = maxWidth;
  var height = width / kPhotoFrameAspect;
  if (!height.isFinite || height > maxHeight) {
    height = maxHeight;
    width = height * kPhotoFrameAspect;
  }
  return Size(width, height);
}

/// 센서 종횡비를 화면 방향에 맞춘 미리보기 종횡비(가로 ÷ 세로)로 바꾼다.
///
/// `camera` 패키지의 `CameraController.value.aspectRatio`는 센서 크기를 **가로
/// 기준**으로 보고한다(예: 1280×720 → 1.78). 세로로 든 화면에 그 값을 그대로
/// 쓰면 미리보기가 납작한 띠가 되므로 역수를 취해야 한다.
///
/// 플랫폼에 따라 이미 세로 기준으로 오는 경우도 있어 긴 쪽을 가로로 정규화한
/// 뒤 방향을 적용한다. 값이 유효하지 않으면 흔한 4:3 센서로 가정한다.
double previewAspectFor({
  required double sensorAspect,
  required Orientation orientation,
}) {
  final safe = (sensorAspect.isFinite && sensorAspect > 0)
      ? sensorAspect
      : 4 / 3;
  final landscape = safe >= 1 ? safe : 1 / safe;
  return orientation == Orientation.portrait ? 1 / landscape : landscape;
}
