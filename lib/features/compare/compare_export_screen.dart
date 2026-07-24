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
import 'compare_export_models.dart';
import 'compare_providers.dart';
import 'services/compare_export_sink.dart';
import 'widgets/compare_missing_context.dart';
import 'widgets/compare_photo_pane.dart';
import 'widgets/labeled_switch.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

/// 비교 이미지 저장 설정 화면.
///
/// 전후 비교 화면(compareView)에서 `extra`로 전달받은 [CompareExportRequest]
/// (확대/이동 값, 격자, 대상 사진 등)를 그대로 재현해 화면 구도와 생성
/// 이미지 구도를 일치시킨다. 포함 항목을 선택한 뒤 RepaintBoundary로
/// 캡처하고, gal/share_plus로 저장·공유한다.
class CompareExportScreen extends ConsumerStatefulWidget {
  static const screenId = 'screen.compare.export';

  final String memberId;

  const CompareExportScreen({super.key, required this.memberId});

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
  String _studioName = '';

  CompareExportStatus _status = CompareExportStatus.idle;
  Uint8List? _resultBytes;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request == null) {
      final extra = GoRouterState.of(context).extra;
      if (extra is CompareExportRequest) {
        _request = extra;
        _previewBeforeCtrl = TransformationController(extra.beforeMatrix.clone());
        _previewAfterCtrl = TransformationController(extra.afterMatrix.clone());
        _options = _options.copyWith(includeGrid: extra.showGrid);
      }
    }
  }

  @override
  void dispose() {
    _previewBeforeCtrl?.dispose();
    _previewAfterCtrl?.dispose();
    super.dispose();
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
    setState(() {
      _status = CompareExportStatus.generating;
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
      if (!mounted) return;
      setState(() {
        _resultBytes = bytes;
        _status = CompareExportStatus.success;
      });
      logger.phase('compare.export.generate', LogPhase.success,
          context: {'bytes': bytes.length});
    } catch (e) {
      if (!mounted) return;
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
      messenger.showSnackBar(const SnackBar(content: Text('저장에 실패했습니다. 다시 시도해 주세요.')));
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
      await sink.share(bytes, name: _fileName(req), text: '체형 변화 비교 이미지');
      logger.phase('compare.export.share', LogPhase.success);
    } catch (e) {
      logger.phase('compare.export.share', LogPhase.failure);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('공유에 실패했습니다. 다시 시도해 주세요.')));
    }
  }

  bool _hasMemo(CompareExportRequest req) {
    return (req.beforeRecord.memo?.isNotEmpty ?? false) ||
        (req.afterRecord.memo?.isNotEmpty ?? false) ||
        (req.beforePhoto.memo?.isNotEmpty ?? false) ||
        (req.afterPhoto.memo?.isNotEmpty ?? false);
  }

  String _memoText(CompareExportRequest req) {
    final parts = <String>[];
    if (req.beforeRecord.memo?.isNotEmpty ?? false) {
      parts.add('이전: ${req.beforeRecord.memo}');
    }
    if (req.afterRecord.memo?.isNotEmpty ?? false) {
      parts.add('이후: ${req.afterRecord.memo}');
    }
    return parts.join('\n');
  }

  Widget _buildComposition(CompareExportRequest req) {
    final beforeCtrl = _previewBeforeCtrl!;
    final afterCtrl = _previewAfterCtrl!;
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
                  '${req.direction.label} 비교',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ComparePhotoPane(
                        label: '이전',
                        dateLabel: _options.includeShotDate
                            ? _dateFormat.format(req.beforeRecord.shotAt)
                            : '',
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
                        dateLabel: _options.includeShotDate
                            ? _dateFormat.format(req.afterRecord.shotAt)
                            : '',
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
                ),
                if (_options.includeMemberName &&
                    (req.member?.name.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('회원: ${req.member!.name}',
                        textAlign: TextAlign.center),
                  ),
                if (_options.includeMemo && _hasMemo(req))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_memoText(req), textAlign: TextAlign.center),
                  ),
                if (_options.includeStudioName && _studioName.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                        Text(_studioName.trim(), textAlign: TextAlign.center),
                  ),
                if (_options.includeWatermark)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'body_frame',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.grey),
                    ),
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
  Widget _buildFallbackFromQuery(BodyDirection direction, String beforeId,
      String afterId) {
    final bundleAsync = ref.watch(compareViewBundleProvider((
      memberId: widget.memberId,
      beforePhotoId: beforeId,
      afterPhotoId: afterId,
    )));
    return bundleAsync.when(
      loading: () => const Center(
        key: ValueKey('screen.compare.export.status'),
        child: CircularProgressIndicator(),
      ),
      error: (e, st) => CompareMissingContext(
        memberId: widget.memberId,
        message: '비교 정보를 불러오지 못했습니다. 전후 사진 비교 화면에서 다시 진입해 주세요.',
        backButtonId: 'compare.export.backToDates.button',
      ),
      data: (bundle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _request != null) return;
          setState(() {
            _request = CompareExportRequest(
              member: bundle.member,
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
    final req = _request;
    Widget body;
    if (req != null) {
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
        body = CompareMissingContext(
          memberId: widget.memberId,
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
            id: 'compare.export.name.toggle',
            title: '회원 이름 포함',
            subtitle: '개인정보 보호를 위해 기본값은 숨김입니다.',
            value: _options.includeMemberName,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(includeMemberName: v)),
          ),
          LabeledSwitch(
            id: 'compare.export.date.toggle',
            title: '촬영일 포함',
            value: _options.includeShotDate,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(includeShotDate: v)),
          ),
          LabeledSwitch(
            id: 'compare.export.memo.toggle',
            title: '메모 포함',
            value: _options.includeMemo,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(includeMemo: v)),
          ),
          LabeledSwitch(
            id: 'compare.export.grid.toggle',
            title: '격자 포함',
            value: _options.includeGrid,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(includeGrid: v)),
          ),
          LabeledSwitch(
            id: 'compare.export.studio.toggle',
            title: '스튜디오명 포함',
            value: _options.includeStudioName,
            onChanged: (v) => setState(
                () => _options = _options.copyWith(includeStudioName: v)),
          ),
          if (_options.includeStudioName)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                identifier: 'compare.export.studio.field',
                label: '스튜디오명 입력',
                child: TextField(
                  key: const ValueKey('compare.export.studio.field'),
                  decoration: const InputDecoration(labelText: '스튜디오명(선택)'),
                  onChanged: (v) => setState(() => _studioName = v),
                ),
              ),
            ),
          LabeledSwitch(
            id: 'compare.export.watermark.toggle',
            title: '앱 워터마크 포함',
            value: _options.includeWatermark,
            onChanged: (v) =>
                setState(() => _options = _options.copyWith(includeWatermark: v)),
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
              onPressed:
                  _status == CompareExportStatus.generating ? null : _generate,
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
