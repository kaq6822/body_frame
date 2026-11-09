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
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bottom_action_bar.dart';
import '../../core/widgets/direction_stepper.dart';
import '../members/member_providers.dart';
import '../members/ui.dart' show lessonDate, phases;
import '../settings/providers/settings_providers.dart';
import 'compare_export_models.dart';
import 'compare_logic.dart';
import 'compare_providers.dart';
import 'widgets/compare_layered_pane.dart';
import 'services/compare_export_sink.dart';
import 'services/compare_photo_loader.dart';
import 'widgets/compare_missing_context.dart';
import 'widgets/compare_photo_pane.dart';
import 'widgets/labeled_switch.dart';

enum _DefaultsSaveStatus { idle, saving, success, failure }

/// 공유 이미지 만들기의 두 단계. 라우트를 늘리지 않고 한 화면 안에서 바꾼다.
enum _ExportStep { options, preview }

/// 공유 이미지 구성 → 미리보기 화면.
///
/// 사진 비교 화면(compareView)에서 `extra`로 전달받은 [CompareExportRequest]
/// (확대/이동 값, 격자, 대상 사진 등)를 그대로 재현해 화면 구도와 생성
/// 이미지 구도를 일치시킨다.
/// 1단계에서 방향·표시 항목을 고르고 "미리보기 만들기"를 누르면
/// RepaintBoundary로 캡처한다. 2단계는 캡처한 바이트를 그대로 보여주고,
/// 같은 바이트를 gal/share_plus로 저장·공유한다. 시스템 뒤로 가기와
/// "구성 수정"은 고른 옵션을 유지한 채 1단계로 돌아간다.
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

  _ExportStep _step = _ExportStep.options;
  CompareExportStatus _status = CompareExportStatus.idle;
  Uint8List? _resultBytes;
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
      if (exportOptionsChanged) {
        _defaultsSaveStatus = _DefaultsSaveStatus.idle;
      }
    });
  }

  String _defaultsSaveStatusLabel() {
    switch (_defaultsSaveStatus) {
      case _DefaultsSaveStatus.idle:
        return '현재 포함 옵션을 다음 내보내기의 기본값으로 저장할 수 있어요.';
      case _DefaultsSaveStatus.saving:
        return '기본 내보내기 옵션을 저장하고 있어요.';
      case _DefaultsSaveStatus.success:
        return '기본 내보내기 옵션으로 저장했어요.';
      case _DefaultsSaveStatus.failure:
        return '기본값 저장에 실패했어요. 다시 시도해주세요.';
    }
  }

  Future<void> _saveOptionsAsDefaults() async {
    if (_defaultsSaveStatus == _DefaultsSaveStatus.saving) return;
    setState(() => _defaultsSaveStatus = _DefaultsSaveStatus.saving);
    final logger = ref.read(appLoggerProvider);
    logger.phase('compare.export.defaults.save', LogPhase.start);
    // 저장은 큐가 순서대로 이어서 처리하고 결과를 상태로 돌려준다. 예외가
    // 아니라 저장 상태로 판정하므로 조용히 실패한 저장을 놓치지 않는다.
    final result = await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (settings) => settings.copyWith(defaultExportOptions: _options),
        );
    logger.phase(
      'compare.export.defaults.save',
      result.isFailure ? LogPhase.failure : LogPhase.success,
    );
    if (!mounted) return;
    setState(
      () => _defaultsSaveStatus = result.isFailure
          ? _DefaultsSaveStatus.failure
          : _DefaultsSaveStatus.success,
    );
  }

  String _fileName(CompareExportRequest req) {
    final fmt = DateFormat('yyyyMMdd');
    return 'compare_${req.direction.key}_'
        '${fmt.format(req.beforeRecord.shotAt)}_${fmt.format(req.afterRecord.shotAt)}';
  }

  String _statusLabel() {
    switch (_status) {
      case CompareExportStatus.idle:
        return '아직 미리보기를 만들지 않았어요.';
      case CompareExportStatus.generating:
        return '비교 이미지를 만들고 있어요.';
      case CompareExportStatus.success:
        return '미리보기를 만들었어요.';
      case CompareExportStatus.failure:
        return '이미지를 만들지 못했어요.';
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
    });
    logger.phase('compare.export.generate', LogPhase.start);
    try {
      // 가려진 구성 위젯에 들어갈 두 사진을 먼저 끝까지 읽는다. 읽지 못하면
      // 빈 칸이 찍힌 이미지를 성공으로 넘기지 않고 실패로 보낸다.
      final load = ref.read(comparePhotoLoaderProvider);
      await Future.wait([
        load(context, req.beforePhoto),
        load(context, req.afterPhoto),
      ]);
      if (!mounted || generationToken != _generationToken) return;
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
        _step = _ExportStep.preview;
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
      });
      // 화면에는 고정 문구만 보이고, 원인은 로그에만 남긴다.
      logger.error('compare.export.generate', err: e.runtimeType.toString());
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
      messenger.showSnackBar(const SnackBar(content: Text('사진 보관함에 저장했어요.')));
    } catch (e) {
      logger.phase('compare.export.save', LogPhase.failure);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('저장에 실패했어요. 다시 시도해주세요.')),
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
        const SnackBar(content: Text('공유에 실패했어요. 다시 시도해주세요.')),
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
        ? lessonDate(req.beforeRecord.shotAt)
        : '';
    final afterDate = _options.includeShotDate
        ? lessonDate(req.afterRecord.shotAt)
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
    final members = req.beforeRecord.memberId == null
        ? null
        : ref.watch(membersProvider).valueOrNull;
    String? name(PhotoRecord r) =>
        members?.where((m) => m.id == r.memberId).firstOrNull?.name ??
        r.label?.trim();
    final before = name(req.beforeRecord);
    final after = name(req.afterRecord);
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
        message: '비교 정보를 불러오지 못했어요. 사진 비교 화면에서 다시 진입해주세요.',
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

  /// 미리보기 단계에서 구성 단계로 돌아간다. 고른 옵션은 그대로 두고, 이미
  /// 만든 결과만 버린다(옵션이 바뀔 수 있으므로 다시 만든다).
  void _backToOptions() {
    setState(() {
      _step = _ExportStep.options;
      _generationToken++;
      _resultBytes = null;
      _status = CompareExportStatus.idle;
    });
  }

  /// 같은 두 기록·같은 수업 단계에서 다른 방향으로 바꾼다. 사진이 바뀌므로
  /// 확대·이동은 처음 상태(사진 전체)로 돌린다.
  void _changeDirection(
    CompareExportRequest req,
    BodyDirection direction,
    List<BodyPhoto> beforePhotos,
    List<BodyPhoto> afterPhotos,
  ) {
    if (direction == req.direction) return;
    final before = photoForPhaseDirection(
      beforePhotos,
      req.beforePhoto.phase,
      direction,
    );
    final after = photoForPhaseDirection(
      afterPhotos,
      req.afterPhoto.phase,
      direction,
    );
    if (before == null || after == null) return;
    _updateComposition(() {
      _request = CompareExportRequest(
        beforeRecord: req.beforeRecord,
        afterRecord: req.afterRecord,
        beforePhoto: before,
        afterPhoto: after,
        direction: direction,
        beforeMatrix: Matrix4.identity(),
        afterMatrix: Matrix4.identity(),
        grid: req.grid,
        showGrid: req.showGrid,
        mode: req.mode,
        overlayOpacity: req.overlayOpacity,
        sliderPosition: req.sliderPosition,
        panePhotoSize: req.panePhotoSize,
      );
      _previewBeforeCtrl!.value = Matrix4.identity();
      _previewAfterCtrl!.value = Matrix4.identity();
    });
  }

  String? _memberName(CompareExportRequest? req) {
    final memberId = req?.beforeRecord.memberId;
    if (memberId == null) return null;
    final members = ref.watch(membersProvider).valueOrNull;
    return members?.where((m) => m.id == memberId).firstOrNull?.name;
  }

  PreferredSizeWidget _appBar(CompareExportRequest? req) {
    if (_step == _ExportStep.preview) {
      return AppBar(
        title: const Text('공유 미리보기'),
        actions: [
          Semantics(
            identifier: 'compare.export.edit.button',
            button: true,
            label: '공유 이미지 구성 수정',
            excludeSemantics: true,
            child: TextButton(
              key: const ValueKey('compare.export.edit.button'),
              onPressed: _backToOptions,
              child: const Text('구성 수정'),
            ),
          ),
          const SizedBox(width: AppSpacing.sp2),
        ],
      );
    }
    final name = _memberName(req);
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('공유 이미지 구성'),
          if (name != null)
            Text(
              '$name 회원',
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
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
    Widget? bottom;
    if (!_settingsInitialized) {
      body = const Center(
        key: ValueKey('screen.compare.export.status'),
        child: CircularProgressIndicator(),
      );
    } else if (req != null) {
      final bytes = _resultBytes;
      if (_step == _ExportStep.preview && bytes != null) {
        body = _buildPreview(bytes);
        bottom = _previewActions();
      } else {
        body = _buildOptions(req);
        bottom = _optionsActions();
      }
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
          message: '사진 비교 화면에서 공유 이미지 만들기를 눌러 진입해주세요.',
          backButtonId: 'compare.export.backToDates.button',
        );
      }
    }
    return PopScope(
      // 미리보기에서 뒤로 가면 화면을 닫지 않고 구성 단계로 돌아간다.
      canPop: _step == _ExportStep.options,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToOptions();
      },
      child: Semantics(
        identifier: CompareExportScreen.screenId,
        container: true,
        label: _step == _ExportStep.preview ? '공유 미리보기' : '공유 이미지 구성',
        child: Scaffold(
          key: const ValueKey(CompareExportScreen.screenId),
          appBar: _appBar(req),
          body: body,
          bottomNavigationBar: bottom,
        ),
      ),
    );
  }

  Widget _optionsActions() {
    final generating = _status == CompareExportStatus.generating;
    final failed = _status == CompareExportStatus.failure;
    final label = generating ? '이미지 만드는 중' : (failed ? '다시 시도' : '미리보기 만들기');
    return BottomActionBar(
      identifier: 'compare.export.options.actions',
      primary: Semantics(
        identifier: 'compare.export.generate.button',
        button: true,
        enabled: !generating,
        label: label,
        excludeSemantics: true,
        child: FilledButton.icon(
          key: const ValueKey('compare.export.generate.button'),
          onPressed: generating ? null : _generate,
          icon: generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(failed ? Icons.refresh : Icons.arrow_forward),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _previewActions() {
    return BottomActionBar(
      identifier: 'compare.export.preview.actions',
      secondary: Semantics(
        identifier: 'compare.export.save.button',
        button: true,
        label: '기기에 저장',
        excludeSemantics: true,
        child: OutlinedButton.icon(
          key: const ValueKey('compare.export.save.button'),
          onPressed: _resultBytes == null ? null : _save,
          icon: const Icon(Icons.download_outlined),
          label: const Text('기기에 저장'),
        ),
      ),
      primary: Semantics(
        identifier: 'compare.export.share.button',
        button: true,
        label: '외부 앱으로 공유',
        excludeSemantics: true,
        child: FilledButton.icon(
          key: const ValueKey('compare.export.share.button'),
          onPressed: _resultBytes == null ? null : _share,
          icon: const Icon(Icons.share_outlined),
          label: const Text('공유'),
        ),
      ),
    );
  }

  /// 2단계: 실제로 만든 이미지 바이트를 그대로 보여준다. 미리보기가 곧
  /// 결과물이라 화면 구도와 저장·공유되는 구도가 어긋날 수 없다.
  Widget _buildPreview(Uint8List bytes) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: AppSpacing.content,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이 이미지가 그대로 공유되거나 저장돼요.',
              key: const ValueKey('compare.export.preview.hint'),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sp3),
            Expanded(
              child: Center(
                child: Semantics(
                  identifier: 'compare.export.result.thumbnail',
                  image: true,
                  label: '만든 공유 이미지',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Image.memory(
                      bytes,
                      key: const ValueKey('compare.export.result.thumbnail'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1단계: 방향과 표시 항목을 고른다.
  ///
  /// 캡처할 구성 위젯은 화면 뒤에 실제로 그려 둔다(가려진 채 페인트됨).
  /// RepaintBoundary는 그려져 있어야 캡처할 수 있고, 사용자에게는 2단계에서
  /// 캡처된 바이트만 보여준다.
  Widget _buildOptions(CompareExportRequest req) {
    return Stack(
      children: [
        Positioned(
          left: AppSpacing.sp4,
          right: AppSpacing.sp4,
          top: 0,
          child: IgnorePointer(
            child: ExcludeSemantics(child: _buildComposition(req)),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: _buildOptionsList(req),
          ),
        ),
      ],
    );
  }

  Widget? _statusBanner() {
    final colors = context.colors;
    final Widget content;
    switch (_status) {
      case CompareExportStatus.idle:
      case CompareExportStatus.success:
        return null;
      case CompareExportStatus.generating:
        content = _banner(
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
          leading: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: '비교 이미지를 만들고 있어요',
          body: '잠시만 기다리면 미리보기가 준비돼요.',
        );
      case CompareExportStatus.failure:
        content = _banner(
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
          leading: Icon(Icons.error_outline, color: colors.error),
          title: '이미지를 만들지 못했어요',
          body: '고른 기록과 설정은 그대로 있어요. 아래 다시 시도를 눌러주세요.',
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sp4),
      child: Semantics(
        identifier: 'screen.compare.export.status',
        container: true,
        liveRegion: true,
        label: '이미지 생성 상태',
        value: _statusLabel(),
        child: KeyedSubtree(
          key: const ValueKey('screen.compare.export.status'),
          child: content,
        ),
      ),
    );
  }

  Widget _banner({
    required Color background,
    required Color foreground,
    required Widget leading,
    required String title,
    required String body,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdAll,
      ),
      child: Padding(
        padding: AppSpacing.content,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.sp3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.texts.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sp1),
                  Text(
                    body,
                    style: context.texts.bodyMedium?.copyWith(
                      color: foreground,
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

  Widget _card({required String id, String? title, required Widget child}) {
    return Semantics(
      identifier: id,
      container: true,
      child: Card(
        key: ValueKey(id),
        margin: const EdgeInsets.only(bottom: AppSpacing.sp4),
        child: Padding(
          padding: AppSpacing.content,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: context.texts.labelLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp2),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }

  String _recordLabel(PhotoRecord record, BodyPhoto photo) {
    final phase = phases[photo.phase];
    final date = _summaryDate.format(record.shotAt);
    return phase == null ? date : '$date ($phase)';
  }

  Widget _buildOptionsList(CompareExportRequest req) {
    final beforePhotos = ref
        .watch(recordPhotosProvider(req.beforeRecord.id))
        .valueOrNull;
    final afterPhotos = ref
        .watch(recordPhotosProvider(req.afterRecord.id))
        .valueOrNull;
    final directions = (beforePhotos == null || afterPhotos == null)
        ? <BodyDirection>[req.direction]
        : pairedDirections(
            beforePhotos: beforePhotos,
            beforePhase: req.beforePhoto.phase,
            afterPhotos: afterPhotos,
            afterPhase: req.afterPhoto.phase,
          );
    if (!directions.contains(req.direction)) {
      directions.insert(0, req.direction);
    }
    final canChangeDirection =
        directions.length > 1 && beforePhotos != null && afterPhotos != null;
    final label = _labelText(req);
    final hasMemo = _hasMemo(req);
    final banner = _statusBanner();
    final texts = context.texts;
    final mutedStyle = texts.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );

    return SingleChildScrollView(
      key: const ValueKey('compare.export.options.scroll'),
      padding: AppSpacing.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?banner,
          _card(
            id: 'compare.export.target',
            title: '비교 대상 기록',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sp2,
                  runSpacing: AppSpacing.sp1,
                  children: [
                    Text(
                      _recordLabel(req.beforeRecord, req.beforePhoto),
                      style: context.numericTexts.labelLarge,
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: context.colors.onSurfaceVariant,
                    ),
                    Text(
                      _recordLabel(req.afterRecord, req.afterPhoto),
                      style: context.numericTexts.labelLarge.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sp1),
                Text(req.mode.label, style: mutedStyle),
              ],
            ),
          ),
          _card(
            id: 'compare.export.direction.card',
            title: '비교 방향',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DirectionStepper(
                  identifier: 'compare.export.direction',
                  selected: req.direction,
                  directions: directions,
                  onSelected: canChangeDirection
                      ? (d) =>
                            _changeDirection(req, d, beforePhotos, afterPhotos)
                      : null,
                ),
                const SizedBox(height: AppSpacing.sp2),
                Text(
                  canChangeDirection
                      ? '양쪽 기록에 모두 있는 방향만 고를 수 있어요. 방향을 바꾸면 확대·이동은 처음 상태로 돌아가요.'
                      : '양쪽 기록에 함께 있는 방향은 이것뿐이에요.',
                  style: mutedStyle,
                ),
              ],
            ),
          ),
          _card(
            id: 'compare.export.items',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledSwitch(
                  id: 'compare.export.date.toggle',
                  title: '레슨 날짜·시간 표시',
                  subtitle: '사진 위에 레슨 날짜와 시작 시간을 넣어요',
                  value: _options.includeShotDate,
                  onChanged: (v) => _updateComposition(
                    () => _options = _options.copyWith(includeShotDate: v),
                    exportOptionsChanged: true,
                  ),
                ),
                LabeledSwitch(
                  id: 'compare.export.label.toggle',
                  title: '회원 이름 표시',
                  subtitle: label.isEmpty
                      ? '기록에 연결된 이름이 없어요'
                      : '‘$label’ 문구가 들어가요',
                  value: _options.includeLabel,
                  onChanged: (v) => _updateComposition(
                    () => _options = _options.copyWith(includeLabel: v),
                    exportOptionsChanged: true,
                  ),
                ),
                LabeledSwitch(
                  id: 'compare.export.memo.toggle',
                  title: '일지 메모 표시',
                  subtitle: hasMemo ? '기록과 사진 메모를 사진 아래에 넣어요' : '작성된 메모가 없어요',
                  value: _options.includeMemo,
                  onChanged: (v) => _updateComposition(
                    () => _options = _options.copyWith(includeMemo: v),
                    exportOptionsChanged: true,
                  ),
                ),
                LabeledSwitch(
                  id: 'compare.export.grid.toggle',
                  title: '격자 표시',
                  subtitle: '비교 화면과 같은 격자를 사진 위에 그려요',
                  value: _options.includeGrid,
                  onChanged: (v) => _updateComposition(
                    () => _options = _options.copyWith(includeGrid: v),
                    exportOptionsChanged: true,
                  ),
                ),
                const Divider(height: AppSpacing.sp4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp4,
                  ),
                  child: Text(
                    '이름과 메모는 기본으로 넣지 않아요.',
                    key: const ValueKey('compare.export.privacy.note'),
                    style: mutedStyle,
                  ),
                ),
                const SizedBox(height: AppSpacing.sp3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sp4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        identifier: 'compare.export.defaults.save.button',
                        label: '현재 표시 항목을 기본값으로 저장',
                        enabled:
                            _defaultsSaveStatus != _DefaultsSaveStatus.saving,
                        child: OutlinedButton.icon(
                          key: const ValueKey(
                            'compare.export.defaults.save.button',
                          ),
                          onPressed:
                              _defaultsSaveStatus == _DefaultsSaveStatus.saving
                              ? null
                              : _saveOptionsAsDefaults,
                          icon:
                              _defaultsSaveStatus == _DefaultsSaveStatus.saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('현재 옵션을 기본값으로 저장'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sp1),
                      Semantics(
                        identifier: 'compare.export.defaults.save.status',
                        label: '기본 내보내기 옵션 저장 상태',
                        value: _defaultsSaveStatusLabel(),
                        child: Text(
                          _defaultsSaveStatusLabel(),
                          key: const ValueKey(
                            'compare.export.defaults.save.status',
                          ),
                          style: mutedStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _summaryDate = DateFormat('yyyy.MM.dd');
