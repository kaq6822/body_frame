import '../../core/models/models.dart';

/// 전후 비교 화면에서 반복적으로 필요한 순수 로직.
///
/// 위젯에 의존하지 않으므로 단위 테스트로 직접 검증한다.

/// [beforePhotos]와 [afterPhotos] 양쪽에 모두 존재하는 촬영 방향만
/// [BodyDirection] 정의 순서대로 반환한다. 동일한 촬영 방향끼리
/// 비교하는 것을 기본으로 한다.
List<BodyDirection> commonDirections(
  List<BodyPhoto> beforePhotos,
  List<BodyPhoto> afterPhotos,
) {
  final beforeSet = beforePhotos.map((p) => p.direction).toSet();
  final afterSet = afterPhotos.map((p) => p.direction).toSet();
  final common = beforeSet.intersection(afterSet);
  return BodyDirection.values.where(common.contains).toList();
}

/// [photos] 중 [direction]과 일치하는 첫 번째 사진. 없으면 null.
BodyPhoto? photoForDirection(List<BodyPhoto> photos, BodyDirection direction) {
  for (final photo in photos) {
    if (photo.direction == direction) return photo;
  }
  return null;
}

/// 방향별로 이전/이후 양쪽에 사진이 모두 존재하는지 여부.
///
/// 비교 방향 선택 화면에서 선택 가능/비활성 상태를 판단하는 데 쓴다.
bool directionAvailable(
  List<BodyPhoto> beforePhotos,
  List<BodyPhoto> afterPhotos,
  BodyDirection direction,
) {
  return photoForDirection(beforePhotos, direction) != null &&
      photoForDirection(afterPhotos, direction) != null;
}

/// 이미 고른 두 사진과 같은 수업 단계(phase)의 사진 중에서, 양쪽 기록에 모두
/// 있는 방향.
///
/// 같은 레슨의 수업 전·후를 비교할 때 방향을 바꿔도 단계가 섞이지 않게
/// 단계를 고정한 채로 방향만 고른다.
List<BodyDirection> pairedDirections({
  required List<BodyPhoto> beforePhotos,
  required String beforePhase,
  required List<BodyPhoto> afterPhotos,
  required String afterPhase,
}) {
  return commonDirections(
    beforePhotos.where((p) => p.phase == beforePhase).toList(),
    afterPhotos.where((p) => p.phase == afterPhase).toList(),
  );
}

/// [photos] 중 [phase] 단계의 [direction] 사진. 없으면 null.
BodyPhoto? photoForPhaseDirection(
  List<BodyPhoto> photos,
  String phase,
  BodyDirection direction,
) {
  return photoForDirection(
    photos.where((p) => p.phase == phase).toList(),
    direction,
  );
}
