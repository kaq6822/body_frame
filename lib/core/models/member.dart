/// 회원 성별(선택 입력).
enum Gender {
  male,
  female,
  other,
  unspecified;

  String get key => name;

  String get label {
    switch (this) {
      case Gender.male:
        return '남성';
      case Gender.female:
        return '여성';
      case Gender.other:
        return '기타';
      case Gender.unspecified:
        return '선택 안 함';
    }
  }

  static Gender fromKey(String? key) {
    return Gender.values.firstWhere(
      (g) => g.key == key,
      orElse: () => Gender.unspecified,
    );
  }
}

/// 회원.
///
/// 실명 대신 별칭/회원 번호만으로도 관리 가능하므로 [name]만 필수이고
/// 나머지는 모두 선택 입력이다. [id]는 UUID 기반의 안정적 식별자다.
class Member {
  final String id;

  /// 이름 또는 식별용 별칭 (필수).
  final String name;

  /// 실행 중 해석된 대표 사진 절대경로(선택).
  ///
  /// 영속화할 때는 리포지토리가 앱 저장소 기준 상대경로로 변환한다.
  final String? avatarPath;

  final Gender gender;

  /// 생년 또는 연령대 문자열 (선택). 예: '1990', '30대'.
  final String? birth;

  /// 연락처 (선택).
  final String? contact;

  /// 메모 (선택).
  final String? memo;

  /// 등록일.
  final DateTime createdAt;

  /// 수정일.
  final DateTime updatedAt;

  const Member({
    required this.id,
    required this.name,
    this.avatarPath,
    this.gender = Gender.unspecified,
    this.birth,
    this.contact,
    this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  Member copyWith({
    String? name,
    String? avatarPath,
    bool clearAvatar = false,
    Gender? gender,
    String? birth,
    String? contact,
    String? memo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      gender: gender ?? this.gender,
      birth: birth ?? this.birth,
      contact: contact ?? this.contact,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar_path': avatarPath,
      'gender': gender.key,
      'birth': birth,
      'contact': contact,
      'memo': memo,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarPath: map['avatar_path'] as String?,
      gender: Gender.fromKey(map['gender'] as String?),
      birth: map['birth'] as String?,
      contact: map['contact'] as String?,
      memo: map['memo'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  @override
  bool operator ==(Object other) => other is Member && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
