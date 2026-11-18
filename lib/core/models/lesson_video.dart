/// 레슨 동영상의 출처.
enum LessonVideoSource {
  camera,
  gallery;

  static LessonVideoSource fromKey(String? key) =>
      key == gallery.name ? gallery : camera;
}

/// 레슨에 첨부한 동영상.
///
/// 사진과 마찬가지로 파일 자체는 DB에 넣지 않는다. [filePath]는 실행 중 해석된
/// 절대경로이고, 영속화할 때는 리포지토리가 `videos/{yyyyMM}/...` 상대경로로
/// 바꾼다. 원본은 트랜스코딩·압축·자르기 없이 그대로 보관한다.
///
/// 비교·방향·격자 로직은 사진 전제라 [BodyPhoto]와 섞지 않는다.
class LessonVideo {
  final String id;
  final String recordId;
  final String filePath;
  final String phase;

  /// 재생 길이. 알 수 없으면 null.
  final int? durationMs;

  /// 원본 파일 크기. 알 수 없으면 null.
  final int? sizeBytes;

  /// 실제 촬영 일시. 갤러리에서 고른 파일은 알 수 없으면 null.
  final DateTime? capturedAt;
  final LessonVideoSource source;
  final String? memo;

  /// 작성(등록) 일시.
  final DateTime createdAt;

  const LessonVideo({
    required this.id,
    required this.recordId,
    required this.filePath,
    this.phase = 'regular',
    this.durationMs,
    this.sizeBytes,
    this.capturedAt,
    required this.source,
    this.memo,
    required this.createdAt,
  });

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  LessonVideo copyWith({String? filePath}) => LessonVideo(
    id: id,
    recordId: recordId,
    filePath: filePath ?? this.filePath,
    phase: phase,
    durationMs: durationMs,
    sizeBytes: sizeBytes,
    capturedAt: capturedAt,
    source: source,
    memo: memo,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'record_id': recordId,
    'file_path': filePath,
    'phase': phase,
    'duration_ms': durationMs,
    'size_bytes': sizeBytes,
    'captured_at': capturedAt?.millisecondsSinceEpoch,
    'source': source.name,
    'memo': memo,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory LessonVideo.fromMap(Map<String, dynamic> map) => LessonVideo(
    id: map['id'] as String,
    recordId: map['record_id'] as String,
    filePath: map['file_path'] as String,
    phase: map['phase'] as String? ?? 'regular',
    durationMs: map['duration_ms'] as int?,
    sizeBytes: map['size_bytes'] as int?,
    capturedAt: map['captured_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['captured_at'] as int),
    source: LessonVideoSource.fromKey(map['source'] as String?),
    memo: map['memo'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  @override
  bool operator ==(Object other) => other is LessonVideo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
