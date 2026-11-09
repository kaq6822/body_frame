import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bottom_action_bar.dart';
import '../../core/widgets/direction_stepper.dart';
import '../members/member_providers.dart';
import '../members/ui.dart' show lessonDate;
import 'compare_export_models.dart';
import 'compare_logic.dart';
import 'compare_providers.dart';
import 'widgets/compare_layered_pane.dart';
import 'widgets/compare_missing_context.dart';
import 'widgets/compare_photo_pane.dart';
import 'widgets/labeled_switch.dart';

/// 전후 사진 비교 화면.
///
/// 나란히 보기, 투명도를 조절하는 겹쳐 보기, 경계를 움직이는 슬라이더 비교를
/// 제공한다. 위쪽 방향 단계로 같은 두 기록의 다른 방향을 바로 볼 수 있다.
class CompareViewScreen extends ConsumerWidget {
  static const screenId = 'screen.compare.view';

  const CompareViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = GoRouterState.of(context).uri.queryParameters;
    final directionKey = query[AppParams.direction];
    final beforePhotoId = query[AppParams.beforePhotoId];
    final afterPhotoId = query[AppParams.afterPhotoId];

    if (directionKey == null || beforePhotoId == null || afterPhotoId == null) {
      return _screen(
        Scaffold(
          key: const ValueKey(screenId),
          appBar: AppBar(title: const Text('사진 비교')),
          body: const CompareMissingContext(
            backButtonId: 'compare.view.backToDates.button',
          ),
        ),
      );
    }
    return _screen(
      _CompareViewBody(
        direction: BodyDirection.fromKey(directionKey),
        bundleKey: (beforePhotoId: beforePhotoId, afterPhotoId: afterPhotoId),
      ),
    );
  }

  static Widget _screen(Widget child) => Semantics(
    identifier: screenId,
    container: true,
    label: '사진 비교',
    child: child,
  );
}

class _CompareViewBody extends ConsumerStatefulWidget {
  final BodyDirection direction;
  final CompareViewKey bundleKey;

  const _CompareViewBody({required this.direction, required this.bundleKey});

  @override
  ConsumerState<_CompareViewBody> createState() => _CompareViewBodyState();
}

class _CompareViewBodyState extends ConsumerState<_CompareViewBody> {
  late final TransformationController _beforeCtrl;
  late final TransformationController _afterCtrl;

  /// 화면 안에서 방향을 바꾸면 사진 쌍(키)과 방향이 함께 바뀐다.
  late BodyDirection _direction;
  late CompareViewKey _bundleKey;
  bool _sync = true;

  /// 비교 화면도 다른 사진 보기와 같이 격자를 켠 상태로 시작한다.
  bool _showGrid = true;

  /// 사용자가 격자 표시를 직접 건드렸는지. 생성 화면은 저장된 기본 내보내기
  /// 옵션을 쓰는데, 화면 기본값(켜짐)만으로 그 설정을 덮어쓰지 않게 구분한다.
  bool _gridChoiceTouched = false;
  GridSettings _grid = GridSettings.defaults;
  bool _gridInitialized = false;
  CompareMode _mode = CompareMode.sideBySide;
  double _overlayOpacity = 0.5;
  double _sliderPosition = 0.5;
  bool _applyingSync = false;

  /// 실제 렌더링된 사진 프레임 크기. 생성 화면이 같은 크기로 재현해
  /// 화면 구도 = 생성 이미지 구도를 보장한다.
  Size? _panePhotoSize;

  @override
  void initState() {
    super.initState();
    _direction = widget.direction;
    _bundleKey = widget.bundleKey;
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

  /// 같은 두 기록·같은 수업 단계에서 다른 방향의 사진 쌍으로 바꾼다.
  /// 사진이 바뀌므로 확대·이동은 처음 상태로 돌린다.
  void _changeDirection(
    BodyDirection direction,
    CompareViewBundle bundle,
    List<BodyPhoto> beforePhotos,
    List<BodyPhoto> afterPhotos,
  ) {
    if (direction == _direction) return;
    final before = photoForPhaseDirection(
      beforePhotos,
      bundle.beforePhoto.phase,
      direction,
    );
    final after = photoForPhaseDirection(
      afterPhotos,
      bundle.afterPhoto.phase,
      direction,
    );
    if (before == null || after == null) return;
    setState(() {
      _direction = direction;
      _bundleKey = (beforePhotoId: before.id, afterPhotoId: after.id);
      _panePhotoSize = null;
    });
    _beforeCtrl.value = Matrix4.identity();
    _afterCtrl.value = Matrix4.identity();
  }

  void _goExport(CompareViewBundle bundle) {
    final request = CompareExportRequest(
      beforeRecord: bundle.beforeRecord,
      afterRecord: bundle.afterRecord,
      beforePhoto: bundle.beforePhoto,
      afterPhoto: bundle.afterPhoto,
      direction: _direction,
      beforeMatrix: _beforeCtrl.value.clone(),
      afterMatrix: _afterCtrl.value.clone(),
      grid: _grid,
      showGrid: _gridChoiceTouched ? _showGrid : null,
      mode: _mode,
      overlayOpacity: _overlayOpacity,
      sliderPosition: _sliderPosition,
      panePhotoSize: _panePhotoSize,
    );
    context.pushNamed(
      AppRoutes.compareExport,
      queryParameters: {
        AppParams.direction: _direction.key,
        AppParams.beforePhotoId: bundle.beforePhoto.id,
        AppParams.afterPhotoId: bundle.afterPhoto.id,
      },
      extra: request,
    );
  }

  /// 앱 바 부제에 쓸 회원 이름. 회원 없는 기록이면 null.
  String? _memberName(CompareViewBundle? bundle) {
    final memberId = bundle?.beforeRecord.memberId;
    if (memberId == null) return null;
    final members = ref.watch(membersProvider).valueOrNull;
    return members?.where((m) => m.id == memberId).firstOrNull?.name;
  }

  PreferredSizeWidget _appBar(CompareViewBundle? bundle) {
    final name = _memberName(bundle);
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('사진 비교'),
          if (name != null)
            Text(
              '$name 회원',
              key: const ValueKey('compare.view.member'),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: [
        Semantics(
          identifier: 'compare.view.changeRecords.button',
          button: true,
          label: '비교할 기록 바꾸기',
          excludeSemantics: true,
          child: TextButton.icon(
            key: const ValueKey('compare.view.changeRecords.button'),
            onPressed: () {
              // 기록을 고른 화면(회원 비교 선택·방향 선택)으로 돌아간다.
              if (context.canPop()) context.pop();
            },
            icon: const Icon(Icons.swap_horiz),
            label: const Text('기록 변경'),
          ),
        ),
        const SizedBox(width: AppSpacing.sp2),
      ],
    );
  }

  Widget _exportButton(CompareViewBundle? bundle) => Semantics(
    identifier: 'compare.export.button',
    button: true,
    enabled: bundle != null,
    label: '공유 이미지 만들기',
    excludeSemantics: true,
    child: FilledButton.icon(
      key: const ValueKey('compare.export.button'),
      onPressed: bundle == null ? null : () => _goExport(bundle),
      icon: const Icon(Icons.photo_library_outlined),
      label: const Text('공유 이미지 만들기'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(compareViewBundleProvider(_bundleKey));
    final bundle = bundleAsync.valueOrNull;
    final screen = MediaQuery.sizeOf(context);
    // 가로 화면은 높이가 모자라 위아래로 쌓으면 사진이 손톱만 해진다.
    // 사진은 왼쪽, 방향·컨트롤·버튼은 오른쪽 열에 둔다.
    final landscape = screen.width > screen.height * 1.2;

    final Widget body = bundleAsync.when(
      loading: () => const Center(
        key: ValueKey('screen.compare.view.status'),
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: AppSpacing.content,
          child: Column(
            key: const ValueKey('screen.compare.view.status'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('비교 정보를 불러오지 못했어요.', textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sp2),
              TextButton.icon(
                key: const ValueKey('compare.view.retry.button'),
                onPressed: () =>
                    ref.invalidate(compareViewBundleProvider(_bundleKey)),
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
      data: (bundle) => _buildLoaded(bundle, landscape),
    );

    return Scaffold(
      key: const ValueKey(CompareViewScreen.screenId),
      appBar: _appBar(bundle),
      body: body,
      bottomNavigationBar: landscape || bundle == null
          ? null
          : BottomActionBar(
              identifier: 'compare.view.actions',
              primary: _exportButton(bundle),
            ),
    );
  }

  Widget _buildLoaded(CompareViewBundle bundle, bool landscape) {
    if (!_gridInitialized) {
      _grid = bundle.defaultGrid;
      _gridInitialized = true;
    }
    final beforePhotos = ref
        .watch(recordPhotosProvider(bundle.beforeRecord.id))
        .valueOrNull;
    final afterPhotos = ref
        .watch(recordPhotosProvider(bundle.afterRecord.id))
        .valueOrNull;
    final directions = (beforePhotos == null || afterPhotos == null)
        ? <BodyDirection>[]
        : pairedDirections(
            beforePhotos: beforePhotos,
            beforePhase: bundle.beforePhoto.phase,
            afterPhotos: afterPhotos,
            afterPhase: bundle.afterPhoto.phase,
          );

    // 양쪽에 함께 있는 방향만 보여준다. 하나뿐이면 고를 것이 없어 숨긴다.
    final Widget? stepper = directions.length < 2
        ? null
        : DirectionStepper(
            identifier: 'compare.view.direction',
            selected: _direction,
            directions: directions,
            onSelected: (d) =>
                _changeDirection(d, bundle, beforePhotos!, afterPhotos!),
          );

    final selector = _ModeSelector(
      mode: _mode,
      onChanged: (m) => setState(() => _mode = m),
    );
    final panes = switch (_mode) {
      CompareMode.sideBySide => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ComparePhotoPane(
                label: '이전',
                dateLabel: lessonDate(bundle.beforeRecord.shotAt),
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
                dateLabel: lessonDate(bundle.afterRecord.shotAt),
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
      CompareMode.overlay || CompareMode.slider => Padding(
        padding: const EdgeInsets.all(12),
        child: CompareLayeredPane(
          mode: _mode,
          beforePhoto: bundle.beforePhoto,
          afterPhoto: bundle.afterPhoto,
          beforeDateLabel: lessonDate(bundle.beforeRecord.shotAt),
          afterDateLabel: lessonDate(bundle.afterRecord.shotAt),
          beforeController: _beforeCtrl,
          afterController: _afterCtrl,
          interactive: true,
          gridSettings: _grid,
          showGrid: _showGrid,
          overlayOpacity: _overlayOpacity,
          sliderPosition: _sliderPosition,
          onSliderPositionChanged: (value) =>
              setState(() => _sliderPosition = value.clamp(0.0, 1.0)),
          identifierPrefix: _mode == CompareMode.overlay
              ? 'compare.overlay'
              : 'compare.slider',
          onPhotoBoxSize: (size) => _panePhotoSize = size,
        ),
      ),
    };
    final controls = _Controls(
      mode: _mode,
      overlayOpacity: _overlayOpacity,
      onOverlayOpacityChanged: (value) =>
          setState(() => _overlayOpacity = value.clamp(0.0, 1.0)),
      sliderPosition: _sliderPosition,
      onSliderPositionChanged: (value) =>
          setState(() => _sliderPosition = value.clamp(0.0, 1.0)),
      sync: _sync,
      onSyncChanged: _toggleSync,
      showGrid: _showGrid,
      onShowGridChanged: (v) => setState(() {
        _showGrid = v;
        _gridChoiceTouched = true;
      }),
      grid: _grid,
      onGridChanged: (g) => setState(() => _grid = g),
      onLoadCaptureGrid: _loadCaptureGrid,
    );
    Widget scrollable(Widget child) => Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('compare.controls.scroll'),
        child: child,
      ),
    );
    Widget padded(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sp4,
        AppSpacing.sp2,
        AppSpacing.sp4,
        0,
      ),
      child: child,
    );

    // 컨트롤이 길어지면(격자 켜짐, 작은 화면, 가로 화면) 화면을 넘쳐
    // 사진이 잘린다. 컨트롤은 상한을 두고 스크롤시키되, 사진 영역이 너무
    // 작아지지 않게 상한을 정한다.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (landscape) {
          return Row(
            children: [
              Expanded(child: panes),
              SizedBox(
                width: math.min(360.0, constraints.maxWidth * 0.45),
                child: SafeArea(
                  left: false,
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: scrollable(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (stepper != null) padded(stepper),
                              padded(selector),
                              controls,
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sp4,
                          AppSpacing.sp2,
                          AppSpacing.sp4,
                          AppSpacing.sp2,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: _exportButton(bundle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        final height = constraints.maxHeight;
        final minBody =
            _minCompareBodyHeight + (stepper == null ? 0 : _stepperHeight);
        final controlsMaxHeight = height.isFinite
            ? math.max(height * 0.3, height - minBody)
            : double.infinity;
        return Column(
          children: [
            if (stepper != null) padded(stepper),
            padded(selector),
            Expanded(child: panes),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: controlsMaxHeight),
              child: scrollable(controls),
            ),
          ],
        );
      },
    );
  }
}

/// 방향 단계 한 줄이 차지하는 대략의 높이(논리 px).
const double _stepperHeight = 56;

/// 모드 선택기와 사진 영역이 최소한으로 차지해야 하는 높이(논리 px).
const double _minCompareBodyHeight = 340;

class _ModeSelector extends StatelessWidget {
  final CompareMode mode;
  final ValueChanged<CompareMode> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'compare.mode.selector',
      label: '비교 방식 선택',
      // 큰 글꼴에서 칩이 여러 줄로 쌓이면 사진 칸이 줄어든다. 한 줄을 유지하고
      // 넘치면 가로로 밀어 본다.
      child: SingleChildScrollView(
        key: const ValueKey('compare.mode.scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: [
            _chip(
              'compare.mode.sideBySide.button',
              CompareMode.sideBySide.label,
              CompareMode.sideBySide,
            ),
            _chip(
              'compare.mode.overlay.button',
              CompareMode.overlay.label,
              CompareMode.overlay,
            ),
            _chip(
              'compare.mode.slider.button',
              CompareMode.slider.label,
              CompareMode.slider,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String id, String label, CompareMode value) {
    final selected = mode == value;
    final icon = switch (value) {
      CompareMode.sideBySide => Icons.view_column_outlined,
      CompareMode.overlay => Icons.layers_outlined,
      CompareMode.slider => Icons.compare_outlined,
    };
    return Semantics(
      identifier: id,
      label: label,
      selected: selected,
      child: ChoiceChip(
        key: ValueKey(id),
        // 선택 표시로 칩 폭이 바뀌면 누르는 동안 옆 칩이 밀린다. 체크 대신
        // 색만 바꾸고 아이콘은 항상 둔다.
        showCheckmark: false,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(value),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final CompareMode mode;
  final double overlayOpacity;
  final ValueChanged<double> onOverlayOpacityChanged;
  final double sliderPosition;
  final ValueChanged<double> onSliderPositionChanged;
  final bool sync;
  final ValueChanged<bool> onSyncChanged;
  final bool showGrid;
  final ValueChanged<bool> onShowGridChanged;
  final GridSettings grid;
  final ValueChanged<GridSettings> onGridChanged;
  final VoidCallback onLoadCaptureGrid;

  const _Controls({
    required this.mode,
    required this.overlayOpacity,
    required this.onOverlayOpacityChanged,
    required this.sliderPosition,
    required this.onSliderPositionChanged,
    required this.sync,
    required this.onSyncChanged,
    required this.showGrid,
    required this.onShowGridChanged,
    required this.grid,
    required this.onGridChanged,
    required this.onLoadCaptureGrid,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // 스위치 타일은 자체 가로 여백(16)을 가지므로 바깥 여백은 두지 않고
      // 슬라이더·버튼에만 같은 16을 준다. 모든 컨트롤의 글자 열이 맞는다.
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mode == CompareMode.overlay)
              _GridSlider(
                id: 'compare.overlay.opacity.slider',
                label: '이후 사진 투명도',
                value: overlayOpacity,
                min: 0,
                max: 1,
                format: _percent,
                onChanged: onOverlayOpacityChanged,
              ),
            if (mode == CompareMode.slider)
              _GridSlider(
                id: 'compare.slider.position.slider',
                label: '경계 위치',
                value: sliderPosition,
                min: 0,
                max: 1,
                format: _percent,
                onChanged: onSliderPositionChanged,
              ),
            LabeledSwitch(
              id: 'compare.sync.toggle',
              title: '확대/이동 동기화',
              subtitle: '켜면 두 사진을 같은 배율/위치로 함께 조작해요.',
              value: sync,
              onChanged: onSyncChanged,
            ),
            LabeledSwitch(
              id: 'compare.grid.toggle',
              title: '격자 표시',
              value: showGrid,
              onChanged: onShowGridChanged,
            ),
            if (showGrid)
              // 세부 격자 값은 자주 바꾸지 않으므로 접어 두고 사진 영역을 넓힌다.
              Semantics(
                identifier: 'compare.grid.settings.tile',
                container: true,
                child: ExpansionTile(
                  key: const ValueKey('compare.grid.settings.tile'),
                  title: const Text('격자 세부 설정'),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.only(
                    bottom: AppSpacing.sp2,
                  ),
                  children: [
                    _GridSlider(
                      id: 'compare.grid.opacity.slider',
                      label: '격자 투명도',
                      value: grid.opacity,
                      min: 0.1,
                      max: 1.0,
                      format: _percent,
                      onChanged: (v) =>
                          onGridChanged(grid.copyWith(opacity: v)),
                    ),
                    _GridSlider(
                      id: 'compare.grid.linewidth.slider',
                      label: '선 굵기',
                      value: grid.lineWidth,
                      min: 0.5,
                      max: 5.0,
                      format: (v) => v.toStringAsFixed(1),
                      onChanged: (v) =>
                          onGridChanged(grid.copyWith(lineWidth: v)),
                    ),
                    _GridSlider(
                      id: 'compare.grid.spacing.slider',
                      label: '간격',
                      value: grid.spacing,
                      min: 10.0,
                      max: 120.0,
                      format: (v) => v.round().toString(),
                      onChanged: (v) =>
                          onGridChanged(grid.copyWith(spacing: v)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sp4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          identifier: 'compare.grid.load.button',
                          label: '촬영 화면의 격자 값 가져오기',
                          child: TextButton(
                            key: const ValueKey('compare.grid.load.button'),
                            onPressed: onLoadCaptureGrid,
                            child: const Text('촬영 격자 설정 불러오기'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _percent(double v) => '${(v * 100).round()}%';

class _GridSlider extends StatelessWidget {
  final String id;
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _GridSlider({
    required this.id,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    // 라벨·값 글자는 화면용이고, 읽기는 슬라이더 한 곳에서만 한다.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sp4),
      child: Semantics(
        identifier: id,
        label: label,
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56, maxWidth: 112),
              child: ExcludeSemantics(child: Text(label)),
            ),
            Expanded(
              child: Slider(
                key: ValueKey(id),
                value: clamped,
                min: min,
                max: max,
                semanticFormatterCallback: format,
                onChanged: onChanged,
              ),
            ),
            ExcludeSemantics(
              child: SizedBox(
                width: 48,
                child: Text(
                  format(clamped),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
