import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../members/ui.dart';
import 'providers/settings_providers.dart';
import 'services/storage_stats_service.dart';

/// 저장 공간 관리 화면.
///
/// 전체 저장 공간 사용량과 회원별·월별 사진·동영상 용량·개수를 표시한다.
class StorageScreen extends ConsumerWidget {
  static const screenId = 'screen.settings.storage';

  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(storageUsageProvider);

    return Semantics(
      identifier: screenId,
      container: true,
      label: '저장 공간 관리',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('저장 공간 관리')),
        body: usageAsync.when(
          data: (report) => _StorageBody(report: report),
          loading: () => const Center(
            key: ValueKey('screen.settings.storage.status'),
            child: CircularProgressIndicator(),
          ),
          error: (e, st) => Center(
            key: const ValueKey('screen.settings.storage.status'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('저장 공간 정보를 불러오지 못했어요'),
                const SizedBox(height: 8),
                ElevatedButton(
                  key: const ValueKey('storage.retry.button'),
                  onPressed: () => ref.invalidate(storageUsageProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// `yyyyMM` 버킷 이름을 표시용 문자열로 바꾼다. 예: `202608` → `2026년 8월`.
String _formatMonth(String bucket) {
  if (bucket.length != 6) return bucket;
  final year = bucket.substring(0, 4);
  final month = int.tryParse(bucket.substring(4));
  if (month == null) return bucket;
  return '$year년 $month월';
}

class _StorageBody extends StatelessWidget {
  final StorageUsageReport report;

  const _StorageBody({required this.report});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '전체 사용량',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  formatBytes(report.totalBytes),
                  key: const ValueKey('storage.total.value'),
                  style: const TextStyle(fontSize: 24),
                ),
                Text(
                  report.totalVideoCount == 0
                      ? '사진 ${report.totalPhotoCount}장'
                      : '사진 ${report.totalPhotoCount}장 · 동영상 ${report.totalVideoCount}개',
                  key: const ValueKey('storage.total.count'),
                ),
                if (report.totalVideoCount > 0)
                  Text(
                    '동영상 ${formatBytes(report.videoBytes)}',
                    key: const ValueKey('storage.video.value'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _MemberUsageSection(usages: report.byMember),
        const SizedBox(height: 16),
        const Text('월별 사용량', style: TextStyle(fontWeight: FontWeight.bold)),
        if (report.byMonth.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('저장된 사진이나 동영상이 없어요'),
          )
        else
          ...report.byMonth.map(
            (m) => ListTile(
              key: ValueKey('storage.month.item.${m.month}'),
              title: Text(_formatMonth(m.month)),
              subtitle: Text(
                m.videoCount == 0
                    ? '사진 ${m.photoCount}장'
                    : '사진 ${m.photoCount}장 · 동영상 ${m.videoCount}개',
              ),
              trailing: Text(formatBytes(m.totalBytes)),
            ),
          ),
      ],
    );
  }
}

/// 개수 문구. 0인 종류는 빼고, 둘 다 0이면 사진 0장으로 둔다.
String _countLabel(int photos, int videos) {
  if (videos == 0) return '사진 $photos장';
  if (photos == 0) return '동영상 $videos개';
  return '사진 $photos장 · 동영상 $videos개';
}

/// 회원별 사용량. 큰 순서로 [collapsedCount]명까지 보이고 "전체 보기"로 펼친다.
class _MemberUsageSection extends StatefulWidget {
  static const collapsedCount = 10;

  final List<MemberStorageUsage> usages;

  const _MemberUsageSection({required this.usages});

  @override
  State<_MemberUsageSection> createState() => _MemberUsageSectionState();
}

class _MemberUsageSectionState extends State<_MemberUsageSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final usages = widget.usages;
    final visible = _expanded
        ? usages
        : usages.take(_MemberUsageSection.collapsedCount).toList();
    final largest = usages.isEmpty ? 0 : usages.first.totalBytes;
    return Semantics(
      identifier: 'storage.members.section',
      container: true,
      child: Column(
        key: const ValueKey('storage.members.section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('회원별 사용량', style: TextStyle(fontWeight: FontWeight.bold)),
          if (usages.isEmpty)
            Semantics(
              identifier: 'storage.members.empty',
              child: const Padding(
                key: ValueKey('storage.members.empty'),
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('회원별로 집계할 사진이나 동영상이 없어요'),
              ),
            )
          else ...[
            const SizedBox(height: AppSpacing.sp2),
            for (final usage in visible)
              _MemberUsageRow(usage: usage, largestBytes: largest),
            if (!_expanded &&
                usages.length > _MemberUsageSection.collapsedCount)
              Semantics(
                identifier: 'storage.members.showAll.button',
                button: true,
                child: TextButton(
                  key: const ValueKey('storage.members.showAll.button'),
                  onPressed: () => setState(() => _expanded = true),
                  child: Text('전체 보기 (${usages.length}명)'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MemberUsageRow extends StatelessWidget {
  final MemberStorageUsage usage;
  final int largestBytes;

  const _MemberUsageRow({required this.usage, required this.largestBytes});

  @override
  Widget build(BuildContext context) {
    final id = usage.memberId ?? 'unlinked';
    final name = usage.isUnlinked ? '회원 미연결 기록' : usage.name;
    final counts = _countLabel(usage.photoCount, usage.videoCount);
    final size = formatBytes(usage.totalBytes);
    final ratio = largestBytes <= 0
        ? 0.0
        : (usage.totalBytes / largestBytes).clamp(0.0, 1.0);
    final colors = context.colors;
    // 글자가 크면 오른쪽 용량이 이름 칸을 밀어내므로 개수 아래 줄로 내린다.
    final stackSize = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    final sizeText = Text(
      size,
      key: ValueKey('storage.member.size.$id'),
      style: context.texts.labelLarge,
    );
    return Semantics(
      identifier: 'storage.member.item.$id',
      button: true,
      label: '$name, $counts, $size',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('storage.member.item.$id'),
        borderRadius: AppRadius.mdAll,
        onTap: () {
          if (usage.isUnlinked) {
            context.push(
              Uri(
                path: '/records',
                queryParameters: {
                  AppParams.memberFilter: AppParams.unlinkedMembers,
                },
              ).toString(),
            );
          } else {
            context.push('/members/${usage.memberId}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp2),
          child: Row(
            children: [
              if (usage.isUnlinked)
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colors.surfaceContainerHigh,
                  foregroundColor: colors.onSurfaceVariant,
                  child: const Icon(Icons.link_off_outlined, size: 20),
                )
              else
                MemberAvatar(usage.name),
              const SizedBox(width: AppSpacing.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      counts,
                      key: ValueKey('storage.member.count.$id'),
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (stackSize) sizeText,
                    const SizedBox(height: AppSpacing.sp1),
                    ClipRRect(
                      borderRadius: AppRadius.mdAll,
                      child: LinearProgressIndicator(
                        key: ValueKey('storage.member.bar.$id'),
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: colors.surfaceContainerHigh,
                      ),
                    ),
                  ],
                ),
              ),
              if (!stackSize) ...[
                const SizedBox(width: AppSpacing.sp3),
                sizeText,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
