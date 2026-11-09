import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/services/photo_storage_service.dart';
import '../../core/services/app_image_picker.dart';
import '../capture/providers/capture_session_provider.dart';
import '../capture/utils/image_meta.dart';
import '../capture/utils/temporary_capture.dart';
import '../../core/services/app_logger.dart';
import '../records/providers/records_providers.dart';
import 'member_providers.dart';
import 'ui.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/bottom_action_bar.dart';
import '../../core/widgets/direction_stepper.dart';
import '../../core/widgets/info_row.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/theme/app_tokens.dart';

class PendingLessonPhoto {
  final String path;
  final BodyDirection direction;
  final String phase;
  final DateTime? capturedAt;
  final GridSettings grid;
  final bool temporaryCapture;
  const PendingLessonPhoto(
    this.path,
    this.direction,
    this.phase,
    this.capturedAt, {
    this.grid = GridSettings.defaults,
    this.temporaryCapture = false,
  });
}

class LessonEditorScreen extends ConsumerStatefulWidget {
  final String memberId;
  final String? recordId;
  const LessonEditorScreen({super.key, required this.memberId, this.recordId});
  @override
  ConsumerState<LessonEditorScreen> createState() => _LessonEditorState();
}

class _LessonEditorState extends ConsumerState<LessonEditorScreen> {
  final memo = TextEditingController(), condition = TextEditingController();
  final pending = <PendingLessonPhoto>[];
  late PhotoStorageService draftStorage;
  late AppLogger draftLogger;
  PhotoRecord? original;
  late DateTime date;
  bool initialized = false,
      dirty = false,
      saving = false,
      leaving = false,
      choosing = false;
  String phase = 'before';
  String? error;
  @override
  void initState() {
    super.initState();
    date = ref.read(clockProvider)();
    draftStorage = ref.read(photoStorageServiceProvider);
    draftLogger = ref.read(appLoggerProvider);
    if (widget.recordId == null) {
      // 회원 상세의 "바로 촬영"으로 들어오면 첫 프레임 뒤 촬영 흐름을 연다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final request = ref.read(quickCaptureRequestProvider.notifier);
        if (request.state != widget.memberId) return;
        request.state = null;
        capture();
      });
    }
  }

  Future<void> removePending(PendingLessonPhoto p) async {
    if (!await confirm(
          context,
          '이 사진을 뺄까요?',
          '저장 전 추가한 목록에서만 빠져요. 다른 사진과 일지는 그대로예요.',
          button: '빼기',
          icon: Icons.image_not_supported_outlined,
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      pending.remove(p);
      if (p.temporaryCapture) {
        unawaited(
          deleteTemporaryCaptureBestEffort(
            p.path,
            storage: draftStorage,
            logger: draftLogger,
          ),
        );
      }
      dirty = true;
    });
  }

  Future<void> changeDate() async {
    final d = await pickLessonDate(context, date);
    if (d != null && d != date && mounted) {
      setState(() {
        date = d;
        dirty = true;
      });
    }
  }

  /// 카드 머리글: 아이콘 + 제목 + (선택) 오른쪽 보조 문구.
  Widget cardTitle(IconData icon, String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.colors.primary),
        const SizedBox(width: AppSpacing.sp2),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.texts.titleMedium),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  @override
  void dispose() {
    memo.dispose();
    condition.dispose();
    // Camera cache files belong to this draft; imported picker files do not.
    final storage = draftStorage;
    for (final p in pending.where((p) => p.temporaryCapture)) {
      unawaited(
        deleteTemporaryCaptureBestEffort(
          p.path,
          storage: storage,
          logger: draftLogger,
        ),
      );
    }
    super.dispose();
  }

  Future<void> capture() async {
    if (choosing || saving) return;
    setState(() => choosing = true);
    try {
      final selected = await Navigator.of(context).push<LessonCaptureContext>(
        MaterialPageRoute(
          builder: (_) => CapturePreparationScreen(
            memberId: widget.memberId,
            lessonAt: date,
            phase: phase,
            pending: pending,
          ),
        ),
      );
      if (selected == null || !mounted) return;
      // 촬영 준비에서 촬영 목적을 바꿨으면 이번 촬영분과 화면 선택을 맞춘다.
      final shotPhase = selected.phase ?? phase;
      if (shotPhase != phase) setState(() => phase = shotPhase);
      ref.read(lessonCaptureContextProvider.notifier).state = selected;
      ref.read(captureSessionProvider.notifier).reset();
      final shots = await context.push<List<CaptureShot>>('/camera');
      if (!mounted || shots == null) return;
      setState(() {
        for (final s in shots) {
          if (s.imagePath != null) {
            pending.add(
              PendingLessonPhoto(
                s.imagePath!,
                s.direction,
                shotPhase,
                s.capturedAt,
                grid: s.gridSettingsAtCapture ?? GridSettings.defaults,
                temporaryCapture: true,
              ),
            );
          }
        }
        dirty = true;
      });
    } catch (_) {
      if (mounted) setState(() => error = '촬영 결과를 가져오지 못했어요. 다시 시도해주세요.');
    } finally {
      ref.read(lessonCaptureContextProvider.notifier).state = null;
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> importPhotos() async {
    if (choosing || saving) return;
    setState(() {
      choosing = true;
      error = null;
    });
    try {
      final files = await ref
          .read(appImagePickerCoordinatorProvider.notifier)
          .pickMultiImage(context: ImagePickerRequestContext.galleryImport());
      if (files.isEmpty || !mounted) return;
      final selected = await Navigator.of(context)
          .push<List<PendingLessonPhoto>>(
            MaterialPageRoute(
              builder: (_) => AssignPhotosScreen(
                paths: files.map((f) => f.path).toList(),
                phase: phase,
                memberName: ref
                    .read(membersProvider)
                    .valueOrNull
                    ?.where((m) => m.id == widget.memberId)
                    .firstOrNull
                    ?.name,
                lessonAt: date,
              ),
            ),
          );
      if (selected != null && mounted) {
        setState(() {
          pending.addAll(selected);
          dirty = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '사진을 가져오지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> save() async {
    if (saving || choosing) return;
    final oldPhotos = widget.recordId == null
        ? <BodyPhoto>[]
        : (ref.read(recordPhotosProvider(widget.recordId!)).valueOrNull ??
              <BodyPhoto>[]);
    if (memo.text.trim().isEmpty &&
        condition.text.trim().isEmpty &&
        pending.isEmpty &&
        oldPhotos.isEmpty) {
      setState(() => error = '일지 또는 사진을 추가해주세요.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final storage = ref.read(photoStorageServiceProvider);
    final prepared = <String>[];
    var committed = false;
    try {
      final now = ref.read(clockProvider)();
      final record = PhotoRecord(
        id: original?.id ?? const Uuid().v4(),
        memberId: widget.memberId,
        shotAt: date,
        memo: memo.text.trim(),
        condition: condition.text.trim(),
        createdAt: original?.createdAt ?? now,
        updatedAt: now,
        label: original?.label,
      );
      final photos = <BodyPhoto>[];
      for (final p in pending) {
        final path = await storage.saveOriginal(
          shotAt: p.capturedAt ?? date,
          sourcePath: p.path,
        );
        prepared.add(path);
        final meta = await readImageMeta(path);
        photos.add(
          BodyPhoto(
            id: const Uuid().v4(),
            recordId: record.id,
            filePath: path,
            direction: p.direction,
            phase: p.phase,
            capturedAt: p.capturedAt,
            width: meta.width,
            height: meta.height,
            orientation: meta.orientation,
            gridSettings: p.grid,
            createdAt: now,
          ),
        );
      }
      await ref.read(memberRepositoryProvider).saveLesson(record, photos);
      committed = true;
      ref.invalidate(timelineProvider);
      ref.invalidate(allRecordsProvider);
      ref.invalidate(recordProvider(record.id));
      ref.invalidate(recordPhotosProvider(record.id));
      if (!mounted) return;
      setState(() {
        dirty = false;
        leaving = true;
      });
      context.pop();
    } catch (_) {
      if (!committed) {
        for (final path in prepared) {
          try {
            await storage.deleteFile(path);
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => error = '레슨을 저장하지 못했어요. 입력 내용과 사진은 유지돼요. 다시 저장해주세요.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final member = members.valueOrNull
        ?.where((m) => m.id == widget.memberId)
        .firstOrNull;
    final existing = widget.recordId == null
        ? null
        : ref.watch(recordProvider(widget.recordId!));
    final photos = widget.recordId == null
        ? <BodyPhoto>[]
        : ref.watch(recordPhotosProvider(widget.recordId!)).valueOrNull ??
              <BodyPhoto>[];
    if (!initialized && widget.recordId != null) {
      if (existing!.isLoading) {
        return Scaffold(body: busy('lessons.edit.loading'));
      }
      if (existing.hasError) {
        return Scaffold(
          appBar: AppBar(),
          body: loadFailure(
            'lessons.edit.error',
            '기록을 불러오지 못했어요',
            '잠시 후 다시 시도해주세요.',
            () => ref.invalidate(recordProvider(widget.recordId!)),
          ),
        );
      }
      original = existing.value;
      if (original == null || original!.memberId != widget.memberId) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
            identifier: 'lessons.edit.missing',
            icon: Icons.search_off,
            title: '레슨을 찾을 수 없어요',
          ),
        );
      }
      date = original!.shotAt;
      memo.text = original!.memo ?? '';
      condition.text = original!.condition ?? '';
    }
    initialized = true;
    final busyInput = saving || choosing;
    final total = pending.length + photos.length;
    final caution = member == null
        ? ''
        : member.precautions.split('\n').first.trim();
    final secondary = context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return PopScope(
      canPop: leaving || !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await confirm(
              context,
              '작성한 내용을 버릴까요?',
              '저장하지 않은 일지와 사진이 사라져요.',
              button: '변경 내용 버리기',
              cancel: '계속 작성',
              destructive: true,
              preferCancel: true,
            ) &&
            mounted) {
          setState(() => leaving = true);
          if (context.mounted) context.pop();
        }
      },
      child: mark(
        'screen.lessons.edit',
        Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('레슨 기록'),
                if (member != null)
                  Text(
                    // 키보드가 올라와 위 카드가 가려져도 누구의 기록인지 보인다.
                    '${member.name} 회원 · ${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
              ],
            ),
          ),
          // bottomNavigationBar는 키보드에 가려진다. 키보드 높이만큼 올려
          // 메모를 쓰는 중에도 저장 버튼이 보이게 한다.
          bottomNavigationBar: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: BottomActionBar(
              identifier: 'lessons.save.bar',
              leading: saving
                  ? mark(
                      'lessons.save.busy',
                      const LinearProgressIndicator(
                        semanticsLabel: '레슨 기록을 저장하고 있어요',
                      ),
                    )
                  : error == null
                  ? null
                  : mark(
                      'lessons.save.error',
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: context.texts.bodyMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                      ),
                    ),
              primary: mark(
                'lessons.save.button',
                FilledButton.icon(
                  onPressed: busyInput ? null : save,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? '저장 중' : '레슨 기록 저장하기'),
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            children: [
              mark(
                'lessons.header.section',
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sp2,
                        runSpacing: AppSpacing.sp1,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '회원  ', style: secondary),
                                TextSpan(
                                  text: member?.name ?? '',
                                  style: context.texts.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            label: total == 0 ? '수업 일지' : '사진 $total장',
                            tone: StatusPillTone.primary,
                            identifier: 'lessons.kind.status',
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.sp6),
                      mark(
                        'lessons.date.field',
                        InkWell(
                          borderRadius: AppRadius.smAll,
                          onTap: saving ? null : changeDate,
                          child: InfoRow(
                            label: '실제 레슨 일시',
                            value: lessonDate(date),
                            numeric: true,
                            // 행 전체가 눌림 영역이다. 버튼은 모양만 빌린다.
                            trailing: IgnorePointer(
                              child: ExcludeSemantics(
                                child: OutlinedButton.icon(
                                  onPressed: saving ? null : () {},
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                  ),
                                  label: const Text('일시 변경'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cardTitle(
                      Icons.sentiment_satisfied_outlined,
                      '오늘의 컨디션 (선택)',
                    ),
                    if (caution.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sp3),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusPill(
                            label: '회원 주의: $caution',
                            tone: StatusPillTone.warning,
                            icon: Icons.info_outline,
                            identifier: 'lessons.caution.status',
                          ),
                        ),
                      ),
                    mark(
                      'lessons.condition.field',
                      TextField(
                        controller: condition,
                        enabled: !saving,
                        minLines: 1,
                        maxLines: 2,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (_) => setState(() => dirty = true),
                        decoration: const InputDecoration(
                          hintText: '불편한 곳이나 주의할 내용',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cardTitle(
                      Icons.edit_note,
                      '수업 일지 메모',
                      trailing: Text('선택 사항', style: secondary),
                    ),
                    mark(
                      'lessons.memo.field',
                      TextField(
                        controller: memo,
                        enabled: !saving,
                        minLines: 4,
                        maxLines: 10,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (_) => setState(() => dirty = true),
                        decoration: const InputDecoration(
                          hintText: '수업 내용, 회원 반응, 다음 수업 참고',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              mark(
                'lessons.photos.section',
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cardTitle(
                        Icons.photo_library_outlined,
                        '체형 사진',
                        trailing: total == 0
                            ? null
                            : StatusPill(
                                label: '총 $total장',
                                tone: StatusPillTone.primary,
                                identifier: 'lessons.photos.count',
                              ),
                      ),
                      if (total == 0)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.sp3,
                          ),
                          child: Text('사진 없이도 저장할 수 있어요', style: secondary),
                        ),
                      Text('촬영할 구분', style: context.texts.labelMedium),
                      const SizedBox(height: AppSpacing.sp1),
                      mark(
                        'lessons.phase.field',
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final p in phases.entries)
                              ButtonSegment(
                                value: p.key,
                                label: Text(p.value, maxLines: 1),
                              ),
                          ],
                          selected: {phase},
                          onSelectionChanged: busyInput
                              ? null
                              : (v) => setState(() => phase = v.first),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sp3),
                      Row(
                        children: [
                          Expanded(
                            child: mark(
                              'lessons.capture.button',
                              FilledButton.tonalIcon(
                                onPressed: busyInput ? null : capture,
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: Text(total == 0 ? '촬영' : '추가 촬영'),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sp3),
                          Expanded(
                            child: mark(
                              'lessons.import.button',
                              OutlinedButton.icon(
                                onPressed: busyInput ? null : importPhotos,
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                label: const Text('사진 추가'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (choosing) busy('lessons.photos.busy', '사진을 준비하고 있어요'),
                      for (final ph in phases.keys) ..._photoGroup(ph, photos),
                      if (photos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sp3),
                          child: Text(
                            '저장된 사진은 사진을 눌러 상세에서 관리할 수 있어요.',
                            style: secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 한 구분(수업 전/후/정기)의 저장된 사진 + 추가할 사진을 4열로 그린다.
  List<Widget> _photoGroup(String ph, List<BodyPhoto> saved) {
    final entries =
        <({int order, BodyDirection direction, DateTime? at, Widget tile})>[];
    var seq = 0;
    for (final p in saved.where((p) => p.phase == ph)) {
      entries.add((
        order: p.direction.index * 1000 + seq++,
        direction: p.direction,
        at: p.capturedAt,
        tile: LessonPhotoThumb(
          identifier: 'lessons.existing.${p.id}.tile',
          path: p.filePath,
          label: p.direction.label,
          onTap: saving
              ? null
              : () => context.pushNamed(
                  AppRoutes.photoView,
                  pathParameters: {
                    AppParams.recordId: widget.recordId!,
                    AppParams.photoId: p.id,
                  },
                ),
        ),
      ));
    }
    for (var i = 0; i < pending.length; i++) {
      final p = pending[i];
      if (p.phase != ph) continue;
      entries.add((
        order: p.direction.index * 1000 + seq++,
        direction: p.direction,
        at: p.capturedAt,
        tile: LessonPhotoThumb(
          identifier: 'lessons.pending.$i.card',
          path: p.path,
          label: p.direction.label,
          removeTooltip: '${p.direction.label} 사진 빼기',
          onRemove: saving ? null : () => removePending(p),
        ),
      ));
    }
    if (entries.isEmpty) return const [];
    entries.sort((a, b) => a.order.compareTo(b.order));
    final times = entries.map((e) => e.at).whereType<DateTime>().toList()
      ..sort();
    return [
      const Divider(height: AppSpacing.sp6),
      mark(
        'lessons.group.$ph.header',
        photoGroupHeader(context, ph, [
          for (final e in entries) e.direction,
        ], times.firstOrNull),
      ),
      photoGrid([for (final e in entries) e.tile]),
    ];
  }
}

/// Stitch 25. 갤러리에서 고른 사진의 구분과 방향을 정해 레슨에 붙인다.
class AssignPhotosScreen extends StatefulWidget {
  final List<String> paths;
  final String phase;
  final String? memberName;
  final DateTime? lessonAt;
  const AssignPhotosScreen({
    super.key,
    required this.paths,
    required this.phase,
    this.memberName,
    this.lessonAt,
  });
  @override
  State<AssignPhotosScreen> createState() => _AssignPhotosState();
}

class _AssignPhotosState extends State<AssignPhotosScreen> {
  late final directions = [
    for (var i = 0; i < widget.paths.length; i++) BodyDirection.values[i % 4],
  ];
  late String phase = widget.phase;

  /// 사진별 EXIF 촬영 시각. 읽기 전이면 키가 없고, 못 읽으면 null이다.
  final shotAt = <int, DateTime?>{};
  bool attaching = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.paths.length; i++) {
      unawaited(_readShotAt(i));
    }
  }

  Future<DateTime?> _readShotAt(int i) async {
    if (shotAt.containsKey(i)) return shotAt[i];
    DateTime? at;
    try {
      at = await readExifShotDate(await File(widget.paths[i]).readAsBytes());
    } catch (_) {
      at = null;
    }
    if (mounted) setState(() => shotAt[i] = at);
    return at;
  }

  Future<void> attach() async {
    if (attaching) return;
    setState(() => attaching = true);
    final result = <PendingLessonPhoto>[];
    for (var i = 0; i < widget.paths.length; i++) {
      result.add(
        PendingLessonPhoto(
          widget.paths[i],
          directions[i],
          phase,
          await _readShotAt(i),
        ),
      );
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secondary = context.texts.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final header = [
      if (widget.memberName != null) widget.memberName!,
      if (widget.lessonAt != null) '${shortLessonDate(widget.lessonAt!)} 레슨',
    ].join(' · ');
    final lessonText = widget.lessonAt == null
        ? '이 레슨'
        : '${shortLessonDate(widget.lessonAt!)} 레슨';
    return mark(
      'screen.lessons.assignPhotos',
      Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('사진 연결'),
              if (header.isNotEmpty)
                Text(header, overflow: TextOverflow.ellipsis, style: secondary),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sp4),
              child: Center(
                child: StatusPill(
                  label: '사진 ${widget.paths.length}장',
                  tone: StatusPillTone.primary,
                  identifier: 'lessons.assign.count',
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          identifier: 'lessons.assign.actions',
          primary: mark(
            'lessons.photos.attach.button',
            FilledButton.icon(
              onPressed: attaching ? null : attach,
              icon: const Icon(Icons.check),
              label: const Text('선택한 사진 연결하기'),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.sp4),
          children: [
            panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('촬영 목적 선택', style: context.texts.titleMedium),
                  const SizedBox(height: AppSpacing.sp2),
                  mark(
                    'lessons.assign.phase.field',
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        for (final p in phases.entries)
                          ButtonSegment(
                            value: p.key,
                            label: Text(p.value, maxLines: 1),
                          ),
                      ],
                      selected: {phase},
                      onSelectionChanged: (v) =>
                          setState(() => phase = v.first),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp2),
                  Text('레슨 일시는 사진 촬영 시각과 따로 기록돼요.', style: secondary),
                ],
              ),
            ),
            for (var i = 0; i < widget.paths.length; i++)
              mark(
                'lessons.assign.$i.card',
                panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sp2,
                        runSpacing: AppSpacing.sp1,
                        children: [
                          Text(
                            '사진 ${i + 1} / ${widget.paths.length}',
                            style: context.texts.titleMedium,
                          ),
                          const StatusPill(
                            label: '원본 그대로 추가돼요',
                            icon: Icons.verified_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sp3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.photoColors.backdrop,
                              borderRadius: AppRadius.mdAll,
                            ),
                            child: ClipRRect(
                              borderRadius: AppRadius.mdAll,
                              child: Image.file(
                                File(widget.paths[i]),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Center(
                                  child: Text(
                                    '사진을 불러오지 못했어요.',
                                    style: TextStyle(
                                      color: context.photoColors.onChrome,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sp2),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: AppSpacing.sp2,
                        children: [
                          Text('기기 갤러리에서 선택됨', style: secondary),
                          mark(
                            'lessons.assign.$i.shotAt',
                            Text(
                              !shotAt.containsKey(i)
                                  ? '촬영 시각 확인 중'
                                  : shotAt[i] == null
                                  ? '실제 촬영 시각 확인 불가'
                                  : '촬영 ${lessonDate(shotAt[i]!)}',
                              style: context.numericTexts.bodySmall.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sp3),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: AppSpacing.sp2,
                        children: [
                          Text('방향 지정', style: context.texts.labelLarge),
                          Text('회원 시점 기준', style: secondary),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sp2),
                      DirectionStepper(
                        identifier: 'lessons.assign.$i.direction',
                        selected: directions[i],
                        onSelected: (d) => setState(() => directions[i] = d),
                      ),
                    ],
                  ),
                ),
              ),
            mark(
              'lessons.assign.summary',
              Container(
                padding: const EdgeInsets.all(AppSpacing.sp3),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Text(
                  '기기 앨범에서 가져온 사진은 자르거나 보정하지 않고 원본 비율 그대로 '
                  '$lessonText의 [${phases[phase]}] 사진으로 연결돼요.',
                  style: secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stitch 16. 촬영 전에 레슨 일시·촬영 목적·기준 사진·촬영 순서를 확인한다.
class CapturePreparationScreen extends ConsumerStatefulWidget {
  final String memberId, phase;
  final DateTime lessonAt;
  final List<PendingLessonPhoto> pending;
  const CapturePreparationScreen({
    super.key,
    required this.memberId,
    required this.phase,
    required this.lessonAt,
    this.pending = const [],
  });
  @override
  ConsumerState<CapturePreparationScreen> createState() => _CapturePrepState();
}

/// 기준 사진 선택지 하나. [id]는 'none' / 'draft' / 기록 id.
class _BaselineChoice {
  final String id;
  final String title;
  final String subtitle;
  final List<BodyDirection> directions;
  final String? thumbPath;
  final bool recommended;
  const _BaselineChoice(
    this.id,
    this.title,
    this.subtitle, {
    this.directions = const [],
    this.thumbPath,
    this.recommended = false,
  });
}

class _CapturePrepState extends ConsumerState<CapturePreparationScreen> {
  /// 사용자가 고른 기준. null이면 기본값(저장 전 사진 → 최근 기록 → 기준 없음).
  String? choice;
  late String phase = widget.phase;

  static List<BodyDirection> _directions(Iterable<BodyDirection> ds) =>
      ds.toSet().toList()..sort((a, b) => a.index.compareTo(b.index));

  List<_BaselineChoice> _choices(List<RecordWithPhotos> list) {
    final lessonDay = DateUtils.dateOnly(widget.lessonAt);
    return [
      const _BaselineChoice('none', '기준 없이 촬영', '이전 사진 없이 격자만 보며 촬영해요.'),
      if (widget.pending.isNotEmpty)
        _BaselineChoice(
          'draft',
          '현재 레슨에서 추가한 사진',
          '저장 전 사진 ${widget.pending.length}장',
          directions: _directions(widget.pending.map((p) => p.direction)),
          thumbPath: widget.pending.first.path,
          recommended: true,
        ),
      for (var i = 0; i < list.length; i++)
        _BaselineChoice(
          list[i].record.id,
          DateUtils.dateOnly(list[i].record.shotAt) == lessonDay
              ? '오늘 ${phaseSummary(list[i].photos)}'
              : lessonDate(list[i].record.shotAt),
          DateUtils.dateOnly(list[i].record.shotAt) == lessonDay
              ? shortLessonDate(list[i].record.shotAt)
              : phaseSummary(list[i].photos),
          directions: _directions(list[i].photos.map((p) => p.direction)),
          thumbPath: list[i].orderedPhotos.first.filePath,
          recommended: i == 0 && widget.pending.isEmpty,
        ),
    ];
  }

  Future<void> pickBaseline(
    List<_BaselineChoice> choices,
    String current,
  ) async {
    final name = ref
        .read(membersProvider)
        .valueOrNull
        ?.where((m) => m.id == widget.memberId)
        .firstOrNull
        ?.name;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => mark(
        'capture.baseline.sheet',
        DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sp4,
              0,
              AppSpacing.sp4,
              AppSpacing.sp6,
            ),
            children: [
              Semantics(
                header: true,
                child: Text('기준 사진 선택', style: context.texts.titleLarge),
              ),
              if (name != null)
                Text(
                  '$name 회원',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppSpacing.sp4),
              for (final c in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sp2),
                  child: _BaselineTile(
                    choice: c,
                    selected: c.id == current,
                    onTap: () => Navigator.pop(context, c.id),
                  ),
                ),
              const SizedBox(height: AppSpacing.sp2),
              Text(
                '같은 회원의 사진만 표시돼요.',
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => choice = picked);
  }

  @override
  Widget build(BuildContext context) {
    final name = ref
        .watch(membersProvider)
        .valueOrNull
        ?.where((m) => m.id == widget.memberId)
        .firstOrNull
        ?.name;
    final timeline = ref.watch(timelineProvider);
    final list = (timeline.valueOrNull ?? const <RecordWithPhotos>[])
        .where(
          (x) => x.record.memberId == widget.memberId && x.photos.isNotEmpty,
        )
        .toList();
    final choices = _choices(list);
    final selected =
        choice ??
        (widget.pending.isNotEmpty
            ? 'draft'
            : list.firstOrNull?.record.id ?? 'none');
    final current = choices.firstWhere(
      (c) => c.id == selected,
      orElse: () => choices.first,
    );
    final secondary = context.texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return mark(
      'screen.capture.preparation',
      Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('촬영 준비'),
              if (name != null)
                Text(
                  '$name 회원',
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
            ],
          ),
        ),
        bottomNavigationBar: timeline.hasValue
            ? BottomActionBar(
                identifier: 'capture.start.bar',
                primary: mark(
                  'capture.start.button',
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      LessonCaptureContext(
                        widget.memberId,
                        lessonAt: widget.lessonAt,
                        phase: phase,
                        baselineRecordId:
                            current.id == 'draft' || current.id == 'none'
                            ? null
                            : current.id,
                        baselinePhotos: current.id == 'draft'
                            ? {
                                for (final p in widget.pending)
                                  p.direction: p.path,
                              }
                            : null,
                        useBaseline: current.id != 'none',
                      ),
                    ),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('촬영 시작'),
                  ),
                ),
              )
            : null,
        body: timeline.when(
          loading: () => busy('capture.preparation.loading'),
          error: (_, _) => loadFailure(
            'capture.preparation.error',
            '기준 기록을 불러오지 못했어요',
            '다시 불러오거나, 돌아가서 기준 없이 촬영할 수 있어요.',
            () => ref.invalidate(timelineProvider),
          ),
          data: (_) => ListView(
            padding: const EdgeInsets.all(AppSpacing.sp4),
            children: [
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(
                      label: '레슨 일시',
                      value: lessonDate(widget.lessonAt),
                      numeric: true,
                      identifier: 'capture.preparation.date',
                    ),
                    const Divider(height: AppSpacing.sp6),
                    Text('촬영 목적', style: context.texts.labelLarge),
                    const SizedBox(height: AppSpacing.sp2),
                    mark(
                      'capture.phase.field',
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final p in phases.entries)
                            ButtonSegment(
                              value: p.key,
                              label: Text(p.value, maxLines: 1),
                            ),
                        ],
                        selected: {phase},
                        onSelectionChanged: (v) =>
                            setState(() => phase = v.first),
                      ),
                    ),
                  ],
                ),
              ),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '기준 사진',
                            style: context.texts.titleMedium,
                          ),
                        ),
                        mark(
                          'capture.baseline.change.button',
                          TextButton(
                            onPressed: () => pickBaseline(choices, current.id),
                            child: const Text('변경'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sp2),
                    mark(
                      'capture.baseline.selected',
                      _BaselineTile(
                        choice: current,
                        selected: true,
                        onTap: () => pickBaseline(choices, current.id),
                        showRadio: false,
                      ),
                    ),
                    if (current.id != 'none') ...[
                      const SizedBox(height: AppSpacing.sp2),
                      Text('이전 사진의 위치와 크기를 참고해요.', style: secondary),
                    ],
                  ],
                ),
              ),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '촬영 순서',
                            style: context.texts.titleMedium,
                          ),
                        ),
                        mark(
                          'capture.guide.button',
                          TextButton.icon(
                            onPressed: () => context.push('/capture-guide'),
                            icon: const Icon(Icons.help_outline),
                            label: const Text('가이드'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sp2),
                    mark(
                      'capture.order.steps',
                      Wrap(
                        spacing: AppSpacing.sp1,
                        runSpacing: AppSpacing.sp2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (
                            var i = 0;
                            i < DirectionStepper.standardDirections.length;
                            i++
                          ) ...[
                            if (i > 0)
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 16,
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            StatusPill(
                              label:
                                  '${i + 1}. ${DirectionStepper.standardDirections[i].label}',
                              tone: i == 0
                                  ? StatusPillTone.primary
                                  : StatusPillTone.neutral,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sp2),
                    Text('각 방향을 건너뛰거나 다시 촬영할 수 있어요.', style: secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 기준 사진 한 줄: 썸네일(원본 비율) + 제목·부제·방향 + 추천 배지 + 라디오.
class _BaselineTile extends StatelessWidget {
  final _BaselineChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final bool showRadio;
  const _BaselineTile({
    required this.choice,
    required this.selected,
    required this.onTap,
    this.showRadio = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = choice;
    final tile = Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(
          color: selected && showRadio ? colors.primary : colors.outlineVariant,
          width: selected && showRadio ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sp3),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.thumbPath == null
                        ? colors.surfaceContainerHigh
                        : context.photoColors.backdrop,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.smAll,
                    child: c.thumbPath == null
                        ? Icon(Icons.grid_on, color: colors.onSurfaceVariant)
                        : Image.file(
                            File(c.thumbPath!),
                            fit: BoxFit.contain,
                            cacheWidth:
                                (48 * MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: context.photoColors.onChrome,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sp2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(c.title, style: context.texts.titleMedium),
                        if (c.recommended)
                          const StatusPill(
                            label: '추천',
                            tone: StatusPillTone.primary,
                          ),
                      ],
                    ),
                    Text(
                      c.subtitle,
                      style: context.numericTexts.bodySmall.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (c.directions.isNotEmpty)
                      Text(
                        c.directions.map((d) => d.label).join(' · '),
                        style: context.texts.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (showRadio)
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              if (!showRadio)
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
    // 기존 키 규칙: capture.baseline.none / .draft / .<기록 id>
    final id = 'capture.baseline.${c.id}';
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: showRadio,
      child: showRadio ? mark(id, tile) : tile,
    );
  }
}
