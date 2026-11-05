import 'dart:io';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/features/capture/providers/capture_providers.dart';
import 'package:bodymark/features/compare/compare_providers.dart';
import 'package:bodymark/features/members/member_providers.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../compare/fakes.dart';

final at = DateTime(2026, 11, 4, 15);
void main() {
  late Directory root;
  late FakePhotoRecordRepository records;
  late FakeBodyPhotoRepository photos;
  late ProviderContainer container;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bodymark_context_');
    records = FakePhotoRecordRepository();
    photos = FakeBodyPhotoRepository();
    for (final id in ['a', 'b']) {
      await records.insert(
        PhotoRecord(
          id: id,
          memberId: id,
          shotAt: at,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    for (final id in ['a', 'b']) {
      final f = await File('${root.path}/$id.jpg').writeAsBytes([1]);
      await photos.insert(
        BodyPhoto(
          id: id,
          recordId: id,
          filePath: f.path,
          direction: BodyDirection.front,
          createdAt: at,
        ),
      );
    }
    container = ProviderContainer(
      overrides: [
        photoRecordRepositoryProvider.overrideWithValue(records),
        bodyPhotoRepositoryProvider.overrideWithValue(photos),
        timelineProvider.overrideWith((ref) async => []),
        gridSettingsServiceProvider.overrideWithValue(
          FakeGridSettingsService(),
        ),
      ],
    );
    for (final d in [BodyDirection.front, BodyDirection.back]) {
      container.listen(previousPhotoGuidePathProvider(d), (_, _) {});
    }
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });
  test('다른 회원의 사진은 촬영 기준으로 노출하지 않는다', () async {
    container.read(lessonCaptureContextProvider.notifier).state =
        const LessonCaptureContext('a', baselineRecordId: 'a');
    expect(
      await container.read(
        previousPhotoGuidePathProvider(BodyDirection.front).future,
      ),
      '${root.path}/a.jpg',
    );
  });
  test('저장 전 사진도 같은 방향만 기준으로 쓰고 기준 없음은 숨긴다', () async {
    container
        .read(lessonCaptureContextProvider.notifier)
        .state = LessonCaptureContext(
      'a',
      baselinePhotos: {BodyDirection.front: '${root.path}/a.jpg'},
    );
    expect(
      await container.read(
        previousPhotoGuidePathProvider(BodyDirection.front).future,
      ),
      '${root.path}/a.jpg',
    );
    expect(
      await container.read(
        previousPhotoGuidePathProvider(BodyDirection.back).future,
      ),
      isNull,
    );
    container.read(lessonCaptureContextProvider.notifier).state =
        const LessonCaptureContext('a', useBaseline: false);
    expect(
      await container.read(
        previousPhotoGuidePathProvider(BodyDirection.front).future,
      ),
      isNull,
    );
  });
  test('다른 회원의 비교를 차단한다', () async {
    await expectLater(
      container.read(
        compareViewBundleProvider((
          beforePhotoId: 'a',
          afterPhotoId: 'b',
        )).future,
      ),
      throwsStateError,
    );
  });
  test('같은 레슨의 다른 수업 전·후 사진은 비교한다', () async {
    await photos.insert(
      BodyPhoto(
        id: 'after',
        recordId: 'a',
        phase: 'after',
        filePath: '${root.path}/a.jpg',
        direction: BodyDirection.front,
        createdAt: at,
      ),
    );
    final bundle = await container.read(
      compareViewBundleProvider((
        beforePhotoId: 'a',
        afterPhotoId: 'after',
      )).future,
    );
    expect(bundle.beforeRecord.id, bundle.afterRecord.id);
    expect(bundle.beforePhoto.id, isNot(bundle.afterPhoto.id));
  });
}
