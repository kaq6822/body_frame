import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_tokens.dart';
import '../members/ui.dart' show mark, phases;
import '../settings/storage_screen.dart' show formatBytes;
import 'video_providers.dart';

/// 동영상 한 개의 요약 줄. 섬네일 플러그인을 쓰지 않으므로 재생 아이콘과
/// 길이·용량·구분으로 대신한다. 레슨 편집과 레슨 상세가 함께 쓴다.
class LessonVideoTile extends StatelessWidget {
  final String identifier;
  final String phase;
  final Duration? duration;
  final int? sizeBytes;
  final LessonVideoSource source;

  /// 저장 전 항목이면 true. "저장 전" 표시를 붙인다.
  final bool pending;
  final VoidCallback? onTap;

  /// 제거 버튼을 둘지. [onRemove]가 null이면 버튼은 보이되 비활성이다.
  final bool removable;
  final VoidCallback? onRemove;
  final String removeTooltip;

  const LessonVideoTile({
    super.key,
    required this.identifier,
    required this.phase,
    required this.source,
    this.duration,
    this.sizeBytes,
    this.pending = false,
    this.onTap,
    this.removable = false,
    this.onRemove,
    this.removeTooltip = '동영상 빼기',
  });

  /// "수업 전 · 1:05 · 12.3 MB · 촬영" 형태의 부제.
  static String summary({
    Duration? duration,
    int? sizeBytes,
    required LessonVideoSource source,
  }) => [
    if (duration != null) formatVideoDuration(duration),
    if (sizeBytes != null) formatBytes(sizeBytes),
    source == LessonVideoSource.camera ? '촬영' : '갤러리',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = '${phases[phase] ?? phases['regular']} 동영상';
    final detail = summary(
      duration: duration,
      sizeBytes: sizeBytes,
      source: source,
    );
    final info = Semantics(
      button: onTap != null,
      label: '$title, $detail${pending ? ', 저장 전' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp2),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: context.photoColors.backdrop,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  color: context.photoColors.onChrome,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending ? '$title (저장 전)' : title,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      detail,
                      style: context.numericTexts.bodySmall.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!removable && onTap != null)
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
    return mark(
      identifier,
      Row(
        children: [
          Expanded(child: info),
          if (removable)
            mark(
              '$identifier.remove.button',
              IconButton(
                tooltip: removeTooltip,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }
}
