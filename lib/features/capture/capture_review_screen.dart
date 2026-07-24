import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/router/app_routes.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'providers/capture_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/image_meta.dart';
import 'widgets/async_status_indicator.dart';
import 'widgets/capture_member_banner.dart';
import 'widgets/direction_selector.dart';

/// 촬영 결과 확인 화면.
///
/// 미리보기(원본 비율, BoxFit.contain)/확대/다시 촬영/방향 변경/촬영일·메모
/// 입력/저장을 제공한다. 저장 전 회원 이름과 촬영 방향을 다시 표시한다.
/// 저장은 같은 촬영일의 [PhotoRecord]가 있으면 재사용하고,
/// 없으면 새로 만든다.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.review';

  final String memberId;

  const CaptureReviewScreen({super.key, required this.memberId});

  @override
  ConsumerState<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  final _memoController = TextEditingController();
  AsyncStatus _saveStatus = AsyncStatus.idle;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final memo = ref.read(captureSessionProvider(widget.memberId)).memo;
    _memoController.text = memo ?? '';
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(captureSessionProvider(widget.memberId).notifier).setShotDate(picked);
    }
  }

  void _retake() {
    ref.read(captureSessionProvider(widget.memberId).notifier).clearCapturedImage();
    context.pop();
  }

  Future<void> _save(CaptureSessionState session) async {
    final path = session.capturedImagePath;
    if (path == null) return;
    setState(() {
      _saveStatus = AsyncStatus.busy;
      _saveError = null;
    });
    final logger = ref.read(appLoggerProvider);
    logger.phase('capture.save', LogPhase.start, context: {'memberId': widget.memberId});
    try {
      final storage = ref.read(photoStorageServiceProvider);
      final savedPath = await storage.saveOriginal(
        memberId: widget.memberId,
        sourcePath: path,
      );
      try {
        final meta = await readImageMeta(savedPath);

        final records = ref.read(photoRecordRepositoryProvider);
        final existing = await records.listByMember(widget.memberId);
        final shotDate = DateTime(
          session.shotDate.year,
          session.shotDate.month,
          session.shotDate.day,
        );
        final now = DateTime.now();
        PhotoRecord? matched;
        for (final record in existing) {
          if (_isSameDate(record.shotAt, shotDate)) {
            matched = record;
            break;
          }
        }
        final record = matched ??
            PhotoRecord(
              id: const Uuid().v4(),
              memberId: widget.memberId,
              shotAt: shotDate,
              createdAt: now,
              updatedAt: now,
            );
        if (matched == null) {
          await records.insert(record);
        }

        final memo = _memoController.text.trim();
        final photo = BodyPhoto(
          id: const Uuid().v4(),
          recordId: record.id,
          filePath: savedPath,
          direction: session.direction,
          width: meta.width,
          height: meta.height,
          orientation: meta.orientation,
          gridSettings: session.gridSettingsAtCapture ?? GridSettings.defaults,
          memo: memo.isEmpty ? null : memo,
          createdAt: now,
        );
        await ref.read(bodyPhotoRepositoryProvider).insert(photo);
      } catch (_) {
        // 원본은 이미 저장소에 복사됐지만 DB 반영에 실패했다. 고아 파일이 남지
        // 않도록 복사본을 정리한다(best effort). 정리 자체가 실패해도 원래
        // 예외를 가리지 않도록 별도로 삼킨다.
        try {
          await storage.deleteFile(savedPath);
        } catch (_) {
          // 정리 실패는 무시하고 원래 저장 실패를 그대로 알린다.
        }
        rethrow;
      }

      logger.phase('capture.save', LogPhase.success, context: {'memberId': widget.memberId});
      ref.read(captureSessionProvider(widget.memberId).notifier).reset();
      if (!mounted) return;
      setState(() => _saveStatus = AsyncStatus.success);
      context.goNamed(
        AppRoutes.captureDirection,
        pathParameters: {AppParams.memberId: widget.memberId},
      );
    } catch (e) {
      logger.phase('capture.save', LogPhase.failure, context: {'memberId': widget.memberId});
      if (!mounted) return;
      setState(() {
        _saveStatus = AsyncStatus.failure;
        _saveError = '사진을 저장하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(captureSessionProvider(widget.memberId));
    final memberAsync = ref.watch(memberByIdProvider(widget.memberId));

    return Semantics(
      identifier: CaptureReviewScreen.screenId,
      container: true,
      label: '촬영 결과 확인',
      child: Scaffold(
        key: const ValueKey(CaptureReviewScreen.screenId),
        appBar: AppBar(title: const Text('촬영 결과 확인')),
        body: session.capturedImagePath == null
            ? const Center(child: Text('확인할 촬영 결과가 없습니다.'))
            : memberAsync.when(
                data: (member) => _buildBody(session, member?.name ?? ''),
                loading: () => const Center(
                  child: AsyncStatusIndicator(
                    statusId: 'screen.capture.review.status',
                    status: AsyncStatus.busy,
                    busyLabel: '회원 정보를 불러오는 중입니다.',
                  ),
                ),
                error: (error, stackTrace) => Center(
                  child: AsyncStatusIndicator(
                    statusId: 'screen.capture.review.status',
                    status: AsyncStatus.failure,
                    failureMessage: '회원 정보를 불러오지 못했습니다.',
                    onRetry: () => ref.invalidate(memberByIdProvider(widget.memberId)),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(CaptureSessionState session, String memberName) {
    final path = session.capturedImagePath!;
    final dateLabel = DateFormat('yyyy.MM.dd').format(session.shotDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CaptureMemberBanner(memberName: memberName, direction: session.direction),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'capture.review.photo.image',
            label: '촬영 결과 미리보기, 확대해서 확인할 수 있습니다.',
            child: Container(
              key: const ValueKey('capture.review.photo.image'),
              height: 360,
              width: double.infinity,
              color: Colors.black12,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'capture.retake.button',
                  button: true,
                  label: '다시 촬영',
                  child: OutlinedButton(
                    key: const ValueKey('capture.retake.button'),
                    onPressed: _retake,
                    child: const Text('다시 촬영'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('촬영 방향 변경', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DirectionSelector(
            idPrefix: 'capture.review.direction',
            selected: session.direction,
            onSelected: (direction) => ref
                .read(captureSessionProvider(widget.memberId).notifier)
                .selectDirection(direction),
          ),
          const SizedBox(height: 16),
          const Text('촬영일', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'capture.review.date.field',
            label: '촬영일 $dateLabel, 탭하여 변경',
            button: true,
            child: OutlinedButton(
              key: const ValueKey('capture.review.date.field'),
              onPressed: () => _pickDate(session.shotDate),
              child: Text(dateLabel),
            ),
          ),
          const SizedBox(height: 16),
          const Text('메모', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'capture.review.memo.field',
            label: '사진 메모',
            child: TextField(
              key: const ValueKey('capture.review.memo.field'),
              controller: _memoController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '사진에 대한 메모(선택)',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('저장 전 확인', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('회원: $memberName'),
                Text('촬영 방향: ${session.direction.label}'),
                Text('촬영일: $dateLabel'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AsyncStatusIndicator(
            statusId: 'screen.capture.review.status',
            status: _saveStatus,
            busyLabel: '사진을 저장하는 중입니다.',
            failureMessage: _saveError,
            successLabel: '저장되었습니다.',
            onRetry: () => _save(session),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              identifier: 'capture.save.button',
              button: true,
              label: '사진 저장',
              enabled: _saveStatus != AsyncStatus.busy,
              child: FilledButton(
                key: const ValueKey('capture.save.button'),
                onPressed: _saveStatus == AsyncStatus.busy ? null : () => _save(session),
                child: const Text('저장'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
