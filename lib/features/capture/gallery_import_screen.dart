import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/app_image_picker.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'package:body_frame/core/theme/app_tokens.dart';
import 'package:body_frame/core/widgets/photo_grid_overlay.dart';
import '../records/providers/records_providers.dart';
import 'utils/image_meta.dart';
import 'package:body_frame/core/widgets/async_status_indicator.dart';
import 'widgets/direction_selector.dart';

/// 갤러리 사진 등록 화면.
///
/// 여러 사진을 한 번에 선택해 사진별로 방향을 개별 지정하고, EXIF 촬영일이
/// 있으면 기본값으로 제안한다(사용자가 직접 수정 가능). 등록 한 건 안에서
/// 촬영일이 같은 사진끼리 [PhotoRecord] 하나로 묶고, 기존 기록에는 합치지 않는다.
class GalleryImportScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.import';

  const GalleryImportScreen({super.key});

  @override
  ConsumerState<GalleryImportScreen> createState() =>
      _GalleryImportScreenState();
}

class _GalleryPickItem {
  final XFile file;
  BodyDirection? direction;
  DateTime shotDate;
  String memo = '';

  _GalleryPickItem({required this.file, required this.shotDate});
}

/// 등록 요청 1건. 저장 시작 시점에 고정한 값이라 이후 목록 조작과 무관하다.
class _GalleryImportEntry {
  final String sourcePath;
  final BodyDirection direction;
  final DateTime shotDate;
  final String memo;

  const _GalleryImportEntry({
    required this.sourcePath,
    required this.direction,
    required this.shotDate,
    required this.memo,
  });

  String get dateKey => '${shotDate.year}-${shotDate.month}-${shotDate.day}';
}

class _GalleryImportScreenState extends ConsumerState<GalleryImportScreen> {
  final List<_GalleryPickItem> _items = [];
  AsyncStatus _pickStatus = AsyncStatus.idle;
  AsyncStatus _saveStatus = AsyncStatus.idle;
  String? _errorMessage;
  bool _recoveringLostImages = false;
  bool _lostRecoveryScheduled = false;

  /// 저장 요청이 이미 진행 중인지. 위젯 비활성화와 무관하게 중복 저장을 막는
  /// 핸들러 차원의 방어선이다.
  bool _saveInFlight = false;

  /// 저장 중 조작을 막는지.
  bool get _isSaving => _saveStatus == AsyncStatus.busy;

  bool get _isPicking =>
      _pickStatus == AsyncStatus.busy || _recoveringLostImages;

  bool get _canSave => _allDirectionsAssigned && !_isSaving && !_isPicking;

  ImagePickerRequestContext get _pickerContext =>
      ImagePickerRequestContext.galleryImport();

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _allDirectionsAssigned =>
      _items.isNotEmpty && _items.every((item) => item.direction != null);

  @override
  void initState() {
    super.initState();
    ref.listenManual<RecoveredImagePickerSelection?>(
      appImagePickerCoordinatorProvider,
      (previous, next) {
        if (next?.context == _pickerContext) {
          _scheduleLostImageRecovery();
        }
      },
      fireImmediately: true,
    );
  }

  void _scheduleLostImageRecovery() {
    if (_lostRecoveryScheduled) return;
    _lostRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lostRecoveryScheduled = false;
      if (mounted) unawaited(_recoverLostImages());
    });
  }

  Future<void> _recoverLostImages() async {
    if (!mounted || _isPicking || _isSaving) return;
    // 저장 실패 후 입력은 재시도 대상으로 남긴다. 새 복구 결과가 이 목록을
    // 덮어쓰지 않게 하고, 재시도 성공 후 이어서 처리한다.
    if (_saveStatus == AsyncStatus.failure && _items.isNotEmpty) return;
    // 저장 중 도착한 복구 결과는 acknowledge하지 않고 남긴다.
    // 저장 완료 후 다시 확인해 사용자 선택이 누락되지 않게 한다.
    final coordinator = ref.read(appImagePickerCoordinatorProvider.notifier);
    final recovered = coordinator.recoveredFor(_pickerContext);
    if (recovered == null) return;
    _recoveringLostImages = true;
    setState(() {
      _pickStatus = AsyncStatus.busy;
      _errorMessage = null;
    });
    final logger = ref.read(appLoggerProvider);
    try {
      await _replacePickedItems(recovered.files);
      if (!mounted) return;
      await coordinator.acknowledgeRecovered(_pickerContext);
      logger.info(
        'gallery.pick.recovered',
        context: {'count': recovered.files.length},
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickStatus = AsyncStatus.failure;
        _errorMessage = '이전 사진 선택 결과를 복구하지 못했습니다.';
      });
      logger.phase('gallery.pick.recovery', LogPhase.failure);
    } finally {
      _recoveringLostImages = false;
      _finishPicking();
    }
  }

  Future<void> _pickImages() async {
    // 저장 중 새 선택으로 목록을 갈아끼우면 저장 대상과 화면이 어긋난다.
    if (!mounted || _isSaving || _isPicking) return;
    setState(() {
      _pickStatus = AsyncStatus.busy;
      _errorMessage = null;
    });
    final logger = ref.read(appLoggerProvider);
    try {
      final files = await ref
          .read(appImagePickerCoordinatorProvider.notifier)
          .pickMultiImage(context: _pickerContext);
      await _replacePickedItems(files);
      logger.info('gallery.pick', context: {'count': files.length});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickStatus = AsyncStatus.failure;
        _errorMessage = '사진을 불러오지 못했습니다.';
      });
      logger.phase('gallery.pick', LogPhase.failure);
    } finally {
      _finishPicking();
      if (mounted) _scheduleLostImageRecovery();
    }
  }

  void _finishPicking() {
    if (!mounted) return;
    if (_pickStatus == AsyncStatus.busy) {
      setState(() => _pickStatus = AsyncStatus.idle);
    }
  }

  Future<void> _replacePickedItems(List<XFile> files) async {
    // 선택과 저장은 진입점에서 서로 배제한다. await 후 선택 결과를 버리지 않는다.
    if (!mounted) return;
    final items = <_GalleryPickItem>[];
    for (final file in files) {
      var shotDate = _dateOnly(DateTime.now());
      try {
        final bytes = await file.readAsBytes();
        final exifDate = await readExifShotDate(bytes);
        if (exifDate != null) shotDate = exifDate;
      } catch (_) {
        // EXIF가 없거나 파싱에 실패하면 오늘 날짜를 기본값으로 유지한다.
      }
      items.add(_GalleryPickItem(file: file, shotDate: shotDate));
    }
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _pickDateFor(int index) async {
    if (_isSaving) return;
    final item = _items[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: item.shotDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (mounted && picked != null && !_isSaving) {
      setState(() => item.shotDate = _dateOnly(picked));
    }
  }

  void _removeAt(int index) {
    // 저장 중 목록에서 빼면 스냅샷과 화면이 어긋난다.
    if (_isSaving) return;
    setState(() => _items.removeAt(index));
  }

  void _selectDirection(int index, BodyDirection direction) {
    if (_isSaving) return;
    setState(() => _items[index].direction = direction);
  }

  void _setMemo(int index, String value) {
    if (_isSaving) return;
    _items[index].memo = value;
  }

  /// 저장 시작 시점의 목록을 스냅샷으로 고정한다.
  ///
  /// await 사이에 항목이 제거·추가되거나 방향·날짜·메모가 바뀌어도 저장은 이 값으로
  /// 만 진행된다. 성공 시에도 목록 전체를 비우지 않고 스냅샷에 있던 항목만 제거해
  /// 저장 도중 새로 선택된 사진이 사라지지 않게 한다.
  List<_GalleryImportEntry> _snapshotEntries() {
    return [
      for (final item in _items)
        if (item.direction != null)
          _GalleryImportEntry(
            sourcePath: item.file.path,
            direction: item.direction!,
            shotDate: _dateOnly(item.shotDate),
            memo: item.memo.trim(),
          ),
    ];
  }

  /// 스냅샷에 있던 항목만 목록에서 뺀다.
  void _removeSnapshottedItems(List<_GalleryImportEntry> snapshot) {
    final saved = {for (final entry in snapshot) entry.sourcePath};
    setState(() {
      _items.removeWhere((item) => saved.contains(item.file.path));
    });
  }

  Future<void> _saveAll() async {
    if (!mounted || !_canSave || _saveInFlight) return;

    final snapshot = _snapshotEntries();
    if (snapshot.isEmpty) return;

    _saveInFlight = true;
    setState(() {
      _saveStatus = AsyncStatus.busy;
      _errorMessage = null;
    });
    final logger = ref.read(appLoggerProvider);
    logger.phase('gallery.import', LogPhase.start);
    final storage = ref.read(photoStorageServiceProvider);
    final ingest = ref.read(photoIngestRepositoryProvider);
    final preparedPaths = <String>[];
    var databaseCommitted = false;
    try {
      // 이 등록 건 안에서만 촬영일이 같은 사진을 한 기록으로 묶는다. 기존 기록에
      // 합치면 따로 등록한 촬영분이 한 건으로 보이게 된다.
      final byDate = <String, PhotoRecord>{};
      final newRecords = <PhotoRecord>[];
      final preparedPhotos = <BodyPhoto>[];

      for (final entry in snapshot) {
        final now = DateTime.now();
        final record = byDate.putIfAbsent(entry.dateKey, () {
          final created = PhotoRecord(
            id: const Uuid().v4(),
            shotAt: entry.shotDate,
            createdAt: now,
            updatedAt: now,
          );
          newRecords.add(created);
          return created;
        });
        final savedPath = await storage.saveOriginal(
          shotAt: entry.shotDate,
          sourcePath: entry.sourcePath,
        );
        preparedPaths.add(savedPath);
        final meta = await readImageMeta(savedPath);
        preparedPhotos.add(
          BodyPhoto(
            id: const Uuid().v4(),
            recordId: record.id,
            filePath: savedPath,
            direction: entry.direction,
            width: meta.width,
            height: meta.height,
            orientation: meta.orientation,
            memo: entry.memo.isEmpty ? null : entry.memo,
            createdAt: now,
          ),
        );
      }
      await ingest.insertPrepared(
        newRecords: newRecords,
        photos: preparedPhotos,
      );
      databaseCommitted = true;

      logger.phase(
        'gallery.import',
        LogPhase.success,
        context: {'count': snapshot.length},
      );
      ref.invalidate(timelineProvider);
      if (!mounted) return;
      // 저장한 항목만 비운다. 저장 중 새로 선택된 사진은 목록에 그대로 남는다.
      _removeSnapshottedItems(snapshot);
      setState(() => _saveStatus = AsyncStatus.success);
    } catch (_) {
      // DB transaction 전까지는 모든 파일이 미참조 준비 상태다. 실패하면
      // 준비 파일만 제거하며, transaction이 commit된 뒤의 UI 오류로 원본을
      // 삭제하지 않는다. 목록은 그대로 두어 그대로 재시도할 수 있게 한다.
      if (!databaseCommitted) {
        for (final path in preparedPaths.reversed) {
          try {
            await storage.deleteFile(path);
          } catch (_) {
            logger.warn('gallery.import.fileRollback.failure');
          }
        }
      }
      logger.phase('gallery.import', LogPhase.failure);
      if (!mounted) return;
      setState(() {
        _saveStatus = AsyncStatus.failure;
        _errorMessage = '사진 등록에 실패했습니다. 다시 시도해주세요.';
      });
    } finally {
      _saveInFlight = false;
      if (mounted && _saveStatus == AsyncStatus.success) {
        _scheduleLostImageRecovery();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: GalleryImportScreen.screenId,
      container: true,
      label: '갤러리 사진 등록',
      child: PopScope(
        canPop: !_isSaving,
        child: Scaffold(
          key: const ValueKey(GalleryImportScreen.screenId),
          appBar: AppBar(title: const Text('갤러리 사진 등록')),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final saving = _isSaving;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(child: Text('여러 사진을 선택해 방향과 촬영일을 지정하세요.')),
              const SizedBox(width: 8),
              Semantics(
                identifier: 'capture.import.pick.button',
                button: true,
                label: '갤러리에서 사진 선택',
                child: OutlinedButton.icon(
                  key: const ValueKey('capture.import.pick.button'),
                  onPressed: _isPicking || saving ? null : _pickImages,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('사진 선택'),
                ),
              ),
            ],
          ),
        ),
        if (_pickStatus != AsyncStatus.idle)
          AsyncStatusIndicator(
            statusId: 'capture.import.pick.status',
            status: _pickStatus,
            busyLabel: '사진을 불러오는 중입니다.',
            failureMessage: _errorMessage,
            onRetry: _pickImages,
          ),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  key: ValueKey('capture.import.empty'),
                  child: Text('등록할 사진을 선택해주세요.'),
                )
              : ListView.builder(
                  key: const ValueKey('capture.import.list'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _buildItemCard(index),
                ),
        ),
        if (_items.isNotEmpty && !_allDirectionsAssigned)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '모든 사진에 촬영 방향을 지정해주세요.',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              AsyncStatusIndicator(
                statusId: 'screen.capture.import.status',
                status: _saveStatus,
                busyLabel: '사진을 등록하는 중입니다.',
                failureMessage: _errorMessage,
                successLabel: '등록되었습니다.',
                onRetry: _canSave ? _saveAll : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  identifier: 'capture.import.save.button',
                  button: true,
                  label: '일괄 저장',
                  enabled: _canSave,
                  child: FilledButton(
                    key: const ValueKey('capture.import.save.button'),
                    onPressed: _canSave ? _saveAll : null,
                    child: const Text('일괄 저장'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final saving = _isSaving;
    final dateLabel = DateFormat('yyyy.MM.dd').format(item.shotDate);
    return Card(
      key: ValueKey('capture.import.item.$index.card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  identifier: 'capture.import.item.$index.thumbnail.image',
                  label: '선택한 사진 미리보기',
                  child: ClipRRect(
                    key: ValueKey('capture.import.item.$index.thumbnail.image'),
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(item.file.path), fit: BoxFit.contain),
                          // 등록 전 사진도 격자와 함께 보여 정렬 상태를 가늠하게 한다.
                          PhotoGridOverlay(
                            settings: GridSettings.defaults,
                            semanticsIdentifier:
                                'capture.import.item.$index.grid.overlay',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Semantics(
                  identifier: 'capture.import.item.$index.remove.button',
                  button: true,
                  enabled: !saving,
                  label: '목록에서 제거',
                  child: IconButton(
                    key: ValueKey('capture.import.item.$index.remove.button'),
                    onPressed: saving ? null : () => _removeAt(index),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DirectionSelector(
              idPrefix: 'capture.import.item.$index.direction',
              selected: item.direction,
              onSelected: saving
                  ? (_) {}
                  : (direction) => _selectDirection(index, direction),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('촬영일: '),
                Semantics(
                  identifier: 'capture.import.item.$index.date.field',
                  label: '촬영일 $dateLabel, 탭하여 변경',
                  button: true,
                  enabled: !saving,
                  child: OutlinedButton(
                    key: ValueKey('capture.import.item.$index.date.field'),
                    onPressed: saving ? null : () => _pickDateFor(index),
                    child: Text(dateLabel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'capture.import.item.$index.memo.field',
              label: '사진 메모',
              child: TextFormField(
                key: ValueKey('capture.import.item.$index.memo.field'),
                initialValue: item.memo,
                // 저장은 시작 시점 메모를 스냅샷으로 쓰지만, 입력창에 저장과
                // 다른 값이 남아 있으면 무엇이 등록됐는지 알 수 없다.
                readOnly: saving,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '메모(선택)',
                  isDense: true,
                ),
                onChanged: (value) => _setMemo(index, value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
