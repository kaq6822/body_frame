import 'package:bodymark/core/services/tick_haptic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 확인 진동이 플랫폼마다 실제로 울리는 종류로 나가는지 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('Android는 세기와 상관없이 LONG_PRESS로 가는 vibrate를 쓴다', () async {
    tickHaptic(platform: TargetPlatform.android);
    tickHaptic(strong: true, platform: TargetPlatform.android);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), [
      'HapticFeedback.vibrate',
      'HapticFeedback.vibrate',
    ]);
    expect(calls.map((c) => c.arguments), [null, null]);
  });

  test('iOS는 약하면 lightImpact, 강하면 heavyImpact를 쓴다', () async {
    tickHaptic(platform: TargetPlatform.iOS);
    tickHaptic(strong: true, platform: TargetPlatform.iOS);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.arguments), [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });
}
