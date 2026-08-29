/// 특정 날짜에 촬영한 사진 묶음.
///
/// 하나의 촬영 기록은 특정 날짜에 촬영한 사진 묶음을 의미한다.
/// 개별 사진은 [BodyPhoto]로 분리되어 recordId로 이 기록을 참조한다.
class PhotoRecord {
  final String id;

  /// 촬영일 (사용자가 지정, 갤러리 등록 시 EXIF에서 제안 가능).
  final DateTime shotAt;

  /// 촬영 대상 라벨 (선택). 비어 있으면 본인 기록으로 본다.
  ///
  /// 본인 외의 사람을 찍었을 때 타임라인에서 구분하기 위한 자유 문자열이다.
  final String? label;

  /// 기록 메모 (선택).
  final String? memo;

  /// 등록일.
  final DateTime createdAt;

  /// 수정일.
  final DateTime updatedAt;

  const PhotoRecord({
    required this.id,
    required this.shotAt,
    this.label,
    this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  PhotoRecord copyWith({
    DateTime? shotAt,
    String? label,
    bool clearLabel = false,
    String? memo,
    bool clearMemo = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PhotoRecord(
      id: id,
      shotAt: shotAt ?? this.shotAt,
      label: clearLabel ? null : (label ?? this.label),
      // null은 "바꾸지 않음"이므로 비우려면 clearMemo를 써야 한다.
      memo: clearMemo ? null : (memo ?? this.memo),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shot_at': shotAt.millisecondsSinceEpoch,
      'label': label,
      'memo': memo,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PhotoRecord.fromMap(Map<String, dynamic> map) {
    return PhotoRecord(
      id: map['id'] as String,
      shotAt: DateTime.fromMillisecondsSinceEpoch(map['shot_at'] as int),
      label: map['label'] as String?,
      memo: map['memo'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) => other is PhotoRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
