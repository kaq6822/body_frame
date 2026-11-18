import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/features/videos/lesson_video_content.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime(2026, 11, 4, 15);

LessonVideo _video(String id) => LessonVideo(
  id: id,
  recordId: 'r1',
  filePath: 'videos/202611/$id.mp4',
  phase: 'after',
  durationMs: 1000,
  sizeBytes: 1,
  source: LessonVideoSource.camera,
  createdAt: _at,
);

void main() {
  bool check({
    List<BodyPhoto>? photos = const [],
    List<LessonVideo>? videos,
    String? memo,
    String? condition,
    String videoId = 'v1',
  }) => deletingVideoLeavesLessonEmpty(
    videoId: videoId,
    photos: photos,
    videos: videos ?? [_video('v1')],
    memo: memo,
    condition: condition,
  );

  test('일지·사진 없이 그 동영상 하나만 있으면 빈 레슨이 된다', () {
    expect(check(), isTrue);
    expect(check(memo: '  ', condition: ''), isTrue);
  });

  test('다른 내용이 남으면 빈 레슨이 아니다', () {
    expect(check(memo: '메모'), isFalse);
    expect(check(condition: '좋음'), isFalse);
    expect(check(videos: [_video('v1'), _video('v2')]), isFalse);
    expect(check(videoId: 'v2'), isFalse);
  });

  test('사진·동영상 목록을 아직 모르면 빈 레슨으로 단정하지 않는다', () {
    expect(check(photos: null), isFalse);
    expect(
      deletingVideoLeavesLessonEmpty(
        videoId: 'v1',
        photos: const [],
        videos: null,
        memo: null,
        condition: null,
      ),
      isFalse,
    );
  });
}
