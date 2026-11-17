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
import 'video_playback_view.dart';

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
  final _playerKey = GlobalKey<VideoPlaybackViewState>();

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
                        child: VideoPlaybackView(
                          key: _playerKey,
                          path: video.filePath,
                        ),
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
