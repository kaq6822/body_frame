import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:body_frame/core/models/models.dart';
import 'package:body_frame/core/providers.dart';
import 'package:body_frame/core/services/app_logger.dart';
import 'providers/capture_providers.dart';
import 'utils/image_meta.dart';
import 'widgets/async_status_indicator.dart';
import 'widgets/capture_member_banner.dart';
import 'widgets/direction_selector.dart';

/// 9. 갤러리 사진 등록 화면. MVP.md 5장.
///
/// 여러 사진을 한 번에 선택해 사진별로 방향을 개별 지정하고, EXIF 촬영일이
/// 있으면 기본값으로 제안한다(사용자가 직접 수정 가능). 같은 촬영일의
/// [PhotoRecord]가 있으면 재사용하고, 없으면 새로 만든다.
class GalleryImportScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.capture.import';

  final String memberId;

  const GalleryImportScreen({super.key, required this.memberId});

  @override
  ConsumerState<GalleryImportScreen> createState() => _GalleryImportScreenState();
}

class _GalleryPickItem {
  final XFile file;
  BodyDirection? direction;
  DateTime shotDate;
  String memo = '';

  _GalleryPickItem({required this.file, required this.shotDate});
}

class _GalleryImportScreenState extends ConsumerState<GalleryImportScreen> {
  final List<_GalleryPickItem> _items = [];
  AsyncStatus _pickStatus = AsyncStatus.idle;
  AsyncStatus _saveStatus = AsyncStatus.idle;
  String? _errorMessage;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  bool get _allDirectionsAssigned =>
      _items.isNotEmpty && _items.every((item) => item.direction != null);

  Future<void> _pickImages() async {
    setState(() {
      _pickStatus = AsyncStatus.busy;
      _errorMessage = null;
    });
    final logger = ref.read(appLoggerProvider);
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
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
        _pickStatus = AsyncStatus.idle;
      });
      logger.info('gallery.pick', context: {'count': items.length});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickStatus = AsyncStatus.failure;
        _errorMessage = '사진을 불러오지 못했습니다.';
      });
      logger.phase('gallery.pick', LogPhase.failure);
    }
  }

  Future<void> _pickDateFor(int index) async {
    final item = _items[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: item.shotDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => item.shotDate = _dateOnly(picked));
    }
  }

  void _removeAt(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _saveAll() async {
    if (!_allDirectionsAssigned) return;
    setState(() {
      _saveStatus = AsyncStatus.busy;
      _errorMessage = null;
    });
    final logger = ref.read(appLoggerProvider);
    logger.phase('gallery.import', LogPhase.start, context: {'memberId': widget.memberId});
    try {
      final storage = ref.read(photoStorageServiceProvider);
      final records = ref.read(photoRecordRepositoryProvider);
      final photos = ref.read(bodyPhotoRepositoryProvider);

      final existingRecords = await records.listByMember(widget.memberId);
      final byDate = <String, PhotoRecord>{
        for (final r in existingRecords) _dateKey(_dateOnly(r.shotAt)): r,
      };

      final savedCount = _items.length;
      for (final item in _items) {
        final direction = item.direction;
        if (direction == null) continue;
        final dateOnly = _dateOnly(item.shotDate);
        final key = _dateKey(dateOnly);
        final now = DateTime.now();
        var record = byDate[key];
        if (record == null) {
          record = PhotoRecord(
            id: const Uuid().v4(),
            memberId: widget.memberId,
            shotAt: dateOnly,
            createdAt: now,
            updatedAt: now,
          );
          await records.insert(record);
          byDate[key] = record;
        }
        final savedPath = await storage.saveOriginal(
          memberId: widget.memberId,
          sourcePath: item.file.path,
        );
        try {
          final meta = await readImageMeta(savedPath);
          final memo = item.memo.trim();
          await photos.insert(BodyPhoto(
            id: const Uuid().v4(),
            recordId: record.id,
            filePath: savedPath,
            direction: direction,
            width: meta.width,
            height: meta.height,
            orientation: meta.orientation,
            memo: memo.isEmpty ? null : memo,
            createdAt: now,
          ));
        } catch (_) {
          // 원본은 이미 저장소에 복사됐지만 DB 행 생성에 실패했다. 고아 파일이
          // 남지 않도록 복사본을 정리한다(best effort, 실패해도 무시).
          await storage.deleteFile(savedPath);
          rethrow;
        }
      }

      logger.phase('gallery.import', LogPhase.success,
          context: {'memberId': widget.memberId, 'count': savedCount});
      if (!mounted) return;
      setState(() {
        _saveStatus = AsyncStatus.success;
        _items.clear();
      });
    } catch (_) {
      logger.phase('gallery.import', LogPhase.failure, context: {'memberId': widget.memberId});
      if (!mounted) return;
      setState(() {
        _saveStatus = AsyncStatus.failure;
        _errorMessage = '사진 등록에 실패했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberAsync = ref.watch(memberByIdProvider(widget.memberId));

    return Semantics(
      identifier: GalleryImportScreen.screenId,
      container: true,
      label: '갤러리 사진 등록',
      child: Scaffold(
        key: const ValueKey(GalleryImportScreen.screenId),
        appBar: AppBar(title: const Text('갤러리 사진 등록')),
        body: memberAsync.when(
          data: (member) => _buildBody(member?.name ?? ''),
          loading: () => const Center(
            child: AsyncStatusIndicator(
              statusId: 'screen.capture.import.status',
              status: AsyncStatus.busy,
              busyLabel: '회원 정보를 불러오는 중입니다.',
            ),
          ),
          error: (error, stackTrace) => Center(
            child: AsyncStatusIndicator(
              statusId: 'screen.capture.import.status',
              status: AsyncStatus.failure,
              failureMessage: '회원 정보를 불러오지 못했습니다.',
              onRetry: () => ref.invalidate(memberByIdProvider(widget.memberId)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(String memberName) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: CaptureMemberBanner(memberName: memberName)),
              const SizedBox(width: 8),
              Semantics(
                identifier: 'capture.import.pick.button',
                button: true,
                label: '갤러리에서 사진 선택',
                child: OutlinedButton.icon(
                  key: const ValueKey('capture.import.pick.button'),
                  onPressed: _pickStatus == AsyncStatus.busy ? null : _pickImages,
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '모든 사진에 촬영 방향을 지정해주세요.',
              style: TextStyle(color: Colors.red),
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
                onRetry: _saveAll,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  identifier: 'capture.import.save.button',
                  button: true,
                  label: '일괄 저장',
                  enabled: _allDirectionsAssigned && _saveStatus != AsyncStatus.busy,
                  child: FilledButton(
                    key: const ValueKey('capture.import.save.button'),
                    onPressed: (_allDirectionsAssigned && _saveStatus != AsyncStatus.busy)
                        ? _saveAll
                        : null,
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
                    child: Image.file(
                      File(item.file.path),
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DirectionSelector(
                    idPrefix: 'capture.import.item.$index.direction',
                    selected: item.direction,
                    onSelected: (direction) => setState(() => item.direction = direction),
                  ),
                ),
                Semantics(
                  identifier: 'capture.import.item.$index.remove.button',
                  button: true,
                  label: '목록에서 제거',
                  child: IconButton(
                    key: ValueKey('capture.import.item.$index.remove.button'),
                    onPressed: () => _removeAt(index),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('촬영일: '),
                Semantics(
                  identifier: 'capture.import.item.$index.date.field',
                  label: '촬영일 $dateLabel, 탭하여 변경',
                  button: true,
                  child: OutlinedButton(
                    key: ValueKey('capture.import.item.$index.date.field'),
                    onPressed: () => _pickDateFor(index),
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '메모(선택)',
                  isDense: true,
                ),
                onChanged: (value) => item.memo = value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
