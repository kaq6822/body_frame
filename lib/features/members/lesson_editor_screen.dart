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
  }

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
                phase,
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
          body: failure(
            'lessons.edit.error',
            '기록을 불러오지 못했어요.',
            () => ref.invalidate(recordProvider(widget.recordId!)),
          ),
        );
      }
      original = existing.value;
      if (original == null || original!.memberId != widget.memberId) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('레슨을 찾을 수 없어요.')),
        );
      }
      date = original!.shotAt;
      memo.text = original!.memo ?? '';
      condition.text = original!.condition ?? '';
    }
    initialized = true;
    return PopScope(
      canPop: leaving || !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await confirm(
              context,
              '작성을 그만둘까요?',
              '저장하지 않은 일지와 사진이 사라져요.',
              button: '나가기',
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
            title: const Text('레슨 기록'),
            actions: [
              mark(
                'lessons.save.button',
                TextButton(
                  onPressed: saving || choosing ? null : save,
                  child: Text(saving ? '저장 중' : '저장'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (saving) busy('lessons.save.busy', '레슨 기록을 저장하고 있어요'),
              if (error != null) failure('lessons.save.error', error!, save),
              section(
                '회원 ${member?.name ?? ''}',
                mark(
                  'lessons.date.field',
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final d = await pickLessonDate(context, date);
                            if (d != null && mounted) {
                              setState(() {
                                date = d;
                                dirty = true;
                              });
                            }
                          },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('실제 레슨 일시\n${lessonDate(date)}'),
                  ),
                ),
              ),
              section(
                '오늘의 컨디션 (선택)',
                input(
                  'lessons.condition.field',
                  condition,
                  '불편한 곳이나 주의할 내용',
                  lines: 2,
                  enabled: !saving,
                  onChanged: (_) => setState(() => dirty = true),
                ),
              ),
              section(
                '수업 일지 메모 (선택)',
                input(
                  'lessons.memo.field',
                  memo,
                  '수업 내용, 반응, 다음 수업 참고',
                  lines: 6,
                  enabled: !saving,
                  onChanged: (_) => setState(() => dirty = true),
                ),
              ),
              section(
                '체형 사진 (선택)',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('사진 없이 일지만 저장해도 좋아요.'),
                    const SizedBox(height: 12),
                    mark(
                      'lessons.phase.field',
                      DropdownButton<String>(
                        value: phase,
                        isExpanded: true,
                        items: [
                          for (final p in phases.entries)
                            DropdownMenuItem(
                              value: p.key,
                              child: Text(p.value),
                            ),
                        ],
                        onChanged: saving || choosing
                            ? null
                            : (v) => setState(() => phase = v!),
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        mark(
                          'lessons.capture.button',
                          OutlinedButton.icon(
                            onPressed: saving || choosing ? null : capture,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('촬영'),
                          ),
                        ),
                        mark(
                          'lessons.import.button',
                          OutlinedButton.icon(
                            onPressed: saving || choosing ? null : importPhotos,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('사진 추가'),
                          ),
                        ),
                      ],
                    ),
                    if (choosing) busy('lessons.photos.busy', '사진을 준비하고 있어요'),
                    for (final p in pending)
                      mark(
                        'lessons.pending.${pending.indexOf(p)}.card',
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: SizedBox(
                            width: 56,
                            height: 70,
                            child: Image.file(
                              File(p.path),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          title: Text(
                            '${phases[p.phase]} · ${p.direction.label}',
                          ),
                          subtitle: Text(
                            p.capturedAt == null
                                ? '촬영 시각 정보 없음'
                                : lessonDate(p.capturedAt!),
                          ),
                          trailing: IconButton(
                            tooltip: '추가할 사진 제거',
                            onPressed: saving
                                ? null
                                : () async {
                                    if (await confirm(
                                          context,
                                          '사진을 제거할까요?',
                                          '추가할 사진 목록에서만 제거해요.',
                                        ) &&
                                        mounted) {
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
                                  },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    if (photos.isNotEmpty)
                      Text('기존 사진 ${photos.length}장 · 사진 상세에서 관리할 수 있어요.'),
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

class AssignPhotosScreen extends StatefulWidget {
  final List<String> paths;
  final String phase;
  const AssignPhotosScreen({
    super.key,
    required this.paths,
    required this.phase,
  });
  @override
  State<AssignPhotosScreen> createState() => _AssignPhotosState();
}

class _AssignPhotosState extends State<AssignPhotosScreen> {
  late final directions = [
    for (var i = 0; i < widget.paths.length; i++) BodyDirection.values[i % 4],
  ];
  @override
  Widget build(BuildContext context) => mark(
    'screen.lessons.assignPhotos',
    Scaffold(
      appBar: AppBar(
        title: const Text('사진 방향 확인'),
        actions: [
          mark(
            'lessons.photos.attach.button',
            TextButton(
              onPressed: () async {
                final result = <PendingLessonPhoto>[];
                for (var i = 0; i < widget.paths.length; i++) {
                  result.add(
                    PendingLessonPhoto(
                      widget.paths[i],
                      directions[i],
                      widget.phase,
                      await readExifShotDate(
                        await File(widget.paths[i]).readAsBytes(),
                      ),
                    ),
                  );
                }
                if (context.mounted) Navigator.pop(context, result);
              },
              child: const Text('연결'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('실제 촬영 방향을 확인하고 연결해주세요.\n레슨 일시는 사진 촬영일과 별개예요.'),
          for (var i = 0; i < widget.paths.length; i++)
            panel(
              child: Column(
                children: [
                  SizedBox(
                    height: 240,
                    child: Image.file(
                      File(widget.paths[i]),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('사진을 불러오지 못했어요.'),
                    ),
                  ),
                  mark(
                    'lessons.assign.$i.direction',
                    DropdownButton<BodyDirection>(
                      value: directions[i],
                      items: [
                        for (final d in BodyDirection.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (d) => setState(() => directions[i] = d!),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

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

class _CapturePrepState extends ConsumerState<CapturePreparationScreen> {
  String? baseline;
  bool noBaseline = false;
  @override
  Widget build(BuildContext context) => mark(
    'screen.capture.preparation',
    Scaffold(
      appBar: AppBar(title: const Text('촬영 준비')),
      body: ref
          .watch(timelineProvider)
          .when(
            loading: () => busy('capture.preparation.loading'),
            error: (_, _) => failure(
              'capture.preparation.error',
              '기준 기록을 불러오지 못했어요.',
              () => ref.invalidate(timelineProvider),
            ),
            data: (items) {
              final list = items
                  .where(
                    (x) =>
                        x.record.memberId == widget.memberId &&
                        x.photos.isNotEmpty,
                  )
                  .toList();
              final hasDraft = widget.pending.isNotEmpty;
              final selected =
                  baseline ??
                  (hasDraft ? 'draft' : list.firstOrNull?.record.id);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  section('실제 레슨 일시', Text(lessonDate(widget.lessonAt))),
                  section('촬영 목적', Text(phases[widget.phase]!)),
                  mark(
                    'capture.guide.button',
                    TextButton.icon(
                      onPressed: () => context.push('/capture-guide'),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('촬영 가이드'),
                    ),
                  ),
                  section(
                    '촬영 순서',
                    const Text(
                      '1. 정면 → 2. 좌측면 → 3. 우측면 → 4. 후면\n\n각 방향을 건너뛰거나 다시 촬영할 수 있어요.',
                    ),
                  ),
                  section(
                    '기준 사진',
                    Column(
                      children: [
                        mark(
                          'capture.baseline.none',
                          ListTile(
                            leading: Icon(
                              noBaseline || list.isEmpty && !hasDraft
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            selected: noBaseline || list.isEmpty && !hasDraft,
                            onTap: () => setState(() => noBaseline = true),
                            title: const Text('기준 없이 촬영'),
                            subtitle: const Text('격자를 보며 첫 기록을 촬영해요.'),
                          ),
                        ),
                        if (hasDraft)
                          mark(
                            'capture.baseline.draft',
                            ListTile(
                              leading: Icon(
                                !noBaseline && selected == 'draft'
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              title: const Text('현재 레슨에서 추가한 사진'),
                              subtitle: const Text(
                                '저장 전 사진도 같은 방향의 기준으로 사용할 수 있어요.',
                              ),
                              selected: !noBaseline && selected == 'draft',
                              onTap: () => setState(() {
                                baseline = 'draft';
                                noBaseline = false;
                              }),
                            ),
                          ),
                        for (final x in list)
                          mark(
                            'capture.baseline.${x.record.id}',
                            ListTile(
                              leading: Icon(
                                !noBaseline && selected == x.record.id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              selected: !noBaseline && selected == x.record.id,
                              onTap: () => setState(() {
                                baseline = x.record.id;
                                noBaseline = false;
                              }),
                              title: Text(lessonDate(x.record.shotAt)),
                              subtitle: Text(
                                '${x.photos.length}장 · 같은 회원·같은 방향 사진만 표시',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  action(
                    'capture.start.button',
                    '촬영 시작',
                    () => Navigator.pop(
                      context,
                      LessonCaptureContext(
                        widget.memberId,
                        baselineRecordId: selected == 'draft' ? null : selected,
                        baselinePhotos: selected == 'draft'
                            ? {
                                for (final p in widget.pending)
                                  p.direction: p.path,
                              }
                            : null,
                        useBaseline:
                            !noBaseline && (list.isNotEmpty || hasDraft),
                      ),
                    ),
                    icon: Icons.camera_alt_outlined,
                  ),
                ],
              );
            },
          ),
    ),
  );
}
