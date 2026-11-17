import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/korean_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/media_orientation_lock.dart';
import '../members/ui.dart';
import 'video_providers.dart';

enum _PlayerStatus { loading, ready, failure }

/// 동영상 파일 하나를 원본 비율(contain)로 보여 주는 재생기.
///
/// 재생/일시정지, 탐색 바, 경과/전체 시간과 로딩·실패(재시도) 상태를 갖는다.
/// 저장된 레슨 동영상, 촬영 직후 확인, 저장 전 미리보기가 함께 쓴다.
class VideoPlaybackView extends ConsumerStatefulWidget {
  /// 재생할 파일의 절대 경로.
  final String path;

  /// 영상 방향에 화면 방향을 맞출지. 이미 세로로 고정한 화면(카메라) 안에서는
  /// 끈다. 켜 두면 떠날 때 고정을 풀어 아래 화면의 고정까지 풀린다.
  final bool fitOrientation;

  const VideoPlaybackView({
    super.key,
    required this.path,
    this.fitOrientation = true,
  });

  @override
  ConsumerState<VideoPlaybackView> createState() => VideoPlaybackViewState();
}

class VideoPlaybackViewState extends ConsumerState<VideoPlaybackView> {
  LessonVideoPlayer? _player;
  _PlayerStatus _status = _PlayerStatus.loading;

  /// 탐색 바를 끄는 중인 위치. 놓기 전까지 재생 위치 갱신이 손가락을 덮지 않게 한다.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final previous = _player;
    _player = null;
    previous?.removeListener(_onTick);
    if (previous != null) unawaited(previous.dispose());
    setState(() => _status = _PlayerStatus.loading);
    final player = ref.read(lessonVideoPlayerFactoryProvider)(widget.path);
    try {
      await player.initialize();
      if (!mounted) {
        unawaited(player.dispose());
        return;
      }
      player.addListener(_onTick);
      setState(() {
        _player = player;
        _status = _PlayerStatus.ready;
      });
    } catch (_) {
      unawaited(player.dispose().catchError((Object _) {}));
      if (mounted) setState(() => _status = _PlayerStatus.failure);
    }
  }

  @override
  void dispose() {
    final player = _player;
    _player = null;
    player?.removeListener(_onTick);
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  Future<void> pause() async {
    final player = _player;
    if (player == null || !player.isPlaying) return;
    await player.pause();
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (player.isPlaying) {
      await player.pause();
    } else {
      // 끝까지 본 뒤 다시 누르면 처음부터 재생한다.
      if (player.duration > Duration.zero &&
          player.position >= player.duration) {
        await player.seekTo(Duration.zero);
      }
      await player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final photo = context.photoColors;
    switch (_status) {
      case _PlayerStatus.loading:
        return mark(
          'video.player.status',
          Semantics(
            label: '동영상을 여는 중이에요',
            child: Center(
              child: CircularProgressIndicator(color: photo.onChrome),
            ),
          ),
        );
      case _PlayerStatus.failure:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            child: Card(
              child: EmptyState(
                identifier: 'video.player.status',
                icon: Icons.videocam_off_outlined,
                title: '동영상을 재생하지 못했어요',
                body: keepPhrasesWhole('파일이 손상됐거나 이 기기에서 열 수 없는 형식일 수 있어요.'),
                error: true,
                compact: true,
                actions: [
                  mark(
                    'video.player.retry.button',
                    FilledButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 시도'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case _PlayerStatus.ready:
        break;
    }
    final player = _player!;
    final totalMs = player.duration.inMilliseconds.toDouble();
    final positionMs = player.position.inMilliseconds
        .clamp(0, totalMs <= 0 ? 0 : totalMs)
        .toDouble();
    final shownMs = _dragMs ?? positionMs;
    final timeText =
        '${formatVideoDuration(Duration(milliseconds: shownMs.round()))} / ${formatVideoDuration(player.duration)}';
    // 세로 영상은 세로로 고정한다. 가로로 돌리면 좌우가 비어 작게만 보인다.
    return MediaOrientationLock(
      aspectRatio: widget.fitOrientation ? player.aspectRatio : null,
      child: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: photo.backdrop,
              child: Center(
                // 원본 비율을 지켜 화면 안에 맞춘다(잘라내지 않는다).
                child: AspectRatio(
                  key: const ValueKey('video.player.view'),
                  aspectRatio: player.aspectRatio,
                  child: player.buildView(),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sp2,
                AppSpacing.sp1,
                AppSpacing.sp4,
                AppSpacing.sp2,
              ),
              child: Row(
                children: [
                  mark(
                    'video.player.play.button',
                    IconButton(
                      tooltip: player.isPlaying ? '일시정지' : '재생',
                      onPressed: _togglePlay,
                      iconSize: 32,
                      color: photo.onChrome,
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    ),
                  ),
                  Expanded(
                    child: mark(
                      'video.player.seek.slider',
                      Slider(
                        value: totalMs <= 0 ? 0 : shownMs,
                        max: totalMs <= 0 ? 1 : totalMs,
                        semanticFormatterCallback: (v) => formatVideoDuration(
                          Duration(milliseconds: v.round()),
                        ),
                        onChanged: totalMs <= 0
                            ? null
                            : (v) => setState(() => _dragMs = v),
                        onChangeEnd: totalMs <= 0
                            ? null
                            : (v) async {
                                await player.seekTo(
                                  Duration(milliseconds: v.round()),
                                );
                                if (mounted) setState(() => _dragMs = null);
                              },
                      ),
                    ),
                  ),
                  mark(
                    'video.player.time.value',
                    Text(
                      timeText,
                      style: context.numericTexts.bodySmall.copyWith(
                        color: photo.onChrome,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아직 저장하지 않은 동영상 파일을 확인하는 화면(레슨 편집의 저장 전 목록).
///
/// 공유·삭제 없이 보기만 한다. 목록에서 빼기는 편집 화면이 맡는다.
class LocalVideoPreviewScreen extends StatelessWidget {
  static const screenId = 'screen.video.preview';
  final String path;
  final String title;
  const LocalVideoPreviewScreen({
    super.key,
    required this.path,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final photo = context.photoColors;
    return Theme(
      data: AppTheme.dark,
      child: mark(
        screenId,
        Scaffold(
          backgroundColor: photo.viewfinder,
          appBar: AppBar(
            backgroundColor: photo.viewfinder,
            foregroundColor: photo.onChrome,
            iconTheme: IconThemeData(color: photo.onChrome),
            titleTextStyle: AppTheme.dark.textTheme.titleLarge?.copyWith(
              color: photo.onChrome,
            ),
            title: Text(title),
          ),
          body: VideoPlaybackView(path: path),
        ),
      ),
    );
  }
}
