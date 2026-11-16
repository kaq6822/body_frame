import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/providers.dart';
import '../../core/services/app_logger.dart';

import '../capture/camera/video_camera_controller.dart';

/// 동영상 촬영 화면이 쓸 카메라 컨트롤러 팩토리. 테스트에서 가짜로 바꾼다.
final videoCameraControllerFactoryProvider =
    Provider<VideoCameraController Function()>(
      (ref) => DeviceVideoCameraController.new,
    );

/// 촬영 화면이 레슨 편집으로 돌려주는 임시 녹화본.
///
/// [path]는 카메라 캐시의 임시 파일이다. 레슨을 저장할 때 앱 저장소로 복사하고,
/// 저장하지 않고 나가면 편집 화면이 지운다.
class RecordedVideo {
  final String path;
  final Duration duration;
  final DateTime capturedAt;
  const RecordedVideo({
    required this.path,
    required this.duration,
    required this.capturedAt,
  });
}

/// 재생 화면이 의존하는 재생기 경계. `video_player`는 플랫폼 채널을 타므로
/// 테스트에서는 [lessonVideoPlayerFactoryProvider]를 가짜로 바꾼다.
abstract class LessonVideoPlayer implements Listenable {
  /// 파일을 연다. 열지 못하면 예외를 던진다.
  Future<void> initialize();

  bool get isInitialized;
  bool get isPlaying;

  /// 표시 종횡비(가로 ÷ 세로). 회전 정보가 반영된 값이다.
  double get aspectRatio;
  Duration get position;
  Duration get duration;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  Widget buildView();

  Future<void> dispose();
}

class DeviceLessonVideoPlayer implements LessonVideoPlayer {
  final VideoPlayerController _controller;
  DeviceLessonVideoPlayer(String path)
    : _controller = VideoPlayerController.file(File(path));

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    if (_controller.value.hasError) {
      throw StateError('동영상을 열 수 없습니다.');
    }
  }

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  double get aspectRatio {
    final ratio = _controller.value.aspectRatio;
    return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
  }

  @override
  Duration get position => _controller.value.position;

  @override
  Duration get duration => _controller.value.duration;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> dispose() => _controller.dispose();
}

final lessonVideoPlayerFactoryProvider =
    Provider<LessonVideoPlayer Function(String path)>(
      (ref) => DeviceLessonVideoPlayer.new,
    );

/// 동영상 파일의 길이를 읽는 경계. 갤러리에서 고른 파일은 길이를 모르므로
/// 저장 전에 재생기로 한 번 열어 확인한다. 실패하면 null(길이 미표시).
final videoDurationProbeProvider =
    Provider<Future<Duration?> Function(String path)>((ref) {
      final factory = ref.watch(lessonVideoPlayerFactoryProvider);
      return (path) async {
        final player = factory(path);
        try {
          await player.initialize();
          final d = player.duration;
          return d > Duration.zero ? d : null;
        } catch (_) {
          return null;
        } finally {
          await player.dispose();
        }
      };
    });

/// 저장 전 동영상의 파일 크기를 읽는 경계. 읽지 못하면 null(용량 미표시).
final videoFileSizeProvider = Provider<Future<int?> Function(String path)>(
  (ref) => (path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  },
);

/// image_picker가 갤러리 동영상을 복사해 두는 앱 임시 디렉터리들.
///
/// Android는 `getTemporaryDirectory()`(cache)에 사본을 만든다. iOS는 사본을 앱
/// 컨테이너의 `tmp/`에 두는데 `getTemporaryDirectory()`는 `Library/Caches`를
/// 가리키므로, 같은 컨테이너의 `tmp/`도 함께 허용한다. 둘 다 앱 전용 임시
/// 공간이라 사용자의 갤러리 원본은 여기에 없다.
final pickerCopyRootsProvider = Provider<Future<List<String>> Function()>(
  (ref) => () async {
    final temp = (await getTemporaryDirectory()).path;
    return [
      temp,
      if (Platform.isIOS) p.join(p.dirname(p.dirname(temp)), 'tmp'),
    ];
  },
);

/// [path]가 [roots] 안의 파일일 때만 지운다. 갤러리 원본은 절대 건드리지 않는다.
///
/// GB 단위 동영상의 picker 사본이 캐시에 남으면 저장 공간을 두 배로 쓴다.
/// 삭제 실패는 화면 흐름을 막지 않는다.
Future<void> deletePickerCopyBestEffort(
  String path, {
  required List<String> roots,
  required AppLogger logger,
}) async {
  try {
    final target = p.normalize(p.absolute(path));
    final inside = roots.any(
      (root) => p.isWithin(p.normalize(p.absolute(root)), target),
    );
    if (!inside) return;
    final file = File(target);
    if (await file.exists()) await file.delete();
  } catch (_) {
    logger.warn('video.pickerCopy.cleanup.failure');
  }
}

/// 화면이 쓰는 picker 사본 정리 함수. 테스트에서 [pickerCopyRootsProvider]를
/// 임시 디렉터리로 바꿔 실제 삭제 경계를 검증한다.
final pickerCopyCleanerProvider = Provider<Future<void> Function(String path)>((
  ref,
) {
  final roots = ref.watch(pickerCopyRootsProvider);
  final logger = ref.watch(appLoggerProvider);
  return (path) async {
    final List<String> resolved;
    try {
      resolved = await roots();
    } catch (_) {
      logger.warn('video.pickerCopy.roots.failure');
      return;
    }
    await deletePickerCopyBestEffort(path, roots: resolved, logger: logger);
  };
});

String _two(int v) => v.toString().padLeft(2, '0');

/// `m:ss`, 한 시간 이상이면 `h:mm:ss`.
String formatVideoDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}
