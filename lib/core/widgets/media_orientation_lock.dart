import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/capture/providers/capture_providers.dart';

/// 보고 있는 사진·동영상의 방향에 화면 방향을 맞춘다.
///
/// 세로로 찍은 미디어는 화면을 가로로 돌리면 좌우가 비고 작게만 보인다. 그래서
/// 세로 미디어([aspectRatio] < 1)를 보는 동안에는 세로로 고정하고, 가로
/// 미디어일 때만 회전을 허용한다. 비율을 아직 모르면(null) 아무것도 바꾸지 않는다.
/// 화면을 떠나면 앱 기본값(모든 방향)으로 되돌린다.
class MediaOrientationLock extends ConsumerStatefulWidget {
  /// 표시 기준 가로/세로 비율. 모르면 null.
  final double? aspectRatio;
  final Widget child;

  const MediaOrientationLock({
    super.key,
    required this.aspectRatio,
    required this.child,
  });

  /// 픽셀 크기에서 비율을 구한다. 크기를 모르면(0 이하) null.
  static double? aspectFromSize(int width, int height) =>
      width > 0 && height > 0 ? width / height : null;

  @override
  ConsumerState<MediaOrientationLock> createState() =>
      _MediaOrientationLockState();
}

class _MediaOrientationLockState extends ConsumerState<MediaOrientationLock> {
  late final ScreenOrientationLock _lock;

  /// 마지막으로 적용한 상태. null이면 아직 아무것도 바꾸지 않았다.
  bool? _portrait;

  @override
  void initState() {
    super.initState();
    _lock = ref.read(screenOrientationLockProvider);
    _apply();
  }

  @override
  void didUpdateWidget(MediaOrientationLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply();
  }

  void _apply() {
    final aspect = widget.aspectRatio;
    if (aspect == null || !aspect.isFinite || aspect <= 0) return;
    final portrait = aspect < 1;
    if (portrait == _portrait) return;
    _portrait = portrait;
    unawaited(
      (portrait ? _lock.lockPortrait() : _lock.restore()).catchError(
        (Object _) {},
      ),
    );
  }

  @override
  void dispose() {
    if (_portrait == true) unawaited(_lock.restore().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
