import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import 'compare_export_models.dart';
import 'compare_providers.dart';
import 'widgets/compare_missing_context.dart';
import 'widgets/compare_photo_pane.dart';
import 'widgets/labeled_switch.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

enum _CompareMode { sideBySide, overlay, slider }

/// 14. 전후 사진 비교 화면. MVP.md 7.2~7.5.
///
/// 좌우 비교(이전=왼쪽/이후=오른쪽)를 기본으로 제공한다. 겹쳐 보기/슬라이더
/// 비교는 4순위 기능이라 진입점만 두고 '준비 중'으로 표시한다(MVP.md 7.3/7.4).
class CompareViewScreen extends ConsumerWidget {
  static const screenId = 'screen.compare.view';

  final String memberId;

  const CompareViewScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = GoRouterState.of(context).uri.queryParameters;
    final directionKey = query[AppParams.direction];
    final beforePhotoId = query[AppParams.beforePhotoId];
    final afterPhotoId = query[AppParams.afterPhotoId];

    final Widget body;
    if (directionKey == null || beforePhotoId == null || afterPhotoId == null) {
      body = CompareMissingContext(
        memberId: memberId,
        backButtonId: 'compare.view.backToDates.button',
      );
    } else {
      body = _CompareViewBody(
        memberId: memberId,
        direction: BodyDirection.fromKey(directionKey),
        bundleKey: (
          memberId: memberId,
          beforePhotoId: beforePhotoId,
          afterPhotoId: afterPhotoId,
        ),
      );
    }

    return Semantics(
      identifier: screenId,
      container: true,
      label: '전후 사진 비교',
      child: Scaffold(
        key: const ValueKey(screenId),
        appBar: AppBar(title: const Text('전후 사진 비교')),
        body: body,
      ),
    );
  }
}

class _CompareViewBody extends ConsumerStatefulWidget {
  final String memberId;
  final BodyDirection direction;
  final CompareViewKey bundleKey;

  const _CompareViewBody({
    required this.memberId,
    required this.direction,
    required this.bundleKey,
  });

  @override
  ConsumerState<_CompareViewBody> createState() => _CompareViewBodyState();
}

class _CompareViewBodyState extends ConsumerState<_CompareViewBody> {
  late final TransformationController _beforeCtrl;
  late final TransformationController _afterCtrl;
  bool _sync = true;
  bool _showGrid = false;
  GridSettings _grid = GridSettings.defaults;
  bool _gridInitialized = false;
  _CompareMode _mode = _CompareMode.sideBySide;
  bool _applyingSync = false;

  /// 실제 렌더링된 사진 프레임 크기. 생성 화면이 같은 크기로 재현해
  /// 화면 구도 = 생성 이미지 구도를 보장한다(MVP.md 15장).
  Size? _panePhotoSize;

  @override
  void initState() {
    super.initState();
    _beforeCtrl = TransformationController();
    _afterCtrl = TransformationController();
    _beforeCtrl.addListener(_onBeforeChanged);
    _afterCtrl.addListener(_onAfterChanged);
  }

  @override
  void dispose() {
    _beforeCtrl.removeListener(_onBeforeChanged);
    _afterCtrl.removeListener(_onAfterChanged);
    _beforeCtrl.dispose();
    _afterCtrl.dispose();
    super.dispose();
  }

  void _onBeforeChanged() {
    if (!_sync || _applyingSync) return;
    if (_afterCtrl.value == _beforeCtrl.value) return;
    _applyingSync = true;
    _afterCtrl.value = _beforeCtrl.value.clone();
    _applyingSync = false;
  }

  void _onAfterChanged() {
    if (!_sync || _applyingSync) return;
    if (_beforeCtrl.value == _afterCtrl.value) return;
    _applyingSync = true;
    _beforeCtrl.value = _afterCtrl.value.clone();
    _applyingSync = false;
  }

  void _toggleSync(bool value) {
    setState(() => _sync = value);
    if (value) {
      _afterCtrl.value = _beforeCtrl.value.clone();
    }
  }

  Future<void> _loadCaptureGrid() async {
    final loaded = await ref.read(gridSettingsServiceProvider).load();
    if (!mounted) return;
    setState(() => _grid = loaded);
  }

  void _goExport(CompareViewBundle bundle) {
    final request = CompareExportRequest(
      member: bundle.member,
      beforeRecord: bundle.beforeRecord,
      afterRecord: bundle.afterRecord,
      beforePhoto: bundle.beforePhoto,
      afterPhoto: bundle.afterPhoto,
      direction: widget.direction,
      beforeMatrix: _beforeCtrl.value.clone(),
      afterMatrix: _afterCtrl.value.clone(),
      grid: _grid,
      showGrid: _showGrid,
      panePhotoSize: _panePhotoSize,
    );
    context.pushNamed(
      AppRoutes.compareExport,
      pathParameters: {AppParams.memberId: widget.memberId},
      queryParameters: {
        AppParams.direction: widget.direction.key,
        AppParams.beforePhotoId: bundle.beforePhoto.id,
        AppParams.afterPhotoId: bundle.afterPhoto.id,
      },
      extra: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(compareViewBundleProvider(widget.bundleKey));

    return bundleAsync.when(
      loading: () => const Center(
        key: ValueKey('screen.compare.view.status'),
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Column(
          key: const ValueKey('screen.compare.view.status'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('비교 정보를 불러오지 못했습니다.'),
            TextButton(
              key: const ValueKey('compare.view.retry.button'),
              onPressed: () =>
                  ref.invalidate(compareViewBundleProvider(widget.bundleKey)),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      data: (bundle) {
        if (!_gridInitialized) {
          _grid = bundle.defaultGrid;
          _gridInitialized = true;
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _ModeSelector(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ),
            Expanded(
              child: switch (_mode) {
                _CompareMode.sideBySide => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ComparePhotoPane(
                            label: '이전',
                            dateLabel:
                                _dateFormat.format(bundle.beforeRecord.shotAt),
                            photo: bundle.beforePhoto,
                            controller: _beforeCtrl,
                            interactive: true,
                            gridSettings: _grid,
                            showGrid: _showGrid,
                            paneIdentifier: 'compare.before',
                            onPhotoBoxSize: (size) => _panePhotoSize = size,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ComparePhotoPane(
                            label: '이후',
                            dateLabel:
                                _dateFormat.format(bundle.afterRecord.shotAt),
                            photo: bundle.afterPhoto,
                            controller: _afterCtrl,
                            interactive: true,
                            gridSettings: _grid,
                            showGrid: _showGrid,
                            paneIdentifier: 'compare.after',
                          ),
                        ),
                      ],
                    ),
                  ),
                _CompareMode.overlay => const _NotReadyNotice(
                    identifier: 'compare.overlay.placeholder',
                    label: '겹쳐 보기',
                  ),
                _CompareMode.slider => const _NotReadyNotice(
                    identifier: 'compare.slider.placeholder',
                    label: '슬라이더 비교',
                  ),
              },
            ),
            _Controls(
              sync: _sync,
              onSyncChanged: _toggleSync,
              showGrid: _showGrid,
              onShowGridChanged: (v) => setState(() => _showGrid = v),
              grid: _grid,
              onGridChanged: (g) => setState(() => _grid = g),
              onLoadCaptureGrid: _loadCaptureGrid,
              onExport: () => _goExport(bundle),
            ),
          ],
        );
      },
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final _CompareMode mode;
  final ValueChanged<_CompareMode> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'compare.mode.selector',
      label: '비교 방식 선택',
      child: Wrap(
        spacing: 8,
        children: [
          _chip('compare.mode.sideBySide.button', '좌우 비교', _CompareMode.sideBySide),
          _chip('compare.mode.overlay.button', '겹쳐 보기', _CompareMode.overlay),
          _chip('compare.mode.slider.button', '슬라이더 비교', _CompareMode.slider),
        ],
      ),
    );
  }

  Widget _chip(String id, String label, _CompareMode value) {
    final selected = mode == value;
    return Semantics(
      identifier: id,
      label: label,
      selected: selected,
      child: ChoiceChip(
        key: ValueKey(id),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(value),
      ),
    );
  }
}

class _NotReadyNotice extends StatelessWidget {
  final String identifier;
  final String label;

  const _NotReadyNotice({required this.identifier, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        identifier: identifier,
        label: '$label, 준비 중인 기능입니다',
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: ValueKey(identifier),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, size: 32),
              const SizedBox(height: 8),
              Text('$label 기능은 준비 중입니다.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool sync;
  final ValueChanged<bool> onSyncChanged;
  final bool showGrid;
  final ValueChanged<bool> onShowGridChanged;
  final GridSettings grid;
  final ValueChanged<GridSettings> onGridChanged;
  final VoidCallback onLoadCaptureGrid;
  final VoidCallback onExport;

  const _Controls({
    required this.sync,
    required this.onSyncChanged,
    required this.showGrid,
    required this.onShowGridChanged,
    required this.grid,
    required this.onGridChanged,
    required this.onLoadCaptureGrid,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledSwitch(
              id: 'compare.sync.toggle',
              title: '확대/이동 동기화',
              subtitle: '켜면 두 사진을 같은 배율/위치로 함께 조작합니다.',
              value: sync,
              onChanged: onSyncChanged,
            ),
            LabeledSwitch(
              id: 'compare.grid.toggle',
              title: '격자 표시',
              value: showGrid,
              onChanged: onShowGridChanged,
            ),
            if (showGrid) ...[
              _GridSlider(
                id: 'compare.grid.opacity.slider',
                label: '투명도',
                value: grid.opacity,
                min: 0.1,
                max: 1.0,
                onChanged: (v) => onGridChanged(grid.copyWith(opacity: v)),
              ),
              _GridSlider(
                id: 'compare.grid.linewidth.slider',
                label: '선 굵기',
                value: grid.lineWidth,
                min: 0.5,
                max: 5.0,
                onChanged: (v) => onGridChanged(grid.copyWith(lineWidth: v)),
              ),
              _GridSlider(
                id: 'compare.grid.spacing.slider',
                label: '간격',
                value: grid.spacing,
                min: 10.0,
                max: 120.0,
                onChanged: (v) => onGridChanged(grid.copyWith(spacing: v)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  identifier: 'compare.grid.load.button',
                  label: '촬영 격자 설정 불러오기',
                  child: TextButton(
                    key: const ValueKey('compare.grid.load.button'),
                    onPressed: onLoadCaptureGrid,
                    child: const Text('촬영 격자 설정 불러오기'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                identifier: 'compare.export.button',
                label: '비교 이미지 생성',
                child: ElevatedButton.icon(
                  key: const ValueKey('compare.export.button'),
                  onPressed: onExport,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('비교 이미지 생성'),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _GridSlider extends StatelessWidget {
  final String id;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _GridSlider({
    required this.id,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      label: label,
      value: value.toStringAsFixed(1),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label)),
          Expanded(
            child: Slider(
              key: ValueKey(id),
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
