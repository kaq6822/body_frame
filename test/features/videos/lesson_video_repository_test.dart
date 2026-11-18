import 'dart:io';

import 'package:bodymark/core/database/app_database.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/repositories/lesson_video_repository.dart';
import 'package:bodymark/core/repositories/photo_record_repository.dart';
import 'package:bodymark/core/services/photo_storage_service.dart';
import 'package:bodymark/core/services/video_storage_service.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/members/member_repository.dart';
import 'package:bodymark/features/settings/services/storage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final at = DateTime(2026, 11, 4, 15);

PhotoRecord lesson(String id, {String memberId = 'a'}) => PhotoRecord(
  id: id,
  memberId: memberId,
  shotAt: at,
  createdAt: at,
  updatedAt: at,
);

void main() {
  late Directory root;
  late AppDatabase database;
  late PhotoStorageService photos;
  late VideoStorageService videos;
  late MemberRepository members;
  late LessonVideoRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bodymark_videos_repo_');
    database = AppDatabase.forTesting();
    photos = PhotoStorageServiceImpl(rootPath: root.path);
    videos = VideoStorageServiceImpl(rootPath: root.path);
    members = SqliteMemberRepository(database, photos, videos);
    repo = LessonVideoRepositoryImpl(database: database, storage: videos);
    for (final id in ['a', 'b']) {
      await members.save(
        Member(id: id, name: id, createdAt: at, updatedAt: at),
      );
    }
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  Future<LessonVideo> storedVideo(String id, String recordId) async {
    final src = File(p.join(root.path, '$id.mp4'));
    await src.writeAsBytes([1, 2, 3, 4], flush: true);
    final path = await videos.saveOriginal(
      capturedAt: at,
      sourcePath: src.path,
    );
    return LessonVideo(
      id: id,
      recordId: recordId,
      filePath: path,
      phase: 'after',
      durationMs: 65000,
      sizeBytes: 4,
      capturedAt: at.add(const Duration(minutes: 5)),
      source: LessonVideoSource.camera,
      createdAt: at,
    );
  }

  test('동영상만 있는 레슨도 저장하고 상대경로와 메타데이터를 남긴다', () async {
    final v = await storedVideo('v1', 'r1');
    await members.saveLesson(lesson('r1'), const [], addedVideos: [v]);

    final row = (await (await database.database).query(
      AppDatabase.tableLessonVideos,
    )).single;
    expect(row['file_path'], matches(RegExp(r'^videos/202611/[^/]+\.mp4$')));
    final listed = (await repo.listByRecord('r1')).single;
    expect(listed.filePath, v.filePath);
    expect(listed.phase, 'after');
    expect(listed.duration, const Duration(seconds: 65));
    expect(listed.sizeBytes, 4);
    expect(listed.source, LessonVideoSource.camera);
    expect(listed.capturedAt, at.add(const Duration(minutes: 5)));
    expect((await repo.listAll()).single.id, 'v1');

    // 기존 동영상이 있으면 일지를 비워 다시 저장해도 거부하지 않는다.
    await members.saveLesson(lesson('r1'), const []);
  });

  test('앱 동영상 저장소 밖 경로와 다른 기록 소속은 거부한다', () async {
    final outside = File(p.join(root.path, 'cache.mp4'));
    await outside.writeAsBytes([1]);
    final bad = LessonVideo(
      id: 'x',
      recordId: 'r1',
      filePath: outside.path,
      source: LessonVideoSource.gallery,
      createdAt: at,
    );
    await expectLater(
      members.saveLesson(lesson('r1'), const [], addedVideos: [bad]),
      throwsA(anything),
    );
    final v = await storedVideo('v1', 'other');
    await expectLater(
      members.saveLesson(lesson('r1'), const [], addedVideos: [v]),
      throwsArgumentError,
    );
    expect(
      await (await database.database).query(AppDatabase.tablePhotoRecords),
      isEmpty,
    );
  });

  test('개별 삭제는 행과 파일을 함께 지운다', () async {
    final v = await storedVideo('v1', 'r1');
    final keep = await storedVideo('v2', 'r1');
    await members.saveLesson(lesson('r1'), const [], addedVideos: [v, keep]);

    await repo.delete('v1');

    expect(await File(v.filePath).exists(), isFalse);
    expect(await File(keep.filePath).exists(), isTrue);
    expect((await repo.listByRecord('r1')).map((e) => e.id), ['v2']);
  });

  test('레슨 기록 삭제는 cascade로 남는 동영상 파일까지 지운다', () async {
    final v = await storedVideo('v1', 'r1');
    await members.saveLesson(lesson('r1'), const [], addedVideos: [v]);
    final records = PhotoRecordRepositoryImpl(
      database: database,
      storage: photos,
      videoStorage: videos,
    );

    await records.delete('r1');

    expect(await File(v.filePath).exists(), isFalse);
    expect(await repo.listAll(), isEmpty);
  });

  test('회원 삭제는 그 회원 레슨의 동영상 파일만 지운다', () async {
    final mine = await storedVideo('v1', 'r1');
    final other = await storedVideo('v2', 'r2');
    await members.saveLesson(lesson('r1'), const [], addedVideos: [mine]);
    await members.saveLesson(
      lesson('r2', memberId: 'b'),
      const [],
      addedVideos: [other],
    );

    await members.delete('a');

    expect(await File(mine.filePath).exists(), isFalse);
    expect(await File(other.filePath).exists(), isTrue);
    expect((await repo.listAll()).map((e) => e.id), ['v2']);
  });

  test('경로가 망가진 행은 목록에서 건너뛰고 저장 공간 개수에는 센다', () async {
    final v = await storedVideo('v1', 'r1');
    await members.saveLesson(lesson('r1'), const [], addedVideos: [v]);
    await (await database.database).insert(AppDatabase.tableLessonVideos, {
      'id': 'bad',
      'record_id': 'r1',
      'file_path': '../../etc/passwd',
      'source': 'gallery',
      'created_at': at.millisecondsSinceEpoch,
    });

    expect((await repo.listAll()).map((e) => e.id), ['v1']);
    expect((await repo.listByRecord('r1')).map((e) => e.id), ['v1']);
    expect(await repo.getById('bad'), isNull);

    final report = await StorageStatsServiceImpl(
      database: database,
      storage: photos,
      videoStorage: videos,
    ).collect();
    expect(report.totalVideoCount, 2);
    expect(report.videoBytes, 4);
    expect(report.byMonth.single.videoCount, 2);
  });
}
