import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:bodymark/core/dates.dart';
import 'package:bodymark/core/korean_text.dart';
import 'package:bodymark/core/photo_frame.dart';
import 'package:bodymark/core/models/models.dart';
import 'package:bodymark/core/providers.dart';
import 'package:bodymark/core/services/app_logger.dart';
import 'package:bodymark/core/theme/app_tokens.dart';
import 'package:bodymark/core/widgets/bottom_action_bar.dart';
import 'package:bodymark/core/widgets/direction_stepper.dart';
import 'package:bodymark/core/widgets/photo_grid_overlay.dart';
import 'package:bodymark/core/widgets/status_pill.dart';
import 'providers/capture_providers.dart';
import '../records/providers/records_providers.dart';
import '../members/member_providers.dart';
import 'providers/capture_session_provider.dart';
import 'utils/image_meta.dart';
import 'utils/temporary_capture.dart';
import 'package:bodymark/core/widgets/async_status_indicator.dart';

/// 연속 촬영 결과 일괄 확인 화면.
///
/// 위쪽 방향 탭으로 한 방향을 고르면 그 방향 사진을 크게 보여준다. 찍은 방향은
/// 체크로, 건너뛴 방향은 "건너뜀"으로 표시하고, 고른 방향만 다시 찍거나 빠진
/// 방향을 이어 찍을 수 있다. 세션에서 찍은 컷을 확인한 뒤 촬영일·라벨·메모를 지정해 **하나의
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

  /// 저장 요청이 이미 진행 중인지. 위젯 비활성화와 무관하게 중복 저장을 막는
  /// 핸들러 차원의 방어선이다 — 저장 버튼을 연속으로 눌러도 ingest가 두 번
  /// 돌지 않아야 한다.
  bool _saveInFlight = false;

  /// 저장 중 조작을 막는지. 위젯 비활성화와 핸들러 가드를 함께 쓴다.
  bool get _isSaving => _saveStatus == AsyncStatus.busy;

  /// 방향 탭에서 고른 단계. null이면 처음 찍힌 단계를 보여준다.
  int? _selectedIndex;

  int _selectedOf(CaptureSessionState session) {
    final selected = _selectedIndex;
    if (selected != null && selected < session.shots.length) return selected;
    final first = session.shots.indexWhere((shot) => shot.isCaptured);
    return first < 0 ? 0 : first;
  }

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
    if (_isSaving) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && !_isSaving) {
      ref.read(captureSessionProvider.notifier).setShotDate(picked);
    }
  }

  /// 해당 단계를 다시 찍는다. 기존 컷을 지우고 카메라 화면으로 돌아간다.
  ///
  /// 저장이 진행 중이면 막는다. 저장은 복사 중인 임시 원본 경로를 이미 읽고
  /// 있는데 그 파일을 지우면 준비 단계가 실패하거나, DB에는 없는 파일을
  /// 가리키는 기록이 남는다.
  void _retake(int index) {
    if (_isSaving) return;
    final notifier = ref.read(captureSessionProvider.notifier);
    final path = ref.read(captureSessionProvider).shots[index].imagePath;
    notifier.clearShot(index);
    notifier.goTo(index);
    if (path != null) {
      unawaited(_deleteTemporaryCaptureBestEffort(path));
    }
    context.pop();
  }

  Future<void> _deleteTemporaryCaptureBestEffort(String path) {
    return deleteTemporaryCaptureBestEffort(
      path,
      storage: ref.read(photoStorageServiceProvider),
      logger: ref.read(appLoggerProvider),
    );
  }

  Future<void> _save(CaptureSessionState session) async {
    if (ref.read(lessonCaptureContextProvider) != null) {
      if (_saveInFlight) return;
      _saveInFlight = true;
      context.pop(session.capturedShots);
      return;
    }
    final captured = session.capturedShots;
    if (captured.isEmpty) return;
    // 위젯 비활성화 이전에 들어온 요청까지 막는다.
    if (_saveInFlight) return;

    // 저장 대상을 스냅샷으로 고정한다. await 사이에 세션(촬영일·라벨·메모)이나
    // 임시 원본이 바뀌어도 저장은 시작 시점의 값으로만 진행된다.
    final snapshot = _CaptureSaveRequest.from(
      session,
      label: _labelController.text,
      memo: _memoController.text,
    );

    _saveInFlight = true;
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
      context: {'count': snapshot.photos.length},
    );

    try {
      final now = DateTime.now();

      final record = PhotoRecord(
        id: const Uuid().v4(),
        shotAt: snapshot.shotDate,
        label: snapshot.label,
        memo: snapshot.memo,
        createdAt: now,
        updatedAt: now,
      );

      final photos = <BodyPhoto>[];
      for (final pending in snapshot.photos) {
        final preparedPath = await storage.saveOriginal(
          shotAt: snapshot.shotDate,
          sourcePath: pending.sourcePath,
        );
        preparedPaths.add(preparedPath);
        final meta = await readImageMeta(preparedPath);
        photos.add(
          BodyPhoto(
            id: const Uuid().v4(),
            recordId: record.id,
            filePath: preparedPath,
            direction: pending.direction,
            width: meta.width,
            height: meta.height,
            orientation: meta.orientation,
            gridSettings: pending.gridSettings,
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
      for (final pending in snapshot.photos) {
        unawaited(_deleteTemporaryCaptureBestEffort(pending.sourcePath));
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
        _saveError = '사진을 저장하지 못했어요. 다시 시도해주세요.';
      });
    } finally {
      _saveInFlight = false;
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
          appBar: AppBar(
            title: _buildTitle(),
            actions: [
              if (session.hasAnyCapture)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sp4),
                  child: Center(
                    child: StatusPill(
                      identifier: 'capture.review.count',
                      label: '사진 ${session.capturedCount}장',
                      tone: StatusPillTone.primary,
                    ),
                  ),
                ),
            ],
          ),
          body: session.hasAnyCapture
              ? _buildBody(session)
              : const Center(child: Text('확인할 촬영 결과가 없어요.')),
          bottomNavigationBar: session.hasAnyCapture
              ? _buildActions(session)
              : null,
        ),
      ),
    );
  }

  /// 레슨 촬영이면 회원 이름을 제목 아래 함께 보여준다.
  Widget _buildTitle() {
    final member = ref.watch(cameraHeaderInfoProvider).valueOrNull?.title;
    if (member == null) return const Text('촬영 확인');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('촬영 확인'),
        Text(
          member,
          key: const ValueKey('capture.review.member'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 하단 고정 저장(연결) 버튼과 저장 상태.
  Widget _buildActions(CaptureSessionState session) {
    final saving = _isSaving;
    final lesson = ref.watch(lessonCaptureContextProvider) != null;
    final label = lesson
        ? '사진 ${session.capturedCount}장 추가하고 돌아가기'
        : '${session.capturedCount}장 모두 저장';
    return BottomActionBar(
      identifier: 'capture.review.actions',
      leading: _saveStatus == AsyncStatus.idle
          ? (lesson
                ? Text(
                    '작성 중인 레슨에 추가해요.',
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  )
                : null)
          : AsyncStatusIndicator(
              statusId: 'screen.capture.review.status',
              status: _saveStatus,
              busyLabel: '사진을 저장하고 있어요.',
              failureMessage: _saveError,
              successLabel: '저장했어요.',
              onRetry: () => _save(session),
            ),
      primary: Semantics(
        identifier: 'capture.save.button',
        button: true,
        label: label,
        enabled: !saving,
        excludeSemantics: true,
        child: FilledButton(
          key: const ValueKey('capture.save.button'),
          onPressed: saving ? null : () => _save(session),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildBody(CaptureSessionState session) {
    final dateLabel = DateFormat('yyyy.MM.dd').format(session.shotDate);
    final saving = _isSaving;
    final skipped = session.shots.length - session.capturedCount;
    final selectedIndex = _selectedOf(session);
    final selected = session.shots[selectedIndex];
    final missingIndex = session.shots.indexWhere((shot) => !shot.isCaptured);

    return SingleChildScrollView(
      padding: AppSpacing.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 네 방향의 상태를 한 줄에 보여 준다. 찍은 방향은 체크, 건너뛴 방향은
          // "건너뜀"이라 어떤 방향이 빠졌는지 탭만 봐도 안다.
          DirectionStepper(
            identifier: 'capture.review.step',
            singleRow: true,
            directions: [for (final shot in session.shots) shot.direction],
            selected: selected.direction,
            recorded: {
              for (final shot in session.shots)
                if (shot.isCaptured) shot.direction,
            },
            captionBuilder: skipped == 0
                ? null
                : (direction) {
                    final shot = session.shots.firstWhere(
                      (s) => s.direction == direction,
                    );
                    if (direction == selected.direction) return '선택됨';
                    return shot.isCaptured ? '완료' : '건너뜀';
                  },
            onSelected: saving
                ? null
                : (direction) => setState(
                    () => _selectedIndex = session.shots.indexWhere(
                      (s) => s.direction == direction,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.sp3),
          _ShotPreview(
            shot: selected,
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          const SizedBox(height: AppSpacing.sp3),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'capture.review.retake.${selected.direction.key}',
                  button: true,
                  enabled: !saving,
                  label: selected.isCaptured
                      ? '${selected.direction.label} 다시 촬영'
                      : '${selected.direction.label} 촬영하기',
                  excludeSemantics: true,
                  child: OutlinedButton.icon(
                    key: ValueKey(
                      'capture.review.retake.${selected.direction.key}',
                    ),
                    onPressed: saving ? null : () => _retake(selectedIndex),
                    icon: Icon(
                      selected.isCaptured ? Icons.refresh : Icons.photo_camera,
                    ),
                    label: Text(
                      selected.isCaptured ? '이 방향 다시 촬영' : '이 방향 촬영하기',
                    ),
                  ),
                ),
              ),
              // 고른 방향은 찍혔는데 다른 방향이 빠졌으면 바로 이어 찍게 한다.
              if (selected.isCaptured && missingIndex >= 0) ...[
                const SizedBox(width: AppSpacing.sp2),
                Expanded(
                  child: Semantics(
                    identifier: 'capture.review.missing.button',
                    button: true,
                    enabled: !saving,
                    label:
                        '빠진 방향 촬영, ${session.shots[missingIndex].direction.label}',
                    excludeSemantics: true,
                    child: OutlinedButton.icon(
                      key: const ValueKey('capture.review.missing.button'),
                      onPressed: saving ? null : () => _retake(missingIndex),
                      icon: const Icon(Icons.add),
                      label: const Text('빠진 방향 촬영'),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (skipped > 0) ...[
            const SizedBox(height: AppSpacing.sp3),
            Text(
              keepPhrasesWhole('일부 방향만 남겨도 괜찮아요. 건너뛴 방향은 나중에 추가할 수 있어요.'),
              key: const ValueKey('capture.review.partial.note'),
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (ref.watch(lessonCaptureContextProvider) == null) ...[
            const Text('촬영일', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'capture.review.date.field',
              label: '촬영일 $dateLabel, 탭하여 변경',
              button: true,
              enabled: !saving,
              child: OutlinedButton(
                key: const ValueKey('capture.review.date.field'),
                onPressed: saving ? null : () => _pickDate(session.shotDate),
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
                // 저장이 진행 중이면 입력을 막는다. 저장은 시작 시점 값을
                // 스냅샷으로 고정해 쓰지만, 입력창에 다르게 보이는 값이 남아
                // 있으면 사용자가 무엇이 저장됐는지 알 수 없다.
                readOnly: saving,
                // 다시 촬영을 누르면 이 화면이 닫히고 새 State로 다시 열린다.
                // 입력을 세션에 남겨 두지 않으면 그때 조용히 사라진다.
                onChanged: (value) =>
                    ref.read(captureSessionProvider.notifier).setLabel(value),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '비워두면 라벨 없이 저장돼요',
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
                readOnly: saving,
                onChanged: (value) =>
                    ref.read(captureSessionProvider.notifier).setMemo(value),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '기록에 대한 메모(선택)',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 저장 시작 시점에 고정한, 더 이상 바뀌지 않는 저장 요청.
///
/// 파일 경로·방향·촬영일·라벨·메모·격자를 한 번에 복사한다. 복사 도중 세션이
/// 바뀌어도 저장은 이 값으로만 진행되므로, 임시 원본이 사라지거나 라벨이 뒤섞이는
/// 일이 없다. 실패해도 이 스냅샷은 그대로 남아 재시도가 같은 내용을 다시 시도한다.
class _CaptureSaveRequest {
  final DateTime shotDate;
  final String? label;
  final String? memo;
  final List<_CaptureSavePhoto> photos;

  const _CaptureSaveRequest({
    required this.shotDate,
    required this.label,
    required this.memo,
    required this.photos,
  });

  factory _CaptureSaveRequest.from(
    CaptureSessionState session, {
    required String label,
    required String memo,
  }) {
    final trimmedLabel = label.trim();
    final trimmedMemo = memo.trim();
    return _CaptureSaveRequest(
      // 촬영일은 날짜만 남긴다. 시각 성분이 경로 버킷과 경과일에 섞이지 않게.
      shotDate: dateOnly(session.shotDate),
      label: trimmedLabel.isEmpty ? null : trimmedLabel,
      memo: trimmedMemo.isEmpty ? null : trimmedMemo,
      photos: [
        for (final shot in session.capturedShots)
          _CaptureSavePhoto(
            sourcePath: shot.imagePath!,
            direction: shot.direction,
            gridSettings: shot.gridSettingsAtCapture ?? GridSettings.defaults,
          ),
      ],
    );
  }
}

class _CaptureSavePhoto {
  final String sourcePath;
  final BodyDirection direction;
  final GridSettings gridSettings;

  const _CaptureSavePhoto({
    required this.sourcePath,
    required this.direction,
    required this.gridSettings,
  });
}

/// 고른 방향의 큰 사진(3:4, contain)과 실제 촬영 시각.
class _ShotPreview extends StatelessWidget {
  final CaptureShot shot;
  final double maxHeight;

  const _ShotPreview({required this.shot, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final id = 'capture.review.shot.${shot.direction.key}';
    final photoColors = context.photoColors;
    final capturedAt = shot.capturedAt;

    return Semantics(
      identifier: id,
      container: true,
      label: '${shot.direction.label} ${shot.isCaptured ? '촬영 결과' : '건너뜀'}',
      child: Column(
        key: ValueKey(id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: AspectRatio(
                aspectRatio: kPhotoFrameAspect,
                child: ClipRRect(
                  borderRadius: AppRadius.mdAll,
                  child: ColoredBox(
                    color: photoColors.backdrop,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (shot.isCaptured)
                          // 촬영 당시와 같은 격자를 사진 사각형 위에 겹쳐 보여준다.
                          // 격자 없이 보이면 정렬이 맞는지 확인할 수 없어 다시 찍을
                          // 판단이 어렵다.
                          PhotoWithGrid(
                            image: FileImage(File(shot.imagePath!)),
                            settings:
                                shot.gridSettingsAtCapture ??
                                GridSettings.defaults,
                            gridSemanticsIdentifier: '$id.grid.overlay',
                            errorIdPrefix: '$id.photo',
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.remove_circle_outline,
                                  color: photoColors.onChrome.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '건너뜀',
                                  style: context.texts.labelLarge?.copyWith(
                                    color: photoColors.onChrome,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (shot.isCaptured)
                          Positioned(
                            top: AppSpacing.sp2,
                            left: AppSpacing.sp2,
                            child: ExcludeSemantics(
                              child: Container(
                                key: ValueKey('$id.badge'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sp2,
                                  vertical: AppSpacing.sp1,
                                ),
                                decoration: BoxDecoration(
                                  color: photoColors.hudSurface,
                                  borderRadius: AppRadius.fullAll,
                                  border: Border.all(
                                    color: photoColors.hudOutline,
                                  ),
                                ),
                                child: Text(
                                  '${shot.direction.label} 원본',
                                  style: context.texts.labelMedium?.copyWith(
                                    color: photoColors.onChrome,
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
            ),
          ),
          // 실제 촬영 시각. 레슨 일시·작성 일시와 구분해 보여준다.
          if (capturedAt != null) ...[
            const SizedBox(height: AppSpacing.sp2),
            Text(
              '실제 촬영 ${DateFormat('HH:mm').format(capturedAt)}',
              key: ValueKey('$id.capturedAt'),
              style: context.numericTexts.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
