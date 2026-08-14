import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';

/// 한 세션에서 순서대로 촬영하는 방향. 정면 → 좌측면 → 우측면 → 후면.
const List<BodyDirection> kSessionDirections = [
  BodyDirection.front,
  BodyDirection.leftSide,
  BodyDirection.rightSide,
  BodyDirection.back,
];

/// 세션 안의 방향 1개에 대한 촬영 결과.
///
/// [imagePath]가 null이면 아직 찍지 않았거나 건너뛴 단계다. 촬영 원본은 카메라가
/// 반환한 임시 파일 경로이며, 저장 시점에 앱 저장소로 복사한다.
class CaptureShot {
  final BodyDirection direction;
  final String? imagePath;
  final GridSettings? gridSettingsAtCapture;

  const CaptureShot({
    required this.direction,
    this.imagePath,
    this.gridSettingsAtCapture,
  });

  bool get isCaptured => imagePath != null;

  CaptureShot copyWith({
    String? imagePath,
    bool clearImage = false,
    GridSettings? gridSettingsAtCapture,
  }) {
    return CaptureShot(
      direction: direction,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      gridSettingsAtCapture: clearImage
          ? null
          : (gridSettingsAtCapture ?? this.gridSettingsAtCapture),
    );
  }
}

/// 연속 촬영 세션 상태.
///
/// 카메라 화면과 리뷰 화면이 공유하는 임시 상태다. 화면 간 임시 촬영 데이터는
/// 쿼리 파라미터 대신 Riverpod 상태로 전달하고, `.autoDispose`로 촬영 흐름을
/// 완전히 벗어나면 초기화되게 한다.
class CaptureSessionState {
  /// [kSessionDirections]와 같은 순서·길이를 유지한다.
  final List<CaptureShot> shots;

  /// 카메라 화면이 현재 촬영 중인 단계.
  final int currentIndex;

  final DateTime shotDate;

  /// 촬영 대상 라벨(선택). 비어 있으면 본인 기록으로 본다.
  final String? label;

  final String? memo;

  const CaptureSessionState({
    required this.shots,
    this.currentIndex = 0,
    required this.shotDate,
    this.label,
    this.memo,
  });

  CaptureShot get current => shots[currentIndex];

  /// 실제로 찍힌 컷만.
  List<CaptureShot> get capturedShots =>
      shots.where((shot) => shot.isCaptured).toList();

  int get capturedCount => capturedShots.length;

  bool get hasAnyCapture => capturedCount > 0;

  bool get isLastStep => currentIndex >= shots.length - 1;

  /// 아직 찍지 않은 다음 단계. 없으면 null.
  int? get nextUncapturedIndex {
    for (var i = currentIndex + 1; i < shots.length; i++) {
      if (!shots[i].isCaptured) return i;
    }
    return null;
  }

  CaptureSessionState copyWith({
    List<CaptureShot>? shots,
    int? currentIndex,
    DateTime? shotDate,
    String? label,
    bool clearLabel = false,
    String? memo,
    bool clearMemo = false,
  }) {
    return CaptureSessionState(
      shots: shots ?? this.shots,
      currentIndex: currentIndex ?? this.currentIndex,
      shotDate: shotDate ?? this.shotDate,
      label: clearLabel ? null : (label ?? this.label),
      memo: clearMemo ? null : (memo ?? this.memo),
    );
  }
}

class CaptureSessionNotifier extends StateNotifier<CaptureSessionState> {
  CaptureSessionNotifier() : super(_initial());

  static CaptureSessionState _initial() {
    return CaptureSessionState(
      shots: [
        for (final direction in kSessionDirections)
          CaptureShot(direction: direction),
      ],
      shotDate: _today(),
    );
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// 현재 단계의 촬영 결과를 기록하고 아직 안 찍은 다음 단계로 넘어간다.
  /// 남은 단계가 없으면 현재 단계에 머문다(호출부가 리뷰로 이동시킨다).
  ///
  /// 이미 찍힌 단계를 다시 찍으면 **밀려난 이전 임시 파일 경로**를 돌려준다.
  /// 그 파일은 더 이상 세션에 없어 저장 시점의 정리 대상에도 들지 않으므로,
  /// 호출부가 받아서 지워야 카메라 캐시에 고아 파일이 남지 않는다.
  String? captureCurrent(String path, {GridSettings? gridSettings}) {
    final replaced = state.shots[state.currentIndex].imagePath;
    final shots = [...state.shots];
    shots[state.currentIndex] = shots[state.currentIndex].copyWith(
      imagePath: path,
      gridSettingsAtCapture: gridSettings,
    );
    final next = state.copyWith(shots: shots).nextUncapturedIndex;
    state = state.copyWith(
      shots: shots,
      currentIndex: next ?? state.currentIndex,
    );
    return replaced == path ? null : replaced;
  }

  /// 현재 단계를 찍지 않고 넘어간다. 남은 단계가 없으면 그대로 둔다.
  void skipCurrent() {
    final next = state.nextUncapturedIndex;
    if (next == null) return;
    state = state.copyWith(currentIndex: next);
  }

  /// 특정 단계로 직접 이동한다(재촬영 등).
  void goTo(int index) {
    if (index < 0 || index >= state.shots.length) return;
    state = state.copyWith(currentIndex: index);
  }

  /// 특정 단계의 촬영 결과를 지운다.
  void clearShot(int index) {
    if (index < 0 || index >= state.shots.length) return;
    final shots = [...state.shots];
    shots[index] = shots[index].copyWith(clearImage: true);
    state = state.copyWith(shots: shots);
  }

  void setShotDate(DateTime date) {
    state = state.copyWith(shotDate: DateTime(date.year, date.month, date.day));
  }

  void setLabel(String? label) {
    final trimmed = label?.trim();
    final isEmpty = trimmed == null || trimmed.isEmpty;
    state = state.copyWith(label: trimmed, clearLabel: isEmpty);
  }

  void setMemo(String? memo) {
    final trimmed = memo?.trim();
    final isEmpty = trimmed == null || trimmed.isEmpty;
    state = state.copyWith(memo: trimmed, clearMemo: isEmpty);
  }

  /// 저장 완료 등으로 세션을 초기 상태로 되돌린다(다음 촬영을 위해).
  void reset() {
    state = _initial();
  }
}

final captureSessionProvider =
    StateNotifierProvider.autoDispose<
      CaptureSessionNotifier,
      CaptureSessionState
    >((ref) => CaptureSessionNotifier());
