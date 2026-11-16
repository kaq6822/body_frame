import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/features/members/member.dart';
import 'package:bodymark/features/records/providers/records_providers.dart';

/// 2026-11-17은 화요일이다.
final now = DateTime(2026, 11, 17, 10);

Member member(String id, {String? name, DateTime? createdAt}) => Member(
  id: id,
  name: name ?? id,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  updatedAt: createdAt ?? DateTime(2026, 1, 1),
);

var _seq = 0;

RecordWithPhotos lesson(
  String? memberId,
  DateTime at, {
  String? id,
  List<String> phases = const [],
  int videos = 0,
  String? memo,
}) {
  final recordId = id ?? 'r${_seq++}';
  return RecordWithPhotos(
    record: PhotoRecord(
      id: recordId,
      memberId: memberId,
      shotAt: at,
      memo: memo,
      createdAt: at,
      updatedAt: at,
    ),
    photos: [
      for (final (i, phase) in phases.indexed)
        BodyPhoto(
          id: '$recordId.p$i',
          recordId: recordId,
          filePath: '/missing/$recordId.$i.jpg',
          direction: BodyDirection.values[i % 4],
          phase: phase,
          createdAt: at,
        ),
    ],
    videos: [
      for (var i = 0; i < videos; i++)
        LessonVideo(
          id: '$recordId.v$i',
          recordId: recordId,
          filePath: '/missing/$recordId.$i.mp4',
          source: LessonVideoSource.camera,
          createdAt: at,
        ),
    ],
  );
}
