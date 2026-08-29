import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/services/app_logger.dart';
import '../settings/providers/settings_providers.dart';
import 'compare_export_models.dart';
import 'compare_providers.dart';
import 'widgets/compare_layered_pane.dart';
import 'services/compare_export_sink.dart';
import 'widgets/compare_missing_context.dart';
import 'widgets/compare_photo_pane.dart';
import 'widgets/labeled_switch.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

enum _DefaultsSaveStatus { idle, saving, success, failure }

/// 비교 이미지 저장 설정 화면.
///
/// 전후 비교 화면(compareView)에서 `extra`로 전달받은 [CompareExportRequest]
/// (확대/이동 값, 격자, 대상 사진 등)를 그대로 재현해 화면 구도와 생성
/// 이미지 구도를 일치시킨다. 포함 항목을 선택한 뒤 RepaintBoundary로
/// 캡처하고, gal/share_plus로 저장·공유한다.
class CompareExportScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.compare.export';

  const CompareExportScreen({super.key});

  @override
  ConsumerState<CompareExportScreen> createState() =>
      _CompareExportScreenState();
}

class _CompareExportScreenState extends ConsumerState<CompareExportScreen> {
  final GlobalKey _boundaryKey = GlobalKey();

  CompareExportRequest? _request;
  TransformationController? _previewBeforeCtrl;
  TransformationController? _previewAfterCtrl;

  ExportImageOptions _options = ExportImageOptions.defaults;
  bool _settingsInitialized = false;

  CompareExportStatus _status = CompareExportStatus.idle;
  Uint8List? _resultBytes;
  Object? _error;
  int _generationToken = 0;
  _DefaultsSaveStatus _defaultsSaveStatus = _DefaultsSaveStatus.idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == null) {
      final extra = GoRouterState.of(context).extra;
      if (extra is CompareExportRequest) {
        _request = extra;
        _previewBeforeCtrl = TransformationController(
          extra.beforeMatrix.clone(),
        );
        _previewAfterCtrl = TransformationController(extra.afterMatrix.clone());
        final choice = extra.showGrid;
        if (_settingsInitialized && choice != null) {
          _options = _options.copyWith(includeGrid: choice);
        }
      }
    }
  }

  @override
  void dispose() {
    _previewBeforeCtrl?.dispose();
    _previewAfterCtrl?.dispose();
    super.dispose();
  }

  void _initializeSettings(AppSettings settings) {
    if (_settingsInitialized) return;
    _options = settings.defaultExportOptions;
    // 비교 화면에서 격자를 직접 켜거나 끈 경우에만 그 선택을 따른다.
    final choice = _request?.showGrid;
    if (choice != null) {
      _options = _options.copyWith(includeGrid: choice);
    }
    _settingsInitialized = true;
  }

  void _updateComposition(
    VoidCallback update, {
    bool exportOptionsChanged = false,
  }) {
    setState(() {
      update();
      _generationToken++;
      _resultBytes = null;
      _status = CompareExportStatus.idle;
      _error = null;
      if (exportOptionsChanged) {
        _defaultsSaveStatus = _DefaultsSaveStatus.idle;
      }
    });
  }

  String _defaultsSaveStatusLabel() {
    switch (_defaultsSaveStatus) {
      case _DefaultsSaveStatus.idle:
        return '현재 포함 옵션을 다음 내보내기의 기본값으로 저장할 수 있습니다.';
      case _DefaultsSaveStatus.saving:
        return '기본 내보내기 옵션을 저장하는 중입니다.';
      case _DefaultsSaveStatus.success:
        return '기본 내보내기 옵션으로 저장했습니다.';
      case _DefaultsSaveStatus.failure:
        return '기본값 저장에 실패했습니다. 다시 시도해 주세요.';
    }
  }

  Future<void> _saveOptionsAsDefaults() async {
    if (_defaultsSaveStatus == _DefaultsSaveStatus.saving) return;
    setState(() => _defaultsSaveStatus = _DefaultsSaveStatus.saving);
    final logger = ref.read(appLoggerProvider);
    logger.phase('compare.export.defaults.save', LogPhase.start);
    try {
      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (settings) => settings.copyWith(defaultExportOptions: _options),
          );
      logger.phase('compare.export.defaults.save', LogPhase.success);
      if (!mounted) return;
      setState(() => _defaultsSaveStatus = _DefaultsSaveStatus.success);
    } catch (error) {
      logger.phase('compare.export.defaults.save', LogPhase.failure);
      if (!mounted) return;
      setState(() => _defaultsSaveStatus = _DefaultsSaveStatus.failure);
    }
  }

  String _fileName(CompareExportRequest req) {
    final fmt = DateFormat('yyyyMMdd');
    return 'compare_${req.direction.key}_'
        '${fmt.format(req.beforeRecord.shotAt)}_${fmt.format(req.afterRecord.shotAt)}';
  }

  String _statusLabel() {
    switch (_status) {
      case CompareExportStatus.idle:
        return '이미지를 생성해 주세요.';
      case CompareExportStatus.generating:
        return '이미지를 생성하는 중입니다.';
      case CompareExportStatus.success:
        return '이미지 생성이 완료되었습니다.';
      case CompareExportStatus.failure:
        return '이미지 생성에 실패했습니다: $_error';
    }
  }

  Future<void> _generate() async {
    final req = _request;
    if (req == null) return;
    final logger = ref.read(appLoggerProvider);
    final generationToken = ++_generationToken;
    setState(() {
      _status = CompareExportStatus.generating;
      _resultBytes = null;
      _error = null;
    });
    logger.phase('compare.export.generate', LogPhase.start);
    try {
      // 위젯이 최신 옵션으로 다시 그려질 프레임을 기다린 뒤 캡처한다.
      await WidgetsBinding.instance.endOfFrame;
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('미리보기를 렌더링할 수 없습니다.');
      }
      final image = await renderObject.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('이미지 인코딩에 실패했습니다.');
      }
      final bytes = byteData.buffer.asUint8List();
      if (!mounted || generationToken != _generationToken) return;
      setState(() {
        _resultBytes = bytes;
        _status = CompareExportStatus.success;
      });
      logger.phase(
        'compare.export.generate',
        LogPhase.success,
        context: {'bytes': bytes.length},
      );
    } catch (e) {
      if (!mounted || generationToken != _generationToken) return;
      setState(() {
        _status = CompareExportStatus.failure;
        _error = e;
      });
      logger.phase('compare.export.generate', LogPhase.failure);
    }
  }

  Future<void> _save() async {
    final bytes = _resultBytes;
    final req = _request;
    if (bytes == null || req == null) return;
    final sink = ref.read(compareExportSinkProvider);
    final logger = ref.read(appLoggerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sink.saveToGallery(bytes, name: _fileName(req));
      logger.phase('compare.export.save', LogPhase.success);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('사진 보관함에 저장했습니다.')));
    } catch (e) {
      logger.phase('compare.export.save', LogPhase.failure);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('저장에 실패했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _share() async {
    final bytes = _resultBytes;
    final req = _request;
    if (bytes == null || req == null) return;
    final sink = ref.read(compareExportSinkProvider);
    final logger = ref.read(appLoggerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      final shareOrigin = renderBox == null || !renderBox.hasSize
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : renderBox.localToGlobal(Offset.zero) & renderBox.size;
      await sink.share(
        bytes,
        name: _fileName(req),
        text: '체형 변화 비교 이미지',
        sharePositionOrigin: shareOrigin,
      );
      logger.phase('compare.export.share', LogPhase.success);
    } catch (e) {
      logger.phase('compare.export.share', LogPhase.failure);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('공유에 실패했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  bool _hasMemo(CompareExportRequest req) {
    return _memoText(req).isNotEmpty;
  }

  String _memoText(CompareExportRequest req) {
    final parts = <String>[];

    void addMemo(String label, String? memo) {
      final value = memo?.trim();
      if (value != null && value.isNotEmpty) {
        parts.add('$label: $value');
      }
    }

    addMemo('이전 기록', req.beforeRecord.memo);
    addMemo('이전 사진', req.beforePhoto.memo);
    addMemo('이후 기록', req.afterRecord.memo);
    addMemo('이후 사진', req.afterPhoto.memo);
    return parts.join('\n');
  }

  Widget _buildComparisonMedia(
    CompareExportRequest req,
    TransformationController beforeCtrl,
    TransformationController afterCtrl,
  ) {
    final beforeDate = _options.includeShotDate
        ? _dateFormat.format(req.beforeRecord.shotAt)
        : '';
    final afterDate = _options.includeShotDate
        ? _dateFormat.format(req.afterRecord.shotAt)
        : '';

    if (req.mode != CompareMode.sideBySide) {
      return CompareLayeredPane(
        mode: req.mode,
        beforePhoto: req.beforePhoto,
        afterPhoto: req.afterPhoto,
        beforeDateLabel: beforeDate,
        afterDateLabel: afterDate,
        beforeController: beforeCtrl,
        afterController: afterCtrl,
        interactive: false,
        gridSettings: req.grid,
        showGrid: _options.includeGrid,
        overlayOpacity: req.overlayOpacity,
        sliderPosition: req.sliderPosition,
        identifierPrefix: 'compare.export.${req.mode.key}',
        fixedPhotoSize: req.panePhotoSize ?? const Size(300, 400),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ComparePhotoPane(
            label: '이전',
            dateLabel: beforeDate,
            photo: req.beforePhoto,
            controller: beforeCtrl,
            interactive: false,
            gridSettings: req.grid,
            showGrid: _options.includeGrid,
            paneIdentifier: 'compare.export.before',
            fixedPhotoSize: req.panePhotoSize,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ComparePhotoPane(
            label: '이후',
            dateLabel: afterDate,
            photo: req.afterPhoto,
            controller: afterCtrl,
            interactive: false,
            gridSettings: req.grid,
            showGrid: _options.includeGrid,
            paneIdentifier: 'compare.export.after',
            fixedPhotoSize: req.panePhotoSize,
          ),
        ),
      ],
    );
  }

  /// 생성 이미지에 넣을 대상 라벨.
  ///
  /// 한쪽 기록에만 라벨이 있을 수 있다(본인 기록은 라벨이 없다). 이전 기록만
  /// 보면 "라벨 포함"을 켜도 아무것도 나오지 않으므로 양쪽을 함께 본다. 서로
  /// 다른 대상을 비교한 이미지가 한쪽 이름만 달고 나가지 않게 둘 다 밝힌다.
  String _labelText(CompareExportRequest req) {
    final before = req.beforeRecord.label?.trim();
    final after = req.afterRecord.label?.trim();
    final beforeLabel = (before == null || before.isEmpty) ? null : before;
    final afterLabel = (after == null || after.isEmpty) ? null : after;
    if (beforeLabel == null) return afterLabel ?? '';
    if (afterLabel == null || afterLabel == beforeLabel) return beforeLabel;
    return '이전: $beforeLabel · 이후: $afterLabel';
  }

  Widget _buildComposition(CompareExportRequest req) {
    final beforeCtrl = _previewBeforeCtrl!;
    final afterCtrl = _previewAfterCtrl!;
    final label = _labelText(req);
    return RepaintBoundary(
      key: _boundaryKey,
      child: Semantics(
        identifier: 'compare.result.image',
        container: true,
        label: '비교 이미지 미리보기',
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${req.direction.label} · ${req.mode.label}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _buildComparisonMedia(req, beforeCtrl, afterCtrl),
                if (_options.includeLabel && label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(label, textAlign: TextAlign.center),
                  ),
                if (_options.includeMemo && _hasMemo(req))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_memoText(req), textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `extra`가 소실된 경우(프로세스 복원/딥링크) 쿼리 파라미터로 기본 구도의
  /// 요청을 재구성한다. 확대/이동 상태까지는 복원하지 못하지만 전체 사진을
  /// 표시하는 기본 구도로 화면 자체는 계속 사용할 수 있다.
  Widget _buildFallbackFromQuery(
    BodyDirection direction,
    String beforeId,
    String afterId,
  ) {
    final bundleAsync = ref.watch(
      compareViewBundleProvider((
        beforePhotoId: beforeId,
        afterPhotoId: afterId,
      )),
    );
    return bundleAsync.when(
      loading: () => const Center(
        key: ValueKey('screen.compare.export.status'),
        child: CircularProgressIndicator(),
      ),
      error: (e, st) => const CompareMissingContext(
        message: '비교 정보를 불러오지 못했습니다. 전후 사진 비교 화면에서 다시 진입해 주세요.',
        backButtonId: 'compare.export.backToDates.button',
      ),
      data: (bundle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _request != null) return;
          setState(() {
            _request = CompareExportRequest(
              beforeRecord: bundle.beforeRecord,
              afterRecord: bundle.afterRecord,
              beforePhoto: bundle.beforePhoto,
              afterPhoto: bundle.afterPhoto,
              direction: direction,
              beforeMatrix: Matrix4.identity(),
              afterMatrix: Matrix4.identity(),
              grid: bundle.defaultGrid,
              showGrid: false,
            );
            _previewBeforeCtrl = TransformationController();
            _previewAfterCtrl = TransformationController();
          });
        });
        return const Center(
          key: ValueKey('screen.compare.export.status'),
          child: CircularProgressIndicator(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);
    if (!_settingsInitialized) {
      final settings = settingsAsync.valueOrNull;
      if (settings != null) {
        _initializeSettings(settings);
      } else if (settingsAsync.hasError) {
        _initializeSettings(AppSettings.defaults);
      }
    }

    final req = _request;
    Widget body;
    if (!_settingsInitialized) {
      body = const Center(
        key: ValueKey('screen.compare.export.status'),
        child: CircularProgressIndicator(),
      );
    } else if (req != null) {
      body = _buildContent(req);
    } else {
      final query = GoRouterState.of(context).uri.queryParameters;
      final directionKey = query[AppParams.direction];
      final beforeId = query[AppParams.beforePhotoId];
      final afterId = query[AppParams.afterPhotoId];
      if (directionKey != null && beforeId != null && afterId != null) {
        body = _buildFallbackFromQuery(
          BodyDirection.fromKey(directionKey),
          beforeId,
          afterId,
        );
      } else {
        body = const CompareMissingContext(
          message: '전후 사진 비교 화면에서 이미지 생성을 눌러 진입해 주세요.',
          backButtonId: 'compare.export.backToDates.button',
        );
      }
    }
    return Semantics(
      identifier: CompareExportScreen.screenId,
      container: true,
      label: '비교 이미지 저장 설정',
      child: Scaffold(
        key: const ValueKey(CompareExportScreen.screenId),
        appBar: AppBar(title: const Text('비교 이미지 저장 설정')),
        body: body,
      ),
    );
  }

  Widget _buildContent(CompareExportRequest req) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildComposition(req),
          const SizedBox(height: 16),
          Text('포함 항목', style: Theme.of(context).textTheme.titleSmall),
          LabeledSwitch(
            id: 'compare.export.label.toggle',
            title: '대상 라벨 포함',
            value: _options.includeLabel,
            onChanged: (v) => _updateComposition(
              () => _options = _options.copyWith(includeLabel: v),
              exportOptionsChanged: true,
            ),
          ),
          LabeledSwitch(
            id: 'compare.export.date.toggle',
            title: '촬영일 포함',
            value: _options.includeShotDate,
            onChanged: (v) => _updateComposition(
              () => _options = _options.copyWith(includeShotDate: v),
              exportOptionsChanged: true,
            ),
          ),
          LabeledSwitch(
            id: 'compare.export.memo.toggle',
            title: '메모 포함',
            value: _options.includeMemo,
            onChanged: (v) => _updateComposition(
              () => _options = _options.copyWith(includeMemo: v),
              exportOptionsChanged: true,
            ),
          ),
          LabeledSwitch(
            id: 'compare.export.grid.toggle',
            title: '격자 포함',
            value: _options.includeGrid,
            onChanged: (v) => _updateComposition(
              () => _options = _options.copyWith(includeGrid: v),
              exportOptionsChanged: true,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'compare.export.defaults.save.button',
            label: '현재 포함 옵션을 기본값으로 저장',
            enabled: _defaultsSaveStatus != _DefaultsSaveStatus.saving,
            child: OutlinedButton.icon(
              key: const ValueKey('compare.export.defaults.save.button'),
              onPressed: _defaultsSaveStatus == _DefaultsSaveStatus.saving
                  ? null
                  : _saveOptionsAsDefaults,
              icon: _defaultsSaveStatus == _DefaultsSaveStatus.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('현재 옵션을 기본값으로 저장'),
            ),
          ),
          Semantics(
            identifier: 'compare.export.defaults.save.status',
            label: '기본 내보내기 옵션 저장 상태',
            value: _defaultsSaveStatusLabel(),
            child: Text(
              _defaultsSaveStatusLabel(),
              key: const ValueKey('compare.export.defaults.save.status'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'screen.compare.export.status',
            label: '이미지 생성 상태',
            value: _statusLabel(),
            child: Text(
              _statusLabel(),
              key: const ValueKey('screen.compare.export.status'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'compare.export.generate.button',
            label: '비교 이미지 생성',
            enabled: _status != CompareExportStatus.generating,
            child: ElevatedButton(
              key: const ValueKey('compare.export.generate.button'),
              onPressed: _status == CompareExportStatus.generating
                  ? null
                  : _generate,
              child: _status == CompareExportStatus.generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('비교 이미지 생성'),
            ),
          ),
          if (_resultBytes != null) ...[
            const SizedBox(height: 12),
            Semantics(
              identifier: 'compare.export.result.thumbnail',
              label: '생성된 비교 이미지',
              child: Image.memory(
                _resultBytes!,
                key: const ValueKey('compare.export.result.thumbnail'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'compare.export.save.button',
                  label: '기기에 저장',
                  child: OutlinedButton(
                    key: const ValueKey('compare.export.save.button'),
                    onPressed: _resultBytes == null ? null : _save,
                    child: const Text('기기에 저장'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  identifier: 'compare.export.share.button',
                  label: '외부 앱으로 공유',
                  child: OutlinedButton(
                    key: const ValueKey('compare.export.share.button'),
                    onPressed: _resultBytes == null ? null : _share,
                    child: const Text('공유'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
