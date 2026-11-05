/// 회원의 실제 레슨 기록. 사진과 일지는 각각 선택이다.
/// 기존 미연결 기록의 식별자와 날짜는 마이그레이션으로 유지한다.
class PhotoRecord {
  final String id;
  final String? memberId;
  final String? condition;

  /// 실제 레슨 일시. 기존 미연결 사진 기록은 종전 촬영일을 유지한다.
  final DateTime shotAt;

  /// 이전 개인 기록의 자유 라벨. 회원 이름의 대체 식별자로 사용하지 않는다.
  final String? label;

  /// 기록 메모 (선택).
  final String? memo;

  /// 등록일.
  final DateTime createdAt;

  /// 수정일.
  final DateTime updatedAt;

  const PhotoRecord({
    required this.id,
    this.memberId,
    this.condition,
    required this.shotAt,
    this.label,
    this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  PhotoRecord copyWith({
    DateTime? shotAt,
    String? memberId,
    String? condition,
    bool clearCondition = false,
    String? label,
    bool clearLabel = false,
    String? memo,
    bool clearMemo = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PhotoRecord(
      id: id,
      memberId: memberId ?? this.memberId,
      condition: clearCondition ? null : condition ?? this.condition,
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
      'member_id': memberId,
      'condition': condition,
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
      memberId: map['member_id'] as String?,
      condition: map['condition'] as String?,
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
