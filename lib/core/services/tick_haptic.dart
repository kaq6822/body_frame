import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 짧은 확인 진동(수평 잠금, 타이머 카운트다운).
///
/// Android에서 Flutter의 `selectionClick`·`lightImpact`·`heavyImpact`는 각각
/// CLOCK_TICK·VIRTUAL_KEY·CONTEXT_CLICK으로 보낸다. 삼성 보급형(기본 진동 모터,
/// SM-A235N 실측)은 앱이 보낸 이 종류를 시스템에서 버리고 LONG_PRESS만 울린다.
/// 그래서 Android는 LONG_PRESS로 가는 [HapticFeedback.vibrate]를 쓴다. iOS의
/// `vibrate`는 0.4초짜리 강한 진동이라 확인 신호로는 지나쳐 [strong]에 따라
/// impact 계열을 쓴다.
void tickHaptic({bool strong = false, TargetPlatform? platform}) {
  final target = platform ?? defaultTargetPlatform;
  final Future<void> feedback = switch (target) {
    TargetPlatform.android => HapticFeedback.vibrate(),
    _ => strong ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact(),
  };
  unawaited(feedback);
}
