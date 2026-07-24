/// 촬영 기록. MVP.md 6.1 / 14장 '촬영 기록'.
///
/// 하나의 촬영 기록은 특정 날짜에 촬영한 사진 묶음을 의미한다.
/// 개별 사진은 [BodyPhoto]로 분리되어 recordId로 이 기록을 참조한다.
class PhotoRecord {
  final String id;

  /// 소속 회원 식별자.
  final String memberId;

  /// 촬영일 (사용자가 지정, 갤러리 등록 시 EXIF에서 제안 가능).
  final DateTime shotAt;

  /// 기록 메모 (선택).
  final String? memo;

  /// 등록일.
  final DateTime createdAt;

  /// 수정일.
  final DateTime updatedAt;

  const PhotoRecord({
    required this.id,
    required this.memberId,
    required this.shotAt,
    this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  PhotoRecord copyWith({
    String? memberId,
    DateTime? shotAt,
    String? memo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PhotoRecord(
      id: id,
      memberId: memberId ?? this.memberId,
      shotAt: shotAt ?? this.shotAt,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'member_id': memberId,
      'shot_at': shotAt.millisecondsSinceEpoch,
      'memo': memo,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PhotoRecord.fromMap(Map<String, dynamic> map) {
    return PhotoRecord(
      id: map['id'] as String,
      memberId: map['member_id'] as String,
      shotAt: DateTime.fromMillisecondsSinceEpoch(map['shot_at'] as int),
      memo: map['memo'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) => other is PhotoRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
