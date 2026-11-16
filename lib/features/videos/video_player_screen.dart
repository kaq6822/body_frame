import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/korean_text.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../members/ui.dart';
import '../records/providers/records_providers.dart';
import '../records/services/photo_export_sink.dart';
import 'video_providers.dart';

/// 레슨 동영상 재생 화면.
///
/// 원본 비율을 지켜(contain) 보여 주고, 가로 회전을 막지 않는다. 공유는 원본
/// 파일을 그대로 넘기고, 삭제는 확인을 거쳐 DB 행과 파일을 함께 지운다.
class LessonVideoPlayerScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.video.player';
  final String recordId;
  final String videoId;
  const LessonVideoPlayerScreen({
    super.key,
    required this.recordId,
    required this.videoId,
  });

  @override
  ConsumerState<LessonVideoPlayerScreen> createState() =>
      _LessonVideoPlayerScreenState();
}

class _LessonVideoPlayerScreenState
    extends ConsumerState<LessonVideoPlayerScreen> {
  bool deleting = false;
  String? actionError;

  /// 확인창·공유 시트가 떠 있는 동안 소리가 계속 나지 않게 재생을 멈춘다.
  final _playerKey = GlobalKey<_PlayerViewState>();

  Future<void> _delete(LessonVideo video) async {
    if (deleting) return;
    await _playerKey.currentState?.pause();
    if (!mounted) return;
    if (!await confirm(
          context,
          '이 동영상을 삭제할까요?',
          '레슨의 일지와 사진은 그대로 남아요.',
          icon: Icons.delete_outline,
          destructive: true,
          warning: '삭제 후 되돌릴 수 없어요.',
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      deleting = true;
      actionError = null;
    });
    try {
      await ref.read(lessonVideoRepositoryProvider).delete(video.id);
      ref.invalidate(recordVideosProvider(widget.recordId));
      ref.invalidate(timelineProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => actionError = '삭제하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  Future<void> _share(LessonVideo video, Rect? origin) async {
    setState(() => actionError = null);
    await _playerKey.currentState?.pause();
    try {
      await ref
          .read(photoExportSinkProvider)
          .shareOriginalFile(video.filePath, sharePositionOrigin: origin);
    } catch (_) {
      if (mounted) setState(() => actionError = '공유하지 못했어요. 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = ref.watch(recordVideosProvider(widget.recordId));
    final video = videos.valueOrNull
        ?.where((v) => v.id == widget.videoId)
        .firstOrNull;
    final photo = context.photoColors;
    // 영상을 어두운 바탕에서 보도록 사진 보기 화면처럼 화면 전체에 다크 테마를
    // 쓴다. 앱바 제목·아이콘·확인창도 어두운 바탕용 색으로 그려진다.
    return Theme(
      data: AppTheme.dark,
      child: mark(
        LessonVideoPlayerScreen.screenId,
        Scaffold(
          backgroundColor: photo.viewfinder,
          appBar: AppBar(
            backgroundColor: photo.viewfinder,
            foregroundColor: photo.onChrome,
            iconTheme: IconThemeData(color: photo.onChrome),
            actionsIconTheme: IconThemeData(color: photo.onChrome),
            titleTextStyle: AppTheme.dark.textTheme.titleLarge?.copyWith(
              color: photo.onChrome,
            ),
            title: Text(
              video == null ? '레슨 동영상' : '${phases[video.phase] ?? ''} 동영상',
            ),
            actions: [
              if (video != null) ...[
                Builder(
                  builder: (buttonContext) => mark(
                    'video.player.share.button',
                    IconButton(
                      tooltip: '공유',
                      onPressed: deleting
                          ? null
                          : () {
                              final box =
                                  buttonContext.findRenderObject()
                                      as RenderBox?;
                              final origin = box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size;
                              _share(video, origin);
                            },
                      icon: const Icon(Icons.share_outlined),
                    ),
                  ),
                ),
                mark(
                  'video.player.delete.button',
                  IconButton(
                    tooltip: '삭제',
                    onPressed: deleting ? null : () => _delete(video),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ],
          ),
          body: videos.when(
            loading: () => busy('video.player.loading'),
            error: (_, _) => loadFailure(
              'video.player.load.error',
              '동영상을 불러오지 못했어요',
              '잠시 후 다시 시도해주세요.',
              () => ref.invalidate(recordVideosProvider(widget.recordId)),
            ),
            data: (_) => video == null
                ? const EmptyState(
                    identifier: 'video.player.missing',
                    icon: Icons.search_off,
                    title: '동영상을 찾을 수 없어요',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _PlayerView(key: _playerKey, video: video),
                      ),
                      if (deleting)
                        busy('video.player.delete.busy', '삭제하고 있어요'),
                      if (actionError != null)
                        mark(
                          'video.player.action.error',
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.sp3),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                keepPhrasesWhole(actionError!),
                                textAlign: TextAlign.center,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: photo.onChrome,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

enum _PlayerStatus { loading, ready, failure }

class _PlayerView extends ConsumerStatefulWidget {
  final LessonVideo video;
  const _PlayerView({super.key, required this.video});

  @override
  ConsumerState<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<_PlayerView> {
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
    final player = ref.read(lessonVideoPlayerFactoryProvider)(
      widget.video.filePath,
    );
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
    return Column(
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
    );
  }
}
