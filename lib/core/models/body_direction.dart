/// 체형 사진 촬영 방향.
///
/// MVP.md 4.2: 측면을 하나로 통합하지 않고 좌측면/우측면을 구분한다.
enum BodyDirection {
  front,
  leftSide,
  rightSide,
  back,
  etc;

  /// DB/JSON 직렬화에 사용하는 안정적인 문자열 키.
  String get key => name;

  /// 화면 표시용 한국어 라벨.
  String get label {
    switch (this) {
      case BodyDirection.front:
        return '정면';
      case BodyDirection.leftSide:
        return '좌측면';
      case BodyDirection.rightSide:
        return '우측면';
      case BodyDirection.back:
        return '후면';
      case BodyDirection.etc:
        return '기타';
    }
  }

  /// 문자열 키로부터 enum 복원. 알 수 없는 값은 [etc]로 처리한다.
  static BodyDirection fromKey(String? key) {
    return BodyDirection.values.firstWhere(
      (d) => d.key == key,
      orElse: () => BodyDirection.etc,
    );
  }
}
