import '../../core/models/models.dart';

/// 저장된 동영상 [videoId]를 지우면 레슨에 아무 내용도 남지 않는지.
///
/// 내용이 없는 레슨은 다시 저장할 수 없으므로, 그때는 동영상만 지우지 않고
/// 레슨 삭제를 제안한다. 사진·동영상 목록을 아직 못 읽었으면(null) 빈 레슨으로
/// 단정하지 않는다.
bool deletingVideoLeavesLessonEmpty({
  required String videoId,
  required List<BodyPhoto>? photos,
  required List<LessonVideo>? videos,
  required String? memo,
  required String? condition,
}) {
  if (photos == null || videos == null) return false;
  return photos.isEmpty &&
      videos.length == 1 &&
      videos.single.id == videoId &&
      (memo ?? '').trim().isEmpty &&
      (condition ?? '').trim().isEmpty;
}
