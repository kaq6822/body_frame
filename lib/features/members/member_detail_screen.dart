import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/app_logger.dart';
import 'providers/members_providers.dart';
import 'widgets/async_status.dart';

/// 4. 회원 상세 화면. MVP.md 3.3.
///
/// 기본 정보/메모/촬영 기록 목록을 표시하고, 새 사진 촬영·갤러리 등록·전후
/// 비교는 각 담당 워커가 구현한 기존 라우트로 이동만 시킨다(foundation.md §8).
/// 삭제는 '복구 불가' 경고 다이얼로그 확인 후 리포지토리의 연쇄 삭제를
/// 호출한다(MVP.md 3.4).
class MemberDetailScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.members.detail';

  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  /// 대기(null)/진행(loading)/성공(data)/실패(error) 4-상태.
  AsyncValue<void>? _deleteState;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('회원 삭제'),
        content: const Text(
          '이 회원과 모든 촬영 기록·사진이 함께 삭제되며 복구할 수 없습니다.\n계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            key: const ValueKey('members.delete.cancel.button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          Semantics(
            identifier: 'members.delete.confirm.button',
            button: true,
            label: '삭제 확인',
            child: FilledButton(
              key: const ValueKey('members.delete.confirm.button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('삭제'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _delete();
  }

  Future<void> _delete() async {
    final logger = ref.read(appLoggerProvider);
    setState(() => _deleteState = const AsyncValue.loading());
    logger.phase('member.delete', LogPhase.start, context: {'id': widget.memberId});
    try {
      await ref.read(memberRepositoryProvider).delete(widget.memberId);
      logger.phase('member.delete', LogPhase.success, context: {'id': widget.memberId});
      ref.invalidate(membersListProvider);
      if (!mounted) return;
      setState(() => _deleteState = const AsyncValue.data(null));
      context.goNamed(AppRoutes.membersList);
    } catch (e, st) {
      logger.error('member.delete.failure', err: e, stack: st);
      if (!mounted) return;
      setState(() => _deleteState = AsyncValue.error(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(memberDetailProvider(widget.memberId));
    final deleting = _deleteState is AsyncLoading;

    return Semantics(
      identifier: MemberDetailScreen.screenId,
      container: true,
      label: '회원 상세',
      child: Scaffold(
        key: const ValueKey(MemberDetailScreen.screenId),
        appBar: AppBar(
          title: const Text('회원 상세'),
          actions: [
            Semantics(
              identifier: 'members.detail.edit.button',
              button: true,
              enabled: !deleting,
              label: '회원 정보 수정',
              child: IconButton(
                key: const ValueKey('members.detail.edit.button'),
                icon: const Icon(Icons.edit),
                onPressed: deleting
                    ? null
                    : () => context.pushNamed(
                          AppRoutes.memberEdit,
                          pathParameters: {AppParams.memberId: widget.memberId},
                        ),
              ),
            ),
          ],
        ),
        body: AsyncValueView<Member?>(
          value: memberAsync,
          statusId: '${MemberDetailScreen.screenId}.status',
          onRetry: () => ref.invalidate(memberDetailProvider(widget.memberId)),
          builder: (member) {
            if (member == null) {
              return const Center(child: Text('회원 정보를 찾을 수 없습니다.'));
            }
            return _DetailBody(
              member: member,
              deleting: deleting,
              deleteState: _deleteState,
              onCapture: () => context.pushNamed(
                AppRoutes.captureDirection,
                pathParameters: {AppParams.memberId: member.id},
              ),
              onImport: () => context.pushNamed(
                AppRoutes.galleryImport,
                pathParameters: {AppParams.memberId: member.id},
              ),
              onCompare: () => context.pushNamed(
                AppRoutes.compareDates,
                pathParameters: {AppParams.memberId: member.id},
              ),
              onExport: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('데이터 내보내기는 설정 > 백업 및 복원에서 제공됩니다.'),
                ),
              ),
              onDelete: deleting ? null : _confirmDelete,
            );
          },
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Member member;
  final bool deleting;
  final AsyncValue<void>? deleteState;
  final VoidCallback onCapture;
  final VoidCallback onImport;
  final VoidCallback onCompare;
  final VoidCallback onExport;
  final VoidCallback? onDelete;

  const _DetailBody({
    required this.member,
    required this.deleting,
    required this.deleteState,
    required this.onCapture,
    required this.onImport,
    required this.onCompare,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              identifier: 'member.avatar.image',
              label: '대표 사진',
              image: true,
              child: CircleAvatar(
                key: const ValueKey('member.avatar.image'),
                radius: 36,
                backgroundImage: member.avatarPath != null
                    ? FileImage(File(member.avatarPath!))
                    : null,
                child: member.avatarPath == null
                    ? const Icon(Icons.person, size: 32)
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    identifier: 'member.info.name',
                    label: '이름',
                    child: Text(
                      member.name,
                      key: const ValueKey('member.info.name'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    identifier: 'member.info.summary',
                    label: '기본 정보',
                    child: Text(
                      _summaryLine(member),
                      key: const ValueKey('member.info.summary'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if ((member.memo ?? '').isNotEmpty) ...[
          Text('메모', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Semantics(
            identifier: 'member.memo.text',
            label: '메모',
            child: Text(member.memo!, key: const ValueKey('member.memo.text')),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _actionButton(
              context,
              'members.detail.capture.button',
              Icons.camera_alt,
              '새 사진 촬영',
              deleting ? null : onCapture,
            ),
            _actionButton(
              context,
              'members.detail.import.button',
              Icons.photo_library,
              '갤러리 등록',
              deleting ? null : onImport,
            ),
            _actionButton(
              context,
              'members.detail.compare.button',
              Icons.compare,
              '전후 비교',
              deleting ? null : onCompare,
            ),
            _actionButton(
              context,
              'members.detail.export.button',
              Icons.ios_share,
              '데이터 내보내기',
              deleting ? null : onExport,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('촬영 기록', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Consumer(
          builder: (context, ref, _) {
            // 기록마다 사진을 개별 조회하면 N+1 쿼리가 발생하므로, 기록 목록과
            // 기록별 사진을 회원 단위로 한 번에 조회하는 batched provider를
            // 사용한다(memberRecordsWithPhotosProvider).
            final recordsAsync = ref.watch(memberRecordsWithPhotosProvider(member.id));
            return AsyncValueView<List<MemberRecordWithPhotos>>(
              value: recordsAsync,
              statusId: 'member.records.status',
              onRetry: () =>
                  ref.invalidate(memberRecordsWithPhotosProvider(member.id)),
              builder: (records) {
                if (records.isEmpty) {
                  return Semantics(
                    identifier: 'member.records.empty',
                    label: '촬영 기록 없음',
                    child: const Padding(
                      key: ValueKey('member.records.empty'),
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('아직 촬영 기록이 없습니다.')),
                    ),
                  );
                }
                return Column(
                  key: const ValueKey('member.records.list'),
                  children: [
                    for (var i = 0; i < records.length; i++)
                      _RecordTile(
                        memberId: member.id,
                        record: records[i].record,
                        photos: records[i].photos,
                        index: i,
                      ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 24),
        if (deleteState != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: deleteState!.when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                '삭제하지 못했습니다: $e',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Semantics(
          identifier: 'members.detail.delete.button',
          button: true,
          enabled: onDelete != null,
          label: '회원 삭제',
          child: OutlinedButton.icon(
            key: const ValueKey('members.detail.delete.button'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('회원 삭제'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  String _summaryLine(Member member) {
    final parts = <String>[member.gender.label];
    if ((member.birth ?? '').isNotEmpty) parts.add(member.birth!);
    if ((member.contact ?? '').isNotEmpty) parts.add(member.contact!);
    return parts.join(' · ');
  }

  Widget _actionButton(
    BuildContext context,
    String id,
    IconData icon,
    String label,
    VoidCallback? onPressed,
  ) {
    return Semantics(
      identifier: id,
      button: true,
      enabled: onPressed != null,
      label: label,
      child: OutlinedButton.icon(
        key: ValueKey(id),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

/// 촬영 기록 1건 표시. 사진은 [memberRecordsWithPhotosProvider]가 회원 단위로
/// 한 번에 조회해 이미 그룹핑한 결과를 그대로 전달받으므로, 이 위젯 자체는
/// 별도 쿼리를 수행하지 않는다(N+1 방지).
class _RecordTile extends StatelessWidget {
  final String memberId;
  final PhotoRecord record;
  final List<BodyPhoto> photos;
  final int index;

  const _RecordTile({
    required this.memberId,
    required this.record,
    required this.photos,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('yyyy.MM.dd').format(record.shotAt);

    return Semantics(
      identifier: 'member.record.item.$index',
      button: true,
      label: '$dateLabel 촬영 기록',
      child: ListTile(
        key: ValueKey('member.record.item.$index'),
        onTap: () => context.pushNamed(
          AppRoutes.recordDetail,
          pathParameters: {
            AppParams.memberId: memberId,
            AppParams.recordId: record.id,
          },
        ),
        leading: photos.isEmpty
            ? const CircleAvatar(child: Icon(Icons.image_not_supported))
            : CircleAvatar(backgroundImage: FileImage(File(photos.first.filePath))),
        title: Text(dateLabel),
        subtitle: Text(_directionsSummary(photos)),
        trailing: Text('${photos.length}장'),
      ),
    );
  }

  String _directionsSummary(List<BodyPhoto> photos) {
    if (photos.isEmpty) return '사진 없음';
    final labels = photos.map((p) => p.direction.label).toSet();
    return labels.join(', ');
  }
}
