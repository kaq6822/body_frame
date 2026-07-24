import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';

/// 촬영 방향 선택 → 격자 카메라 → 촬영 결과 확인 화면 사이에서 공유하는
/// 임시 촬영 세션 상태.
///
/// 화면 간 임시 촬영 데이터는 쿼리 파라미터 대신 Riverpod 상태로
/// 전달한다. `.family`로 회원별로 분리하고
/// `.autoDispose`로 촬영 흐름을 완전히 벗어나면 초기화되게 한다.
class CaptureSessionState {
  final BodyDirection direction;
  final String? capturedImagePath;
  final GridSettings? gridSettingsAtCapture;
  final DateTime shotDate;
  final String? memo;

  const CaptureSessionState({
    this.direction = BodyDirection.front,
    this.capturedImagePath,
    this.gridSettingsAtCapture,
    required this.shotDate,
    this.memo,
  });

  CaptureSessionState copyWith({
    BodyDirection? direction,
    String? capturedImagePath,
    bool clearCapturedImage = false,
    GridSettings? gridSettingsAtCapture,
    DateTime? shotDate,
    String? memo,
    bool clearMemo = false,
  }) {
    return CaptureSessionState(
      direction: direction ?? this.direction,
      capturedImagePath:
          clearCapturedImage ? null : (capturedImagePath ?? this.capturedImagePath),
      gridSettingsAtCapture: clearCapturedImage
          ? null
          : (gridSettingsAtCapture ?? this.gridSettingsAtCapture),
      shotDate: shotDate ?? this.shotDate,
      memo: clearMemo ? null : (memo ?? this.memo),
    );
  }
}

class CaptureSessionNotifier extends StateNotifier<CaptureSessionState> {
  CaptureSessionNotifier() : super(CaptureSessionState(shotDate: _today()));

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void selectDirection(BodyDirection direction) {
    state = state.copyWith(direction: direction);
  }

  void setCapturedImage(String path, {GridSettings? gridSettings}) {
    state = state.copyWith(
      capturedImagePath: path,
      gridSettingsAtCapture: gridSettings,
    );
  }

  void clearCapturedImage() {
    state = state.copyWith(clearCapturedImage: true);
  }

  void setShotDate(DateTime date) {
    state = state.copyWith(shotDate: DateTime(date.year, date.month, date.day));
  }

  void setMemo(String? memo) {
    state = state.copyWith(memo: memo, clearMemo: memo == null);
  }

  /// 저장 완료 등으로 세션을 초기 상태로 되돌린다(다음 촬영을 위해).
  void reset() {
    state = CaptureSessionState(shotDate: _today());
  }
}

final captureSessionProvider = StateNotifierProvider.autoDispose
    .family<CaptureSessionNotifier, CaptureSessionState, String>(
  (ref, memberId) => CaptureSessionNotifier(),
);
