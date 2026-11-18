import 'package:bodymark/core/services/app_image_picker.dart';
import 'package:bodymark/features/capture/camera/video_camera_controller.dart';
import 'package:bodymark/features/capture/providers/capture_providers.dart';
import 'package:bodymark/features/videos/video_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

class FakeVideoCameraController implements VideoCameraController {
  Object? initializeError;
  bool micGranted;
  String recordedPath;
  int initializeCalls = 0, startCalls = 0, stopCalls = 0, disposeCalls = 0;
  bool _initialized = false, _recording = false, _audio = true;

  FakeVideoCameraController({
    this.micGranted = true,
    this.recordedPath = '/tmp/fake_video.mp4',
    this.initializeError,
  });

  @override
  bool get isInitialized => _initialized;
  @override
  double get aspectRatio => 16 / 9;
  @override
  bool get isFrontLens => false;
  @override
  bool get canSwitchLens => true;
  @override
  bool get audioEnabled => _audio;
  @override
  bool get isRecording => _recording;

  /// 마지막 initialize의 tryAudio. 마이크 재요청 여부를 확인한다.
  final tryAudioCalls = <bool>[];

  /// 지정하면 startRecording이 이 Future를 기다린다(생명주기 경합 재현).
  Future<void>? startGate;

  @override
  Future<void> initialize({
    bool useFrontLens = false,
    bool tryAudio = true,
  }) async {
    initializeCalls++;
    tryAudioCalls.add(tryAudio);
    final error = initializeError;
    if (error != null) throw error;
    _audio = tryAudio && micGranted;
    _initialized = true;
  }

  @override
  Widget buildPreview() => const SizedBox.expand(key: ValueKey('fake.preview'));

  @override
  Future<void> startRecording() async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate;
    _recording = true;
  }

  @override
  Future<String> stopRecording() async {
    stopCalls++;
    _recording = false;
    return recordedPath;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _initialized = false;
  }
}

class FakeOrientationLock implements ScreenOrientationLock {
  int locks = 0, restores = 0;
  @override
  Future<void> lockPortrait() async => locks++;
  @override
  Future<void> restore() async => restores++;
}

class FakeLessonVideoPlayer extends ChangeNotifier
    implements LessonVideoPlayer {
  final String path;
  bool fail;
  bool _initialized = false, _playing = false;
  Duration _position = Duration.zero;
  final Duration total;
  int initializeCalls = 0;
  bool disposed = false;

  FakeLessonVideoPlayer(
    this.path, {
    this.fail = false,
    this.total = const Duration(seconds: 65),
  });

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (fail) throw StateError('열 수 없음');
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isPlaying => _playing;
  @override
  double get aspectRatio => 9 / 16;
  @override
  Duration get position => _position;
  @override
  Duration get duration => total;

  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    notifyListeners();
  }

  @override
  Widget buildView() => const SizedBox.expand(key: ValueKey('fake.player'));

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }
}

class FakeVideoPicker implements AppImagePicker {
  String? videoPath;

  /// 지정하면 Android에서 선택 중 Activity가 종료돼 이 파일이 돌아온 것처럼 군다.
  String? lostVideoPath;
  int videoCalls = 0;
  FakeVideoPicker({this.videoPath, this.lostVideoPath});

  @override
  bool get supportsLostDataRecovery => lostVideoPath != null;
  @override
  Future<XFile?> pickImage({required ImageSource source}) async => null;
  @override
  Future<List<XFile>> pickMultiImage() async => const [];
  @override
  Future<XFile?> pickVideo({required ImageSource source}) async {
    videoCalls++;
    return videoPath == null ? null : XFile(videoPath!);
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    final lost = lostVideoPath;
    return lost == null
        ? LostDataResponse.empty()
        : LostDataResponse(file: XFile(lost), type: RetrieveType.video);
  }
}

class MemoryRequestStore implements ImagePickerRequestStore {
  ImagePickerRequestContext? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<void> clearIfMatches(ImagePickerRequestContext context) async {
    if (value == context) value = null;
  }

  @override
  Future<ImagePickerRequestContext?> load() async => value;
  @override
  Future<void> save(ImagePickerRequestContext context) async => value = context;
}
