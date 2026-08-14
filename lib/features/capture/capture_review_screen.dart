import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'package:body_frame/core/services/photo_storage_service.dart';
import 'package:body_frame/core/theme/app_tokens.dart';
import 'package:body_frame/core/widgets/photo_grid_overlay.dart';
import '../records/providers/records_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/image_meta.dart';
import 'widgets/async_status_indicator.dart';

/// 연속 촬영 결과 일괄 확인 화면.
///
/// 세션에서 찍은 컷을 한눈에 보여주고, 촬영일·라벨·메모를 지정해 **하나의
/// [PhotoRecord]로** 저장한다. 촬영 한 건이 기록 하나이므로 촬영일이 같은 기존
/// 기록에 합치지 않는다 — 같은 날 두 번 찍으면 기록도 두 개다.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.review';

  const CaptureReviewScreen({super.key});

  @override
  ConsumerState<CaptureReviewScreen> createState() =>
      _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  final _labelController = TextEditingController();
  final _memoController = TextEditingController();
  AsyncStatus _saveStatus = AsyncStatus.idle;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final session = ref.read(captureSessionProvider);
    _labelController.text = session.label ?? '';
    _memoController.text = session.memo ?? '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      ref.read(captureSessionProvider.notifier).setShotDate(picked);
    }
  }

  /// 해당 단계를 다시 찍는다. 기존 컷을 지우고 카메라 화면으로 돌아간다.
  void _retake(int index) {
    final notifier = ref.read(captureSessionProvider.notifier);
    final path = ref.read(captureSessionProvider).shots[index].imagePath;
    notifier.clearShot(index);
    notifier.goTo(index);
    if (path != null) {
      unawaited(_deleteTemporaryCaptureBestEffort(path));
    }
    context.pop();
  }

  Future<void> _deleteTemporaryCaptureBestEffort(String path) async {
    final storage = ref.read(photoStorageServiceProvider);
    final logger = ref.read(appLoggerProvider);
    try {
      // 관리 저장소 안의 파일이면 원본이므로 절대 정리하지 않는다.
      final stored = await storage.toStoredPath(path);
      if (stored.startsWith('${PhotoStorageServiceImpl.rootDirName}/')) {
        return;
      }
    } catch (_) {
      // 카메라가 반환하는 cache/tmp 경로는 변환에 실패하는 것이 정상이다.
    }
    try {
      final source = File(path);
      if (await source.exists()) {
        await source.delete();
      }
    } catch (_) {
      logger.warn('capture.source.cleanup.failure');
    }
  }

  Future<void> _save(CaptureSessionState session) async {
    final captured = session.capturedShots;
    if (captured.isEmpty) return;

    setState(() {
      _saveStatus = AsyncStatus.busy;
      _saveError = null;
    });
    final logger = ref.read(appLoggerProvider);
    final storage = ref.read(photoStorageServiceProvider);
    final preparedPaths = <String>[];
    var databaseCommitted = false;
    logger.phase(
      'capture.save',
      LogPhase.start,
      context: {'count': captured.length},
    );

    try {
      final shotDate = DateTime(
        session.shotDate.year,
        session.shotDate.month,
        session.shotDate.day,
      );
      final now = DateTime.now();

      final label = _labelController.text.trim();
      final memo = _memoController.text.trim();
      // 촬영 한 건은 언제나 자기 기록을 갖는다. 같은 날 여러 번 찍으면 그 횟수가
      // 그대로 남아야 하므로 촬영일이 같은 기존 기록에 합치지 않는다.
      final record = PhotoRecord(
        id: const Uuid().v4(),
        shotAt: shotDate,
        label: label.isEmpty ? null : label,
        memo: memo.isEmpty ? null : memo,
        createdAt: now,
        updatedAt: now,
      );

      final photos = <BodyPhoto>[];
      for (final shot in captured) {
        final preparedPath = await storage.saveOriginal(
          shotAt: shotDate,
          sourcePath: shot.imagePath!,
        );
        preparedPaths.add(preparedPath);
        final meta = await readImageMeta(preparedPath);
        photos.add(
          BodyPhoto(
            id: const Uuid().v4(),
            recordId: record.id,
            filePath: preparedPath,
            direction: shot.direction,
            width: meta.width,
            height: meta.height,
            orientation: meta.orientation,
            gridSettings: shot.gridSettingsAtCapture ?? GridSettings.defaults,
            createdAt: now,
          ),
        );
      }

      await ref
          .read(photoIngestRepositoryProvider)
          .insertPrepared(newRecords: [record], photos: photos);
      databaseCommitted = true;

      logger.phase(
        'capture.save',
        LogPhase.success,
        context: {'count': photos.length},
      );

      // 임시 촬영 파일 정리 후 세션 초기화.
      for (final shot in captured) {
        unawaited(_deleteTemporaryCaptureBestEffort(shot.imagePath!));
      }
      ref.read(captureSessionProvider.notifier).reset();
      ref.invalidate(timelineProvider);

      if (!mounted) return;
      setState(() => _saveStatus = AsyncStatus.success);
      // 카메라 화면까지 함께 닫고 홈으로 돌아간다.
      context.go('/');
    } catch (e) {
      if (!databaseCommitted) {
        for (final prepared in preparedPaths) {
          try {
            await storage.deleteFile(prepared);
          } catch (_) {
            logger.warn('capture.preparedFile.cleanup.failure');
          }
        }
      }
      logger.phase('capture.save', LogPhase.failure);
      if (!mounted) return;
      setState(() {
        _saveStatus = AsyncStatus.failure;
        _saveError = '사진을 저장하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(captureSessionProvider);

    return PopScope(
      canPop: _saveStatus != AsyncStatus.busy,
      child: Semantics(
        identifier: CaptureReviewScreen.screenId,
        container: true,
        label: '촬영 결과 확인',
        child: Scaffold(
          key: const ValueKey(CaptureReviewScreen.screenId),
          appBar: AppBar(title: const Text('촬영 결과 확인')),
          body: session.hasAnyCapture
              ? _buildBody(session)
              : const Center(child: Text('확인할 촬영 결과가 없습니다.')),
        ),
      ),
    );
  }

  Widget _buildBody(CaptureSessionState session) {
    final dateLabel = DateFormat('yyyy.MM.dd').format(session.shotDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${session.capturedCount}장 촬영됨',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: session.shots.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _ShotPreview(
                shot: session.shots[index],
                onRetake: () => _retake(index),
              ),
            ),
          ),
          const SizedBox(height: 20),
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
          const Text('대상 라벨', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'capture.review.label.field',
            label: '촬영 대상 라벨',
            child: TextField(
              key: const ValueKey('capture.review.label.field'),
              controller: _labelController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '비워두면 내 기록으로 저장됩니다',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('메모', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'capture.review.memo.field',
            label: '기록 메모',
            child: TextField(
              key: const ValueKey('capture.review.memo.field'),
              controller: _memoController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '기록에 대한 메모(선택)',
              ),
            ),
          ),
          const SizedBox(height: 24),
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
              label: '${session.capturedCount}장 모두 저장',
              enabled: _saveStatus != AsyncStatus.busy,
              child: FilledButton(
                key: const ValueKey('capture.save.button'),
                onPressed: _saveStatus == AsyncStatus.busy
                    ? null
                    : () => _save(session),
                child: Text('${session.capturedCount}장 모두 저장'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShotPreview extends StatelessWidget {
  final CaptureShot shot;
  final VoidCallback onRetake;

  const _ShotPreview({required this.shot, required this.onRetake});

  @override
  Widget build(BuildContext context) {
    final id = 'capture.review.shot.${shot.direction.key}';

    return Semantics(
      identifier: id,
      container: true,
      label: '${shot.direction.label} ${shot.isCaptured ? '촬영 결과' : '미촬영'}',
      child: SizedBox(
        key: ValueKey(id),
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              shot.direction.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                color: context.photoColors.backdrop,
                child: shot.isCaptured
                    // 촬영 당시와 같은 격자를 겹쳐 보여준다. 격자 없이 보이면
                    // 정렬이 맞는지 확인할 수 없어 다시 찍을 판단이 어렵다.
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(shot.imagePath!),
                            fit: BoxFit.contain,
                          ),
                          PhotoGridOverlay(
                            settings:
                                shot.gridSettingsAtCapture ??
                                GridSettings.defaults,
                            semanticsIdentifier:
                                'capture.review.shot.${shot.direction.key}.grid.overlay',
                          ),
                        ],
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_circle_outline),
                            SizedBox(height: 4),
                            Text('건너뜀', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              identifier: 'capture.review.retake.${shot.direction.key}',
              button: true,
              label:
                  '${shot.direction.label} ${shot.isCaptured ? '다시' : ''} 촬영',
              child: OutlinedButton(
                key: ValueKey('capture.review.retake.${shot.direction.key}'),
                onPressed: onRetake,
                child: Text(shot.isCaptured ? '다시 촬영' : '촬영하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
