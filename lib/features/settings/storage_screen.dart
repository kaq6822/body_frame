import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_providers.dart';
import 'services/storage_stats_service.dart';

/// 저장 공간 관리 화면.
///
/// 전체 저장 공간 사용량과 회원별 사진 용량·개수를 표시한다.
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
                const Text('저장 공간 정보를 불러오지 못했습니다'),
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
                const Text('전체 사용량', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  formatBytes(report.totalBytes),
                  key: const ValueKey('storage.total.value'),
                  style: const TextStyle(fontSize: 24),
                ),
                Text('사진 ${report.totalPhotoCount}장'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('월별 사용량', style: TextStyle(fontWeight: FontWeight.bold)),
        if (report.byMonth.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('저장된 사진이 없습니다'),
          )
        else
          ...report.byMonth.map(
            (m) => ListTile(
              key: ValueKey('storage.month.item.${m.month}'),
              title: Text(_formatMonth(m.month)),
              subtitle: Text('사진 ${m.photoCount}장'),
              trailing: Text(formatBytes(m.totalBytes)),
            ),
          ),
      ],
    );
  }
}
