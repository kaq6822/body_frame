import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:body_frame/core/models/models.dart';
import '../providers/capture_providers.dart';
import 'async_status_indicator.dart';

/// 격자 표시/투명도/굵기/간격/색상 설정 패널.
///
/// [gridSettingsControllerProvider]가 shared_preferences에 즉시 영속화하므로
/// 앱을 종료해도 마지막 설정이 유지된다.
class GridSettingsPanel extends ConsumerWidget {
  const GridSettingsPanel({super.key});

  static const _presetColors = <String, Color>{
    'white': Colors.white,
    'yellow': Colors.yellow,
    'red': Colors.redAccent,
    'cyan': Colors.cyanAccent,
    'black': Colors.black,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gridSettingsControllerProvider);
    final notifier = ref.read(gridSettingsControllerProvider.notifier);

    return async.when(
      data: (settings) => _buildControls(settings, notifier),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: AsyncStatusIndicator(
          statusId: 'capture.grid.settings.status',
          status: AsyncStatus.busy,
          busyLabel: '격자 설정을 불러오는 중입니다.',
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: AsyncStatusIndicator(
          statusId: 'capture.grid.settings.status',
          status: AsyncStatus.failure,
          failureMessage: '격자 설정을 불러오지 못했습니다.',
          onRetry: notifier.retry,
        ),
      ),
    );
  }

  Widget _buildControls(GridSettings settings, GridSettingsController notifier) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                identifier: 'capture.grid.toggle',
                label: '격자 표시',
                toggled: settings.visible,
                child: Switch(
                  key: const ValueKey('capture.grid.toggle'),
                  value: settings.visible,
                  onChanged: (value) =>
                      notifier.update((s) => s.copyWith(visible: value)),
                ),
              ),
              const SizedBox(width: 8),
              const Text('격자 표시'),
            ],
          ),
          _buildSlider(
            id: 'capture.grid.opacity.slider',
            label: '투명도',
            value: settings.opacity,
            min: 0.1,
            max: 1.0,
            onChanged: (value) =>
                notifier.update((s) => s.copyWith(opacity: value)),
          ),
          _buildSlider(
            id: 'capture.grid.lineWidth.slider',
            label: '선 굵기',
            value: settings.lineWidth,
            min: 0.5,
            max: 5.0,
            onChanged: (value) =>
                notifier.update((s) => s.copyWith(lineWidth: value)),
          ),
          _buildSlider(
            id: 'capture.grid.spacing.slider',
            label: '간격',
            value: settings.spacing,
            min: 10.0,
            max: 120.0,
            onChanged: (value) =>
                notifier.update((s) => s.copyWith(spacing: value)),
          ),
          const SizedBox(height: 8),
          const Text('색상'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: _presetColors.entries.map((entry) {
              final colorValue = entry.value.toARGB32();
              final isSelected = settings.colorValue == colorValue;
              final id = 'capture.grid.color.${entry.key}.button';
              return Semantics(
                identifier: id,
                button: true,
                selected: isSelected,
                label: '격자 색상 ${entry.key}',
                child: GestureDetector(
                  key: ValueKey(id),
                  onTap: () =>
                      notifier.update((s) => s.copyWith(colorValue: colorValue)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.blueAccent : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('capture.grid.reset.button'),
              onPressed: notifier.reset,
              child: const Text('설정 초기화'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String id,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final clamped = value.clamp(min, max).toDouble();
    return Semantics(
      identifier: id,
      label: label,
      value: clamped.toStringAsFixed(1),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Slider(
              key: ValueKey(id),
              value: clamped,
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
